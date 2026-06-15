# Caddy + Cloudflare DNS — 未备案域名 HTTPS 解决方案

通过 Cloudflare Tunnel 或 Origin Rules + Caddy 非标端口实现未备案域名 HTTPS 访问。

## 方案对比

| 方案 | 原理 | 优点 | 缺点 |
|------|------|------|------|
| **Cloudflare Tunnel**（推荐） | cloudflared 创建加密隧道直连 | 不需要开放端口、不依赖 VPS 网络环境 | 需要额外安装 cloudflared |
| **Origin Rules 回源** | CF 代理 → VPS 非标端口 | 无需额外进程 | 阿里云经典网络可能 RST，需要弹性公网 IP |

## 推荐方案：Cloudflare Tunnel

### 架构

```
用户 --HTTPS--> Cloudflare 边缘 --Tunnel--> VPS localhost:2083 --HTTP--> Caddy
```

### 前置条件

| 条件 | 说明 |
|------|------|
| 域名 | 已托管到 Cloudflare DNS |
| VPS | 任意云服务商 |
| Cloudflare API Token | Zone:DNS:Edit 权限（仅初次配置需要） |

### 快速部署

```bash
git clone https://github.com/your-repo/caddy-dns.git
cd caddy-dns
chmod +x install.sh
./install.sh
```

### 手动部署

#### 1. 安装 cloudflared

```bash
curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o cloudflared
sudo install -m 755 cloudflared /usr/local/bin/cloudflared
```

#### 2. 创建 Tunnel

```bash
cloudflared tunnel login          # 浏览器授权
cloudflared tunnel create caddy-tunnel
```

#### 3. 配置 Tunnel

创建 `~/.cloudflared/config.yml`:

```yaml
tunnel: <tunnel-id>
credentials-file: /home/peter/.cloudflared/<tunnel-id>.json

ingress:
  - hostname: your-domain.com
    service: http://localhost:2083
  - hostname: wg.your-domain.com
    service: http://localhost:2083
  - service: http_status:404
```

#### 4. 路由 DNS

```bash
cloudflared tunnel route dns <tunnel-id> your-domain.com
```

#### 5. 安装系统服务

```bash
sudo cp /tmp/cloudflared.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable cloudflared
sudo systemctl start cloudflared
```

systemd service 文件内容：

```ini
[Unit]
Description=Cloudflare Tunnel
After=network.target docker.service

[Service]
Type=simple
User=peter
ExecStart=/usr/local/bin/cloudflared tunnel --config /home/peter/.cloudflared/config.yml run caddy-tunnel
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

#### 6. 启动 Docker 服务

```bash
cp env.example .env   # 编辑 .env 填入配置
docker compose up -d
```

#### 7. Cloudflare 设置

- SSL/TLS → **完全（严格）**（Tunnel 提供端到端加密）
- **不需要** Origin Rules，**不需要** 开放安全组端口

---

## 备选方案：Origin Rules 回源

如果 Cloudflare Tunnel 不可用，可使用 Origin Rules 直接端口回源。

### 架构

```
用户 --HTTPS--> Cloudflare CDN --[2083]--> VPS (Caddy + TLS)
```

### 额外要求

| 条件 | 说明 |
|------|------|
| VPS 安全组 | 开放回源端口（TCP） |
| Cloudflare SSL 模式 | 完全（Full），源站需要有效 TLS 证书 |
| 阿里云 ECS | 需使用**弹性公网 IP**（经典网络公网 IP 可能 RST 非标端口 TLS） |

### Cloudflare 配置

1. SSL/TLS → 加密模式 → **完全**
2. 规则 → Origin Rules → 创建规则：
   - 字段：`URI 完整`，运算符：`通配符`
   - 值：`https://your-domain.com/*`
   - 动作：重写端口 → `2083`
3. DNS → 添加 A 记录指向 VPS IP，**已代理**（橙色云朵）

### Caddyfile（回源模式）

```caddyfile
your-domain.com:2083 {
    tls {
        dns cloudflare {env.CLOUDFLARE_API_TOKEN}
    }
    # ... 其余配置同 Tunnel 模式
}
```

### 支持的非标准端口

Cloudflare 支持的 HTTPS 回源端口：`443` `2053` `2083` `2087` `2096` `8443`

---

## wg-easy 说明

wg-easy 是集成 Web UI 的 WireGuard VPN 管理工具。

| 项目 | 值 |
|------|-----|
| Web UI | `https://wg.your-domain.com/` |
| WireGuard 端口 | `51820/udp` |
| 配置文件 | `wg-easy/` 目录下的客户端 `.conf` 文件 |

> **注意**：wg-easy v14+ 使用 `PASSWORD_HASH`（bcrypt）替代明文 `PASSWORD`。`install.sh` 会自动生成。

使用一级子域名（如 `wg.juzhong.xyz`）而非多级子域名，确保被 Cloudflare Free 套餐的 `*.juzhong.xyz` 通配符证书覆盖。

---

## Caddyfile 参考

### Tunnel 模式（当前默认）

```caddyfile
http://your-domain.com:2083 {
    root * /var/www/blog
    file_server
    encode gzip
}

http://wg.your-domain.com:2083 {
    reverse_proxy wg-easy:51821 {
        header_up Host {http.reverse_proxy.upstream.host}
        header_up X-Forwarded-For {remote_host}
    }
}
```

### 回源模式（需要 TLS 证书）

```caddyfile
your-domain.com:2083 {
    tls {
        dns cloudflare {env.CLOUDFLARE_API_TOKEN}
    }

    handle_path /wg* {
        reverse_proxy wg-easy:51821 {
            header_up Host {http.reverse_proxy.upstream.host}
            header_up X-Forwarded-For {remote_host}
        }
    }

    handle {
        root * /var/www/blog
        file_server
        encode gzip
    }
}
```

---

## docker-compose.yaml 参考

```yaml
services:
  caddy:
    image: slothcroissant/caddy-cloudflaredns:2.11.4
    restart: unless-stopped
    ports:
      - "127.0.0.1:2083:2083"   # Tunnel 模式，仅本地
      # - "2083:2083"             # 回源模式，对外暴露
    environment:
      - CLOUDFLARE_API_TOKEN=${CLOUDFLARE_API_TOKEN}
      - ACME_AGREE=true
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - ./blog:/var/www/blog:ro
    networks:
      - caddy-net

  wg-easy:
    image: ghcr.io/wg-easy/wg-easy
    container_name: wg-easy
    restart: unless-stopped
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    sysctls:
      - net.ipv4.conf.all.src_valid_mark=1
      - net.ipv4.ip_forward=1
    environment:
      - WG_HOST=${WG_HOST}
      - PASSWORD_HASH=${WG_PASSWORD_HASH}
      - PORT=51821
      - WG_DEFAULT_DNS=1.1.1.1
    ports:
      - "51820:51820/udp"
    volumes:
      - ./wg-easy:/etc/wireguard
    networks:
      - caddy-net

networks:
  caddy-net:
    driver: bridge
```

---

## 常用命令

```bash
# Docker
docker compose up -d
docker compose logs -f caddy
docker compose restart
docker compose down

# Tunnel
sudo systemctl status cloudflared
sudo systemctl restart cloudflared
cloudflared tunnel list

# 更新镜像
docker compose pull && docker compose up -d
```

---

## 故障排查

| 现象 | 可能原因 | 解决 |
|------|----------|------|
| 525 SSL Handshake Failed | 阿里云经典网络 RST 非标端口 TLS | 改用 Cloudflare Tunnel |
| 证书申请失败 | API Token 权限不足 | 确认 Token 有 Zone:DNS:Edit 权限 |
| `connection refused` | 端口未开放 | 安全组/防火墙，或改用 Tunnel |
| 502 Bad Gateway | Caddy 反向代理目标不可达 | 检查后端服务是否启动 |
| `ERR_CONNECTION_RESET` | 网络监管拦截 | 换端口或使用 Tunnel |

---

## 项目结构

```
caddy-dns/
├── Caddyfile           # Caddy 配置
├── docker-compose.yaml # Docker Compose 编排
├── env.example         # 环境变量模板
├── install.sh          # 一键安装脚本
├── blog/               # 静态文件目录
├── wg-easy/            # wg-easy 数据目录（自动创建）
├── docs/
│   ├── cloudflared-setup.md  # cloudflared 安装指南
│   └── xcaddy-cloudflare.md  # xcaddy 自定义编译指南
├── .env                # 实际环境变量（不提交）
└── .gitignore
```
