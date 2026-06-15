#!/bin/bash
set -euo pipefail

LOG_FILE="/var/log/caddy-blog-deploy.log"
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

# ============ 配置区（按需修改） ============
BLOG_SOURCE_DIR="${BLOG_SOURCE_DIR:-/home/peter/project/blog}"
BLOG_OUTPUT_DIR="${BLOG_OUTPUT_DIR:-/home/peter/project/caddy-dns/blog}"
# ===========================================

log "========== 开始部署 =========="

if [ ! -d "$BLOG_SOURCE_DIR" ]; then
    log "ERROR: 博客源码目录不存在: $BLOG_SOURCE_DIR"
    exit 1
fi

mkdir -p "$BLOG_OUTPUT_DIR"

cd "$BLOG_SOURCE_DIR"

# 拉取最新代码
log "拉取最新代码..."
git pull origin master 2>&1 | tee -a "$LOG_FILE"

# 构建静态文件（优先使用本地 zola，否则用 Docker）
if command -v zola &>/dev/null; then
    log "使用本地 Zola 构建..."
    zola build 2>&1 | tee -a "$LOG_FILE"
elif command -v docker &>/dev/null; then
    log "使用 Docker 运行 Zola 构建..."
    docker run --rm \
        -v "$BLOG_SOURCE_DIR:/app" \
        -w /app \
        ghcr.io/getzola/zola:v0.18.0 build 2>&1 | tee -a "$LOG_FILE"
else
    log "ERROR: 未找到 zola 或 docker"
    exit 1
fi

# 同步到 Caddy 的 blog 目录
log "同步文件到 $BLOG_OUTPUT_DIR ..."
rsync -av --delete "$BLOG_SOURCE_DIR/public/" "$BLOG_OUTPUT_DIR/" 2>&1 | tee -a "$LOG_FILE"

# 修正权限
chmod -R 755 "$BLOG_OUTPUT_DIR"

log "========== 部署完成 =========="
