# 使用 xcaddy 编译支持 Cloudflare DNS 的 Caddy

使用 `xcaddy` 编译支持 Cloudflare DNS 模块的 Caddy 非常简单，以下是完整步骤。

## 安装 xcaddy

**方法一：通过 go install 安装（推荐，需先安装 Go 环境）**

```bash
go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest
```

**方法二：下载预编译二进制**

```bash
wget https://github.com/caddyserver/xcaddy/releases/latest/download/xcaddy_$(uname -s)_$(uname -m).tar.gz
tar -zxvf xcaddy_*.tar.gz
```

## 编译带 Cloudflare 模块的 Caddy

```bash
xcaddy build --with github.com/caddy-dns/cloudflare
```

编译完成后，当前目录会生成一个 `caddy` 可执行文件。

## 验证模块是否编译成功

```bash
./caddy list-modules | grep cloudflare
```

如果看到输出 `dns.providers.cloudflare`，说明 Cloudflare 模块已成功集成。

## 替换系统原有的 Caddy（可选）

```bash
# 备份原有 caddy
sudo mv $(which caddy) /usr/bin/caddy.bak

# 将新编译的 caddy 放到 PATH 中
sudo cp caddy /usr/bin/
```

## 配置使用 Cloudflare DNS

在 `Caddyfile` 中配置 DNS 验证：

```caddyfile
example.com {
    reverse_proxy localhost:8080
    tls {
        dns cloudflare YOUR_CLOUDFLARE_API_TOKEN
    }
}
```

或者通过环境变量方式（更安全）：

```bash
export CLOUDFLARE_API_TOKEN=your_token_here
```

```caddyfile
example.com {
    reverse_proxy localhost:8080
    tls {
        dns cloudflare
    }
}
```

> ⚠️ **注意**：需要使用 Cloudflare 的 **API Token**，而不是 Global API Key。可以在 Cloudflare 后台的 **User Profile → API Tokens** 中创建。

## 同时添加多个模块

```bash
xcaddy build \
    --with github.com/caddy-dns/cloudflare \
    --with github.com/caddyserver/forwardproxy@caddy2=github.com/klzgrad/forwardproxy@naive
```

这样就可以同时集成 Cloudflare DNS 和其他插件。
