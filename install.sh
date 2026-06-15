#!/bin/bash
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
info()  { echo -e "${GREEN}[OK]${NC} $*"; }
error() { echo -e "${RED}[ERR]${NC} $*"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── 1. 检查依赖 ──
echo ""
MISSING=0
command -v docker &>/dev/null || { warn "docker 未安装"; MISSING=1; }
docker compose version &>/dev/null 2>&1 || docker-compose version &>/dev/null 2>&1 || { warn "docker compose 不可用"; MISSING=1; }
[ $MISSING -eq 1 ] && warn "请先安装缺失的依赖，然后重新运行本脚本"
info "依赖检查完成"

# ── 2. 收集信息 ──
echo ""
echo "============================================"
echo "  Caddy + Cloudflare DNS + wg-easy"
echo "============================================"
echo ""

read -r -p "域名: " DOMAIN
[ -z "$DOMAIN" ] && { error "域名不能为空"; exit 1; }

read -r -p "WireGuard 子域名 (默认 wg): " WG_SUBDOMAIN
WG_SUBDOMAIN=${WG_SUBDOMAIN:-wg}

read -r -p "监听端口 (默认 2083): " PORT
PORT=${PORT:-2083}

read -r -p "Cloudflare API Token: " CF_TOKEN
[ -z "$CF_TOKEN" ] && { error "API Token 不能为空"; exit 1; }

read -r -p "wg-easy Host (默认 $DOMAIN): " WG_HOST
WG_HOST=${WG_HOST:-$DOMAIN}

WG_PASSWORD=$(openssl rand -base64 12)
read -r -p "wg-easy 管理员密码 (默认随机: ${WG_PASSWORD:0:8}***): " WG_PASS_INPUT
WG_PASSWORD=${WG_PASS_INPUT:-$WG_PASSWORD}

# 生成 bcrypt 哈希 (wg-easy v14+)
echo "正在生成密码哈希..."
WG_PASSWORD_HASH=$(docker run --rm ghcr.io/wg-easy/wg-easy wgpw "$WG_PASSWORD" 2>/dev/null | grep PASSWORD_HASH | cut -d\' -f2)
if [ -z "$WG_PASSWORD_HASH" ]; then
    # 备选: 用 htpasswd 生成
    WG_PASSWORD_HASH=$(echo "$WG_PASSWORD" | docker run --rm -i httpd:alpine htpasswd -nbB -C 12 '' "$WG_PASSWORD" 2>/dev/null | cut -d: -f2 | sed 's/\$/$$/g')
    [ -z "$WG_PASSWORD_HASH" ] && { error "无法生成密码哈希，跳过"; WG_PASSWORD_HASH="PLACEHOLDER"; }
fi

# ── 3. 替换占位符 ──
sed -i "s/{{WG_SUBDOMAIN}}/$WG_SUBDOMAIN/g" "$SCRIPT_DIR/Caddyfile"
sed -i "s/{{DOMAIN}}/$DOMAIN/g"           "$SCRIPT_DIR/Caddyfile"
sed -i "s/{{PORT}}/$PORT/g"               "$SCRIPT_DIR/Caddyfile"
sed -i "s/{{PORT}}/$PORT/g"               "$SCRIPT_DIR/docker-compose.yaml"
info "Caddyfile / docker-compose.yaml 已配置"

# ── 4. 生成 .env ──
if [ -f "$SCRIPT_DIR/.env" ]; then
    read -r -p ".env 已存在，覆盖? [y/N]: " OVERWRITE
    if [ "$OVERWRITE" != "y" ] && [ "$OVERWRITE" != "Y" ]; then
        info "保留现有 .env"
        SKIP_ENV=1
    fi
fi

if [ "$SKIP_ENV" != "1" ]; then
    cat > "$SCRIPT_DIR/.env" <<EOF
CLOUDFLARE_API_TOKEN=$CF_TOKEN
WG_HOST=$WG_HOST
WG_PASSWORD_HASH=$WG_PASSWORD_HASH
EOF
    info ".env 已生成"
fi

# ── 5. 创建 blog 目录 ──
mkdir -p "$SCRIPT_DIR/blog"
info "blog 目录已就绪"

# ── 6. 完成 ──
echo ""
echo "============================================"
echo "  配置完成!"
echo "============================================"
echo ""
echo "  推荐: 使用 Cloudflare Tunnel（详见 docs/cloudflared-setup.md）"
echo "  备选: Cloudflare 控制台中配置 Origin Rules 端口回源:"
echo "    SSL/TLS → 完全 (Full)"
echo "    规则 → Origin Rules: https://$DOMAIN/* → 端口 $PORT"
echo ""
echo "  域名:       https://$DOMAIN"
echo "  端口:       $PORT"
echo "  wg-easy UI: https://$WG_SUBDOMAIN.$DOMAIN/"
echo "  wg-easy 密码: $WG_PASSWORD (请妥善保管)"
echo ""
echo "  接下来运行:"
echo ""
echo "     docker compose up -d"
echo ""
echo "============================================"
