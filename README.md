# Caddy + Cloudflare DNS — 未备案域名 HTTPS 解决方案

通过 Cloudflare CDN 代理 + Caddy 非标端口监听 + DNS-01 证书挑战，实现未备案域名在国内 VPS 上的 HTTPS 访问。

## 核心原理

```
用户浏览器 --[443]--> Cloudflare CDN --[8443]--> VPS (Caddy)
```

1. 用户请求指向 Cloudflare（DNS 已开启代理，小云朵橙色）
2. Cloudflare 通过 **Origin Rules** 将请求转发到 VPS 的非标准端口（如 8443 / 2083）
3. Caddy 监听该端口，通过 DNS-01 挑战自动申请并续签 Let's Encrypt 证书
4. 整个链路 TLS 加密，规避备案检测

## 前置条件

| 条件 | 说明 |
|------|------|
| 域名 | 已托管到 Cloudflare DNS |
| VPS | 任意云服务商，已开放非标端口（安全组入站规则） |
| 端口 | Caddy 监听端口（TCP） + WireGuard 51820/udp |
| Cloudflare API Token | 拥有 Zone:DNS:Edit 权限 |

## 支持的非标准 HTTPS 端口

Cloudflare 支持的 HTTPS 回源端口：

`443` `2053` `2083` `2087` `2096` `8443`

本模板默认使用 `2083`，可在 `Caddyfile` 和 `docker-compose.yaml` 中统一修改。

## 快速部署

### 一键安装

```bash
git clone https://github.com/your-repo/caddy-dns.git
cd caddy-dns
chmod +x install.sh
sudo ./install.sh
```

脚本会自动完成：
- 安装 Docker 和 Docker Compose（如未安装）
- 引导配置域名、端口、Cloudflare API Token
- 可选安装 wg-easy（WireGuard VPN + Web UI）
- 配置静态 blog 文件目录
- 生成 `.env`、`Caddyfile` 和 `docker-compose.yaml`
- 启动全部服务

### 手动部署

#### 1. 准备环境变量

```bash
cp env.example .env
```

编辑 `.env`，填入你的 Cloudflare API Token：

```env
# Cloudflare API Token (Zone:DNS:Edit 权限)
CLOUDFLARE_API_TOKEN=your-api-token-here

# wg-easy 配置 (可选)
WG_HOST=your-domain.com
WG_PASSWORD=your-wg-easy-password
```

#### 2. 修改 Caddyfile

将 `your-domain.com` 替换为你的域名，端口与下方 docker-compose 暴露端口保持一致：

```caddy
your-domain.com:2083 {
    tls {
        dns cloudflare {env.CLOUDFLARE_API_TOKEN}
    }

    # wg-easy Web UI (可选，子路径反向代理)
    handle_path /wg* {
        reverse_proxy wg-easy:51821 {
            header_up X-Forwarded-For {remote_host}
        }
    }

    # 静态 blog
    handle {
        root * /var/www/blog
        file_server
        encode gzip
    }
}
```

> **关于 wg-easy 子路径**：wg-easy 不原生支持自定义 base path，若页面资源加载异常，建议改用子域名（配置见 Caddyfile 底部注释）。

#### 3. 修改 docker-compose.yaml

根据需求调整端口映射：

```yaml
services:
  caddy:
    image: slothcroissant/caddy-cloudflaredns:2.11.4
    restart: unless-stopped
    environment:
      - CLOUDFLARE_API_TOKEN=${CLOUDFLARE_API_TOKEN}
      - ACME_AGREE=true
    ports:
      - "2083:2083"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - ./blog:/var/www/blog:ro
      - caddy_data:/data
      - caddy_config:/config
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
      - PASSWORD=${WG_PASSWORD}
      - PORT=51821
      - WG_DEFAULT_DNS=1.1.1.1
    ports:
      - "51820:51820/udp"
    volumes:
      - ./wg-easy:/etc/wireguard
    networks:
      - caddy-net

volumes:
  caddy_data:
  caddy_config:

networks:
  caddy-net:
    driver: bridge
```

#### 4. 启动服务

```bash
docker compose up -d
```

#### 5. 验证

```bash
# 查看日志确认证书申请成功
docker compose logs -f

# 测试端口可达
curl -k https://你的VPS_IP:2083
```

## Cloudflare 配置

### 1. 创建 API Token

1. 登录 [Cloudflare 控制台](https://dash.cloudflare.com/)
2. 右上角头像 → "我的个人资料" → "API 令牌" → "创建令牌"
3. 选择 "编辑区域 DNS" 模板
4. **区域资源**限制为你的域名
5. 创建后保存 Token（只显示一次）

### 2. 配置 DNS 记录

| 类型 | 名称 | 内容 | 代理状态 |
|------|------|------|----------|
| A | your-domain.com | VPS 公网 IP | **已代理**（橙色云朵） |

### 3. 配置 Origin Rules

1. 左侧菜单 → "规则" → "源站规则" → "创建规则"
2. 规则名称：`Caddy Backend Port`
3. 字段：`主机名`，值：`your-domain.com`
4. 操作：`重写端口`，目标端口：`2083`（与 Caddy 监听端口一致）

## 更换端口

如需使用其他端口，需要同时修改三处：

| 位置 | 说明 |
|------|------|
| `docker-compose.yaml` → `ports` | 将 `"2083:2083"` 改为 `"8443:8443"` |
| `Caddyfile` → 站点地址 | 将 `:2083` 改为 `:8443` |
| Cloudflare Origin Rules | 目标端口改为 `8443` |

## wg-easy 说明

wg-easy 是一个集成 Web UI 的 WireGuard VPN 管理工具。

| 项目 | 值 |
|------|-----|
| Web UI | `https://your-domain.com/wg/` |
| WireGuard 端口 | `51820/udp` |
| 配置文件 | `wg-easy/` 目录下的客户端 `.conf` 文件 |

> **注意**：WireGuard 使用 UDP 协议，Cloudflare CDN 不代理 UDP 流量。客户端将通过域名直接连接到 VPS 的 51820/udp 端口。若域名 DNS 开启了 Cloudflare 代理（橙色云朵），需要确保 `WG_HOST` 对应的记录可以直连 VPS IP（可使用灰色云朵或指向公网 IP）。
>
> 如果子路径 `/wg/` 出现资源加载问题，请改用子域名方案（见 Caddyfile 底部注释示例）。

## 常用命令

```bash
# 启动
docker compose up -d

# 查看日志
docker compose logs -f caddy

# 重启
docker compose restart

# 停止
docker compose down

# 更新镜像
docker compose pull && docker compose up -d
```

## 故障排查

| 现象 | 可能原因 | 解决 |
|------|----------|------|
| `ERR_CONNECTION_RESET` | 网络监管拦截 | 更换端口重试，或考虑 Cloudflare Tunnel |
| 证书申请失败 | API Token 权限不足 | 确认 Token 有 Zone:DNS:Edit 权限 |
| `connection refused` | 端口未开放 | 检查安全组/防火墙规则 |
| 502 Bad Gateway | Caddy 反向代理目标不可达 | 检查后端服务是否启动 |
| opencode ssh-mcp 启动失败 | 配置参数不完整 | 见下方 [SSH MCP 排查](#ssh-mcp-排查) |

### SSH MCP 排查

**时间**: 2026-06-14

**现象**: opencode 中配置的 ssh-mcp 服务无法启动。

**配置文件**: `~/.config/opencode/opencode.jsonc` → `mcp.ssh-mcp`

**排查过程**:

1. 阅读 `~/.config/opencode/opencode.jsonc`，找到 ssh-mcp 的 command：
   ```
   npx -y ssh-mcp -- --host=alivps --key=~/.ssh/id_ed25519 --timeout=30000
   ```

2. 直接运行该命令测试，报错：
   ```
   Error: Configuration error:
   Missing required --host
   Missing required --user
   ```
   但 `--host=alivps` 已传入，说明 `--` 分隔符导致参数解析异常。实际 ssh-mcp v1.5.0 使用 `--host=` 格式（而非 argparse 风格），`--` 被忽略。

3. 查看 ssh-mcp 源码 (`~/.npm/_npx/.../ssh-mcp/build/index.js`)，确认：
   - 必需参数：`--host`、`--user`
   - 可选参数：`--port`(默认22)、`--key`、`--password`、`--timeout`(默认60000)、`--disableSudo` 等

4. 检查 SSH 环境：
   - `~/.ssh/config` 中 `alivps` Host 定义：`HostName 8.152.200.33`、`User peter`、`Port 22`
   - 全局 `ProxyCommand` 通过 SOCKS5 代理 `192.168.2.100:10808`
   - 本地密钥文件：`~/.ssh/id_ed25519` **不存在**，实际密钥为 `~/.ssh/id_ed25519.hu`

5. 测试 SSH 直连：
   - `ssh -i ~/.ssh/id_ed25519.hu alivps` → 成功
   - `ssh -i ~/.ssh/id_rsa alivps` → Permission denied（密钥未授权）
   - 说明远程服务器只信任 `id_ed25519.hu` 对应的公钥

6. **修复以下 3 个问题**：

   | 问题 | 原因 | 修复 |
   |------|------|------|
   | 缺少 `--user` | ssh-mcp 要求 `--user` 参数 | 添加 `--user=peter` |
   | SSH 密钥路径错误 | `~/.ssh/id_ed25519` 不存在，且 Node.js `fs.readFile` 不展开 `~` | 改为绝对路径 `--key=/home/peter/.ssh/id_ed25519.hu` |
   | 主机名不可解析 | `alivps` 是 SSH config 别名，`ssh2` 库不解析 `~/.ssh/config` | 改为实际 IP `--host=8.152.200.33` |

**修复后 command**:
```
npx -y ssh-mcp -- --host=8.152.200.33 --user=peter --key=/home/peter/.ssh/id_ed25519.hu --timeout=30000
```

**验证**: 直接运行命令输出 `SSH MCP Server running on stdio`，启动成功。

### 测试端口可达性

```bash
# 在 VPS 上
curl -k https://localhost:2083

# 从外部
telnet <VPS_IP> 2083
```

如端口可达但仍无法访问，大概率是国内网络监管导致，可尝试：
- 换用其他非标端口（如 `2096`）
- 使用 Cloudflare Tunnel 方案
- 迁移到海外 VPS

## 项目结构

```
caddy-dns/
├── Caddyfile           # Caddy 配置（blog 静态文件 + wg-easy 反向代理）
├── docker-compose.yaml # Docker Compose 编排（caddy + wg-easy）
├── env.example         # 环境变量模板
├── install.sh          # 一键安装脚本
├── blog/               # 静态 blog 文件目录（挂载到 /var/www/blog）
├── wg-easy/            # wg-easy 数据目录（自动创建）
├── .env                # 实际环境变量（不提交）
└── .gitignore
```
