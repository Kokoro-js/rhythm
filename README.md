# Rhythm 标准自部署

这个目录部署的是完整 Rhythm 机器人，不只是音乐后端：backend、同版本点歌页面、安全网关和私有
Workbench 会一起启动。管理员在 Workbench 配置自己的 Bot，用户直接向这个 Bot 发送命令。

## 推荐：Cloudflare DNS-01 + 非标 HTTPS 端口

这条路径不占用宿主机 80/443。Caddy 通过 Cloudflare DNS-01 取得和续期证书，默认把公网
`31083` 映射到容器内 443。

开始前准备好：

1. Linux x86-64 服务器、Docker Engine 与 Docker Compose plugin；
2. 托管在 Cloudflare 的域名，A/AAAA 记录指向服务器；不可达的 IPv6 地址不要保留 AAAA；
3. Cloudflare scoped API Token：仅授予目标 Zone 的 `Zone:Read` 与 `DNS:Edit`，不要使用 Global API Key；
4. 云安全组、防火墙和 NAT 放行/转发公网 TCP 31083；UDP 31083 仅用于可选 HTTP/3。

在 [Cloudflare API Tokens](https://dash.cloudflare.com/profile/api-tokens) 创建 Custom Token：Permissions 选择
`Zone / Zone / Read` 与 `Zone / DNS / Edit`，Zone Resources 只包含 Rhythm 域名所在 Zone。Token 必须保留给
Caddy 后续续期使用。

进入本目录：

```sh
cp .env.example .env
chmod 600 .env
mkdir -p data music
```

`.env` 顶部两个值必须填写；其余默认值和所有可选字段都已保留在文件中作为配置索引：

```dotenv
RHYTHM_DOMAIN=music.example.com
CF_API_TOKEN=replace-with-scoped-token

COMPOSE_FILE=compose.yaml:compose.https.yaml
RHYTHM_PUBLIC_PORT=31083
RHYTHM_VERSION=latest
```

`RHYTHM_DOMAIN` 只填 hostname，不要写协议、端口、路径或通配符。随后运行：

```sh
docker compose pull rhythm gateway
docker compose build --pull caddy
docker compose up -d --wait
docker compose ps
docker compose logs --tail=100 caddy
curl -fsS https://music.example.com:31083/_gateway/health
```

`Caddy.cloudflare.Dockerfile` 以官方 Caddy 2.11.4 builder 构建，并固定安装 `caddy-dns/cloudflare` v0.2.4；
标准 Caddy 镜像本身没有这个模块。可用下列命令确认实际镜像：

```sh
docker compose exec caddy caddy list-modules | grep '^dns.providers.cloudflare$'
```

### Cloudflare 橙云与端口选择

- 任意高端口（包括示例 31083）：DNS 记录必须使用 **DNS only / 灰云**，浏览器直接连接该端口；
- 使用 **Proxied / 橙云**：改用 Cloudflare 支持代理的 HTTPS 端口，例如 8443，并将 SSL/TLS mode 设为
  `Full (strict)`；Cloudflare 不能普通代理 31083；
- DNS-01 只负责域名所有权验证，不会替你开放防火墙、配置 NAT 或让错误的 A/AAAA 可达。

证书、ACME 账户和配置保存在命名 volume，容器升级不会删除。签发失败时先看 Caddy 日志；Cloudflare 返回
`Invalid request headers` 通常表示 Token 未传入或无效，TXT 传播超时则检查 `_acme-challenge` 记录和 Token 的
Zone 范围。

## 启动后配置 Bot

Workbench 不暴露到公网。先在自己的电脑建立 SSH 隧道：

```sh
ssh -N -L 3311:127.0.0.1:3311 user@server
```

打开 `http://127.0.0.1:3311/__pluxel/workbench/`，添加 KOOK Bot、保存 token、登录需要的音乐平台并启用插件。
新数据目录中的 `KookPlugin` 指令前缀初始为 `/`，因此使用 `/here`；修改过前缀时以当前 Bot 的帮助信息为准。

## 标准部署包含什么

```text
公网 https://music.example.com:31083
  └─ 宿主机 31083 → Caddy:443：Cloudflare DNS-01 与 HTTPS
       └─ gateway:8080：SPA、/streamer/*、Workbench 隔离
            └─ rhythm:3311：业务 API、插件与私有 Workbench

宿主机 127.0.0.1:3310：gateway 调试入口
宿主机 127.0.0.1:3311：仅 SSH 隧道访问的 Workbench
```

内置页面与 API 同源，不需要设置 CORS，也不需要在页面里“添加服务器”。不要把 3310 或 3311 直接开放到公网。

## 直接 ACME 80/443（备选）

只有服务器能直接占用公网 80/443 时才使用这条更简单的路径。它使用标准 Caddy 镜像和 HTTP-01/TLS-ALPN，
不需要 Cloudflare Token：

```dotenv
COMPOSE_FILE=compose.yaml:compose.https-direct.yaml
RHYTHM_DOMAIN=music.example.com
RHYTHM_PUBLIC_PORT=443
```

域名必须直接到达服务器，云安全组、防火墙和 NAT 必须允许公网 TCP 80/443；UDP 443 仍仅供 HTTP/3。运行：

```sh
docker compose pull
docker compose up -d --wait
docker compose logs --tail=100 caddy
```

## 已有 Caddy、Nginx 或负载均衡（高级）

已有可信 HTTPS 入口时不启动本包的 Caddy：

```dotenv
COMPOSE_FILE=compose.yaml
RHYTHM_DOMAIN=music.example.com
RHYTHM_PUBLIC_PORT=443
```

照常运行 `docker compose up -d --wait`，并把整个站点转发到 `http://127.0.0.1:3310`。不要拆分 Rhythm 路径，
也不要代理 3311。Nginx 最小配置：

```nginx
location / {
    proxy_pass http://127.0.0.1:3310;
    proxy_http_version 1.1;
    proxy_buffering off;
    proxy_read_timeout 3600s;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
}
```

外部入口使用非标端口时，把 `RHYTHM_PUBLIC_PORT` 改成相同端口，Bot 才会生成正确链接。

## 其他高级场景

### 本机演示，不提供远程房间功能

```dotenv
COMPOSE_FILE=compose.yaml
RHYTHM_PUBLIC_SCHEME=http
RHYTHM_DOMAIN=127.0.0.1
RHYTHM_PUBLIC_PORT=3310
```

远程 HTTP 页面不会兑换房间入口，生产必须回到可信 HTTPS。数据库仍使用同一套本地 SQLite 架构。

### 离线内网 HTTPS

内网 CA 使用不含 Cloudflare 模块的 direct overlay：

```dotenv
COMPOSE_FILE=compose.yaml:compose.https-direct.yaml
RHYTHM_DOMAIN=rhythm.home.arpa
RHYTHM_PUBLIC_PORT=443
RHYTHM_CADDY_TLS_DIRECTIVE=tls internal
```

启动后导出 Caddy 根证书，并安装到每台客户端设备的系统信任库：

```sh
docker compose cp caddy:/data/caddy/pki/authorities/local/root.crt ./rhythm-local-ca.crt
```

### 使用独立前端

标准 Compose 自带页面，无需操作。只有在其他站点打开 Rhythm 前端时，才在“添加自己的服务器”中填写并选中
`https://RHYTHM_DOMAIN:RHYTHM_PUBLIC_PORT`，不要追加 `/streamer`。同时在 Workbench 的
`RhythmApiPlugin.allowedOrigins` 中逐项加入外部前端的精确 HTTPS origin；不要填写 `*`、路径或 API URL。

首次启动新数据目录时也可在 `.env` 预置：

```dotenv
RHYTHM_ALLOWED_ORIGINS=["https://player.example.net"]
```

## 环境变量索引

`.env.example` 由 Rhythm host build 的 Pluxel 环境 contract 与这三个 Compose YAML 合成，按“必填 → 标准默认 →
可选高级 → 直接 ACME/内网 CA”排列。发布门禁会检查 Compose 的全部变量都已进入模板，也会检查每个 Plugin bootstrap
变量已经被透传、派生或固定在 backend image 中；不要另行维护一份变量清单。普通部署只修改顶部必填项；需要覆盖
端口、路径、镜像、Workbench 或恢复策略时，取消对应注释即可。

## 备份与升级

备份权限为 600 的 `.env` 和完整 `data/`；`music/` 是只读本地曲库。统一数据库位于
`data/rhythm.sqlite`，应停止 backend 后备份，或使用 SQLite 在线备份工具取得一致快照。不要让两个
backend 同时写同一份数据。升级时只改 `RHYTHM_VERSION`，然后：

```sh
docker compose pull rhythm gateway
docker compose build --pull caddy
docker compose up -d --wait
docker compose ps
```

直接 ACME 或外部反代没有本地 build 的 Caddy，可直接使用 `docker compose pull`。回滚前恢复对应备份，再把版本改回。

从旧版部署包升级时：

- 把 `RHYTHM_PUBLIC_URL=https://host:port` 拆为 `RHYTHM_DOMAIN=host` 与 `RHYTHM_PUBLIC_PORT=port`；
- 删除 `RHYTHM_IMAGE` / `RHYTHM_GATEWAY_IMAGE`，把共同 tag 写入 `RHYTHM_VERSION`；
- 使用镜像代理或私有 registry 时设置 `RHYTHM_IMAGE_REGISTRY`。
