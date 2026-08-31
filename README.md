# Rhythm 标准自部署

这个目录一次启动 Rhythm backend、同版本点歌页面、安全 gateway 和私有 Workbench。部署契约刻意只让管理员描述
一个公开地址：

```dotenv
RHYTHM_PUBLIC_URL=https://music.example.com:31083
```

它必须是用户浏览器真正访问的完整 origin：包含 `http://` 或 `https://`，非默认端口必须写出，不包含非根
路径、query 或 fragment。Caddy 用它选择公开站点，backend 用同一个值初始化 KOOK、Discord 和 TeamSpeak
控制链接，因此没有另一组 domain、scheme 或 public port 需要同步。

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
docker compose build --pull caddy
docker compose up -d --wait
docker compose ps
docker compose logs --tail=100 caddy
curl -fsS https://music.example.com:31083/_gateway/health
```

`Caddy.cloudflare.Dockerfile` 以官方 Caddy builder 构建并固定安装 `caddy-dns/cloudflare`。可确认实际模块：

```sh
docker compose exec caddy caddy list-modules | grep '^dns.providers.cloudflare$'
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
docker compose logs --tail=100 caddy
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
`http://127.0.0.1:3310`。公开入口可以是 443、8443 或其他端口，只要
`RHYTHM_PUBLIC_URL` 与浏览器实际地址完全一致。不要拆分 Rhythm path，也不要代理 3311。

Nginx 最小配置：

```nginx
location / {
    proxy_pass http://127.0.0.1:3310;
    proxy_http_version 1.1;
    proxy_buffering off;
    proxy_read_timeout 3600s;
    proxy_set_header Host $http_host;
    proxy_set_header X-Forwarded-Host $http_host;
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
}
```

## 启动后配置 Bot

Workbench 固定只发布到服务器 loopback。先在自己的电脑建立 SSH 隧道：

```sh
ssh -N -L 3311:127.0.0.1:3311 user@server
```

打开 `http://127.0.0.1:3311/__pluxel/workbench/`，保存 Bot token、登录音乐平台并启用所需插件。新数据目录的
`RHYTHM_PUBLIC_URL` 会初始化各 Bot 的 `publicBaseUrl`；之后持久化配置和 Workbench 成为 authority，修改
`.env` 不会覆盖管理员已经保存的 Plugin 配置。

## 网络边界

```text
公网 https://music.example.com:31083
  └─ Caddy:31083：DNS-01 与 HTTPS
       └─ gateway:3310：SPA、/streamer/*、Workbench 隔离
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
docker compose cp caddy:/data/caddy/pki/authorities/local/root.crt ./rhythm-local-ca.crt
```

只有独立前端需要配置跨域。前端的服务器地址直接填写与 `RHYTHM_PUBLIC_URL` 相同的 origin，不追加
`/streamer`；同时在 Workbench 的 `RhythmApiPlugin.allowedOrigins` 中加入外部前端的精确 HTTPS origin。
新数据目录也可在 `.env` 预置：

```dotenv
RHYTHM_ALLOWED_ORIGINS=["https://player.example.net"]
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
docker compose build --pull caddy
docker compose up -d --wait
docker compose ps
```

从拆分地址变量的版本升级时，删除
`RHYTHM_DOMAIN`、`RHYTHM_PUBLIC_PORT`、`RHYTHM_PUBLIC_SCHEME` 以及所有
`RHYTHM_*_BIND` / `RHYTHM_*_PORT` listener override，改为一个精确的 `RHYTHM_PUBLIC_URL`。默认 DNS-01
路径固定使用 `:31083`，direct overlay 使用默认 443，其他端口交给已有反向代理。
