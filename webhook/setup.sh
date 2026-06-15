#!/bin/bash
set -euo pipefail

echo "============================================"
echo "  Caddy Blog Webhook 部署设置向导"
echo "============================================"
echo ""

# 1. 检测环境
if ! command -v node &>/dev/null && ! command -v docker &>/dev/null; then
    echo "错误: 需要 Node.js 或 Docker 来运行 webhook 服务"
    exit 1
fi

# 2. 生成 Webhook Secret
WEBHOOK_SECRET=$(openssl rand -hex 32)
echo "已生成 Webhook Secret: $WEBHOOK_SECRET"
echo ""

# 3. 写入 .env
ENV_FILE="$(dirname "$0")/../.env"
if [ -f "$ENV_FILE" ]; then
    if grep -q "^WEBHOOK_SECRET=" "$ENV_FILE" 2>/dev/null; then
        sed -i "s/^WEBHOOK_SECRET=.*/WEBHOOK_SECRET=$WEBHOOK_SECRET/" "$ENV_FILE"
    else
        echo "" >> "$ENV_FILE"
        echo "# Webhook 密钥（GitHub Webhook 需要与此一致）" >> "$ENV_FILE"
        echo "WEBHOOK_SECRET=$WEBHOOK_SECRET" >> "$ENV_FILE"
    fi
    echo "已将 Webhook Secret 写入 $ENV_FILE"
else
    echo "未找到 .env 文件，请手动创建并添加:"
    echo "  WEBHOOK_SECRET=$WEBHOOK_SECRET"
fi
echo ""

# 4. 启动选项
echo "选择启动方式:"
echo "  [1] 使用 Docker Compose (推荐)"
echo "  [2] 直接运行 Node.js"
echo "  [3] 使用 systemd 服务"
echo ""
read -p "请输入选项 [1-3]: " choice

case "$choice" in
1)
    echo ""
    echo "启动方式: docker compose -f docker-compose.yaml -f webhook/docker-compose.webhook.yaml up -d"
    echo ""
    webhook_dir="$(dirname "$0")"
    (cd "$webhook_dir/.." && docker compose -f docker-compose.yaml -f webhook/docker-compose.webhook.yaml up -d)
    echo "Webhook 已启动，监听 127.0.0.1:9000"
    ;;
2)
    echo ""
    echo "启动方式: nohup node webhook/server.js &"
    (cd "$(dirname "$0")" && nohup node server.js > /tmp/webhook.log 2>&1 &)
    echo "Webhook 已启动 (PID: $!)"
    ;;
3)
    SERVICE_FILE="/etc/systemd/system/caddy-blog-webhook.service"
    echo ""
    echo "创建 systemd 服务: $SERVICE_FILE"
    cat > /tmp/caddy-blog-webhook.service << EOF
[Unit]
Description=Caddy Blog Webhook Deployer
After=network.target

[Service]
Type=simple
User=$(whoami)
WorkingDirectory=$(realpath "$(dirname "$0")")
Environment=WEBHOOK_PORT=9000
Environment=WEBHOOK_SECRET=$WEBHOOK_SECRET
ExecStart=$(which node) $(realpath "$(dirname "$0")/server.js")
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    echo "需要 sudo 权限来安装 systemd 服务:"
    echo "  sudo cp /tmp/caddy-blog-webhook.service $SERVICE_FILE"
    echo "  sudo systemctl daemon-reload"
    echo "  sudo systemctl enable --now caddy-blog-webhook"
    ;;
*)
    echo "无效选项"
    exit 1
    ;;
esac

echo ""
echo "============================================"
echo "  GitHub Webhook 配置"
echo "============================================"
echo ""
echo "在 GitHub 仓库的 Settings > Webhooks 中添加:"
echo ""
echo "  Payload URL:  http://<VPS_IP>:9000/webhook"
echo "  Content type: application/json"
echo "  Secret:       $WEBHOOK_SECRET"
echo "  Events:       Just the push event"
echo ""
echo "安全建议: 在防火墙中限制 9000 端口仅允许 GitHub IP 访问"
echo "  GitHub IP 列表: https://api.github.com/meta"
