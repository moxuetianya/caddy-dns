# Changelog

## 2026-06-14

### 新增
- Cloudflare Tunnel 方案，替代 Origin Rules 端口回源
- `docs/cloudflared-setup.md`：cloudflared 手动安装与 Tunnel 配置指南
- `docs/xcaddy-cloudflare.md`：使用 xcaddy 编译自定义 Caddy 模块指南
- systemd service 模板 `/tmp/cloudflared.service`

### 修复
- wg-easy v14+ 密码改用 `PASSWORD_HASH`（bcrypt），`install.sh` 自动生成哈希
- `.env` 增加 `WG_PASSWORD_HASH` 变量，适配 wg-easy 新版
- docker-compose Tunnel 模式下绑定 `127.0.0.1:2083`，不对外暴露端口

### 变更
- README 重写，按 Tunnel/回源两种方案组织
- 默认推荐 Cloudflare Tunnel 方案
- `env.example` 更新为 `PASSWORD_HASH` 格式

## 2026-03-17

### 初始版本
- Caddy + Cloudflare DNS-01 证书自动申请
- wg-easy WireGuard VPN Web UI 集成
- 静态 blog 文件服务
- `install.sh` 一键部署脚本
- 支持 Cloudflare Origin Rules 端口回源
