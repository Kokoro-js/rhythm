# Rhythm 标准自部署

这个目录一次启动 Rhythm backend、同版本点歌页面、安全 gateway 和私有 Workbench。标准内置前端只有一个公开
origin：

```dotenv
RHYTHM_PUBLIC_URL=https://music.example.com:31083
```

`RHYTHM_PUBLIC_URL` 是 Bot 控制链接、Caddy 站点和 API 同源策略共用的 canonical origin。只有独立前端与 API
gateway 分域时才设置 `RHYTHM_GATEWAY_URL`。公开 origin 必须包含 scheme 和非默认端口，且不包含 credentials、
非根路径、query 或 fragment。

内部拓扑不是用户配置：

```text
gateway container + host loopback  127.0.0.1:3310
backend container + host loopback  127.0.0.1:3311
default DNS-01 public listener      0.0.0.0:31083
direct ACME public listeners        0.0.0.0:80 and 0.0.0.0:443
```

## 推荐：Cloudflare DNS-01 + 31083

这条路径不占用宿主机 80/443。Caddy 通过 Cloudflare DNS-01 取得和续期证书，并在容器和宿主机上都固定监听
31083，不再做 31083 → 443 的端口翻译。

开始前准备好：

1. Linux x86-64 服务器、Docker Engine 与 Docker Compose plugin；
2. 托管在 Cloudflare 的域名，A/AAAA 记录指向服务器；不可达的 IPv6 地址不要保留 AAAA；
3. 仅有目标 Zone `Zone:Read` 与 `DNS:Edit` 的 Cloudflare API Token；
4. 云安全组、防火墙和 NAT 放行/转发公网 TCP 31083；UDP 31083 只用于可选 HTTP/3。

初始化：

```sh
cp .env.example .env
chmod 600 .env
mkdir -p data music
```

填写顶部两个空值；镜像版本默认使用 `latest`：

```dotenv
RHYTHM_PUBLIC_URL=https://music.example.com:31083
CF_API_TOKEN=replace-with-scoped-token
RHYTHM_VERSION=latest

COMPOSE_FILE=compose.yaml:compose.https.yaml
```

`RHYTHM_VERSION` 会同时应用到 backend 和 gateway。保留 `latest` 即可在拉取镜像时跟随最新发布；需要可复现或
受控升级时，可改为两边都已发布的同一个 release 或 `sha-*` tag。

然后启动：

```sh
docker compose pull rhythm gateway
docker compose up -d --wait
docker compose ps
docker compose logs --tail=100 gateway
curl -fsS https://music.example.com:31083/_gateway/health
```

发布的 gateway 镜像以官方 Caddy builder 固定安装 `caddy-dns/cloudflare`。可确认实际模块：

```sh
docker compose exec gateway caddy list-modules | grep '^dns.providers.cloudflare$'
```

任意高端口（包括 31083）的 Cloudflare 记录必须使用 **DNS only / 灰云**，浏览器直接连接服务器。若必须使用
Cloudflare 橙云或 8443 等其他公开端口，使用已有反代模式：只启动 `compose.yaml`，让外部入口监听所需端口并
整站代理到 `http://127.0.0.1:3310`。不要在 bundled overlay 中重新引入一组端口变量。

## 直接 ACME 80/443

服务器可以直接占用公网 80/443 时，使用标准 Caddy 镜像和 HTTP-01/TLS-ALPN，不需要 Cloudflare Token：

```dotenv
RHYTHM_PUBLIC_URL=https://music.example.com
COMPOSE_FILE=compose.yaml:compose.https-direct.yaml
RHYTHM_VERSION=latest
```

```sh
docker compose pull
docker compose up -d --wait
docker compose logs --tail=100 gateway
```

这里 443 是 HTTPS 默认端口，所以公开 URL 不写 `:443`。公网 TCP 80/443 必须能直接到达服务器；UDP 443
仍只用于可选 HTTP/3。

## 已有 Caddy、Nginx 或负载均衡

已有可信 HTTPS 入口时不启动本包的 Caddy：

```dotenv
RHYTHM_PUBLIC_URL=https://music.example.com
COMPOSE_FILE=compose.yaml
RHYTHM_VERSION=latest
```

运行 `docker compose up -d --wait`，把整个公开站点转发到固定的
`http://127.0.0.1:3310`。公开入口可以是 443、8443 或其他端口，只要 `RHYTHM_PUBLIC_URL` 与该入口的浏览器可见
origin 完全一致；不要拆分 Rhythm path，也不要代理 3311。

Nginx 最小配置：

```nginx
location / {
    proxy_pass http://127.0.0.1:3310;
    proxy_http_version 1.1;
    proxy_buffering off;
    proxy_read_timeout 3600s;
    proxy_set_header Host $http_host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
}
```

## 启动后配置 Bot

Workbench 固定只发布到服务器 loopback。先在自己的电脑建立 SSH 隧道：

```sh
ssh -N -L 3311:127.0.0.1:3311 user@server
```

打开 `http://127.0.0.1:3311/__pluxel/workbench/`，保存 Bot token、登录音乐平台并启用所需插件。新数据目录的
`RHYTHM_PUBLIC_URL` 在每次启动时覆盖 `RhythmWebPolicyPlugin.publicOrigin` fallback，供 KOOK、Discord、TeamSpeak
生成前端控制链接；未设置 `RHYTHM_GATEWAY_URL` 时，API 与 Caddy 自动使用同一 origin。独立前端部署设置 gateway
变量后，后端会自动把 canonical frontend 加入 CORS。两个 origin 环境值都不存在时才使用 Workbench policy
fallback；backend 不从转发头重建 origin。

## 网络边界

```text
公网 https://music.example.com:31083
  └─ gateway/Caddy：DNS-01、HTTPS、SPA、/streamer/*、Workbench 隔离
       └─ rhythm:3311：业务 API、Plugin 与私有 Workbench

宿主机 127.0.0.1:3310：已有反代或本机诊断入口
宿主机 127.0.0.1:3311：SSH 隧道 Workbench 入口
```

内置页面与 API 同源，不需要设置 CORS，也不需要在页面中“添加服务器”。不要把 3310 或 3311 直接开放到公网。

## 其他场景

本机演示不提供远程房间的可信 HTTPS：

```dotenv
RHYTHM_PUBLIC_URL=http://127.0.0.1:3310
COMPOSE_FILE=compose.yaml
```

离线内网可以使用 Caddy 内部 CA：

```dotenv
RHYTHM_PUBLIC_URL=https://rhythm.home.arpa
COMPOSE_FILE=compose.yaml:compose.https-direct.yaml
RHYTHM_CADDY_TLS_DIRECTIVE=tls internal
```

启动后导出根证书并安装到每台客户端设备：

```sh
docker compose cp gateway:/data/caddy/pki/authorities/local/root.crt ./rhythm-local-ca.crt
```

只有独立前端需要拆分 origin。`RHYTHM_PUBLIC_URL` 填独立前端自身的 origin，`RHYTHM_GATEWAY_URL` 填 Caddy/API
origin；前端的服务器地址使用后者且不追加 `/streamer`。canonical frontend 会自动获得 CORS 授权，
`RhythmApiPlugin.allowedOrigins` / `RHYTHM_ALLOWED_ORIGINS` 只用于额外站点：

```dotenv
RHYTHM_PUBLIC_URL=https://player.example.net
RHYTHM_GATEWAY_URL=https://music-api.example.com:31083
# 可选的第三方管理页等额外来源
RHYTHM_ALLOWED_ORIGINS=["https://another-player.example.org"]
```

## 环境、备份与升级

`.env.example` 由 Rhythm host build 的 Pluxel 环境 contract 与三个 Compose YAML 合成。生成门禁保证每个应用
bootstrap 变量已被透传、派生或固定，并保证旧的 split domain/port 变量不会重新出现。

备份权限为 600 的 `.env` 和完整 `data/`；`music/` 是只读本地曲库。统一数据库位于
`data/database/rhythm.sqlite`，不要让两个 backend 同时写同一目录。容器启动时会自动对齐 `data/` 内来自宿主机或
恢复备份的 UID/GID，无需额外的权限修复变量。

使用默认 `latest` 时，升级不需要修改 `.env`；直接拉取并重建即可。若已锁定版本，则先把
`RHYTHM_VERSION` 改为 backend 和 gateway 都已发布的同一个新 tag：

```sh
docker compose pull rhythm gateway
docker compose up -d --wait
docker compose ps
```

从拆分地址变量的版本升级时，删除
`RHYTHM_DOMAIN`、`RHYTHM_PUBLIC_PORT`、`RHYTHM_PUBLIC_SCHEME` 以及所有
`RHYTHM_*_BIND` / `RHYTHM_*_PORT` listener override，改为 `RHYTHM_PUBLIC_URL`；只有独立前端才另设
`RHYTHM_GATEWAY_URL`。从按平台分别配置链接的版本升级时，将 `KookRhythmPlugin.publicBaseUrl`、
`DiscordRhythmPlugin.publicBaseUrl` 和 `TeamSpeakRhythmPlugin.publicBaseUrl` 中实际使用的页面 origin 搬到
`RHYTHM_PUBLIC_URL`（或 `RhythmWebPolicyPlugin.publicOrigin` fallback），确认所有平台一致后删除旧字段。默认 DNS-01
路径固定使用 `:31083`，direct overlay 使用默认 443，其他端口交给已有反向代理。
