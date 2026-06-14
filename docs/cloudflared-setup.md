# Cloudflared 手动安装与配置

## 安装 cloudflared

### 方法一：下载二进制（推荐）

```bash
# 下载最新版本
curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /tmp/cloudflared

# 安装到系统路径
sudo install -m 755 /tmp/cloudflared /usr/local/bin/cloudflared

# 验证
cloudflared --version
```

### 方法二：通过包管理器（Ubuntu/Debian）

```bash
curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | sudo gpg --yes --dearmor -o /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/cloudflare-client.list
sudo apt update
sudo apt install cloudflared
```

---

## 创建 Tunnel

### 1. 登录 Cloudflare

```bash
cloudflared tunnel login
```

浏览器会自动打开，选择你的域名（juzhong.xyz），授权即可。证书会保存到 `~/.cloudflared/cert.pem`。

### 2. 创建 Tunnel

```bash
cloudflared tunnel create caddy-tunnel
```

这会生成一个 Tunnel ID 和对应的凭证文件 `~/.cloudflared/<tunnel-id>.json`。

### 3. 配置 Tunnel

创建配置文件 `~/.cloudflared/config.yml`：

```yaml
tunnel: <tunnel-id>            # 替换为上一步生成的 ID
credentials-file: /home/peter/.cloudflared/<tunnel-id>.json

ingress:
  - hostname: ali.juzhong.xyz
    service: http://localhost:2083
  - service: http_status:404
```

### 4. 添加 DNS 记录

```bash
cloudflared tunnel route dns <tunnel-id> ali.juzhong.xyz
```

这会在 Cloudflare DNS 中自动添加一条 `ali.juzhong.xyz` 的 CNAME 记录，指向 Tunnel。

### 5. 启动 Tunnel

```bash
# 前台运行（测试用）
cloudflared tunnel run caddy-tunnel

# 后台运行（安装为系统服务）
cloudflared tunnel --config ~/.cloudflared/config.yml run caddy-tunnel
```

### 6. 安装为系统服务（开机自启）

```bash
sudo cloudflared service install
sudo systemctl enable cloudflared
sudo systemctl start cloudflared
```

---

## Docker Compose 方式

如果不装系统服务，也可以加到现有 docker-compose：

```yaml
services:
  cloudflared:
    image: cloudflare/cloudflared:latest
    restart: unless-stopped
    command: tunnel --no-autoupdate run caddy-tunnel
    environment:
      - TUNNEL_TOKEN=${TUNNEL_TOKEN}
    networks:
      - caddy-net
```

需要先在 Cloudflare Zero Trust 中创建 Tunnel 获取 `TUNNEL_TOKEN`。

---

## 关键点

- Tunnel 建立后，**不再需要 Origin Rule 和端口转发**
- SSL/TLS 模式可设为 **完全 (Full) 或 完全(严格)**，不需要源站证书
- 安全组中也不需要开放 2083 端口（全部走 Tunnel 内网）
