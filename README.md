# Rhythm 标准自部署

这是 Rhythm 唯一维护的 Docker Compose 部署包。标准拓扑始终同时启动：

- `rhythm` backend：宿主机 `127.0.0.1:3311`，包含业务 API 与私有 Pluxel Workbench；
- `gateway`：宿主机 `127.0.0.1:3310`，提供内置 SPA、公开 `/streamer/*` 并隔离管理面。

Gateway 不只是一个可选前端容器，也是公网 API 的安全边界，因此默认部署没有 frontend/profile 开关。完整房间功能
要求浏览器通过受信任的 HTTPS 访问；普通 HTTP 只适合 loopback 开发和部署健康诊断。

## 启动

在 Linux x86-64 服务器安装 Docker Engine 与 Docker Compose plugin，然后进入本目录：

```sh
cp .env.example .env
mkdir -p data music
# 编辑 .env：填写 DATABASE_URL、RHYTHM_PUBLIC_URL，并把两个镜像固定为同一个版本
docker compose pull
docker compose up -d --wait
docker compose ps
```

如果服务器还没有 TLS 入口，可使用同目录的官方 Caddy overlay：

```dotenv
RHYTHM_PUBLIC_URL=https://rhythm.example.com
RHYTHM_DOMAIN=rhythm.example.com
```

```sh
docker compose -f compose.yaml -f compose.https.yaml pull
docker compose -f compose.yaml -f compose.https.yaml up -d --wait
```

Caddy 会公开 80/443，并把整站代理到容器网络中的 Gateway。公开域名默认使用 ACME 自动证书，因此域名必须正确解析且
80/443 可被证书机构访问。已有 Caddy/Nginx 或负载均衡 TLS 时继续使用基础 `compose.yaml`，不要启动第二个 TLS 入口。

生产环境必须配置独立 PostgreSQL：

```dotenv
DATABASE_URL=postgresql://rhythm:PASSWORD@db.example.com:5432/rhythm?sslmode=verify-full
RHYTHM_REQUIRE_POSTGRES=true
```

默认会在缺少 `DATABASE_URL` 时拒绝启动。只有明确的本机/demo 部署才设置
`RHYTHM_REQUIRE_POSTGRES=false`，使用 `data/` 中的持久 PGlite。生产还应将 `RHYTHM_IMAGE` 与
`RHYTHM_GATEWAY_IMAGE` 固定为同一个 release 或 `sha-*` 标签。

首次启动前填写最终供用户打开的前端地址：

```dotenv
RHYTHM_PUBLIC_URL=https://music.example.com
```

它会初始化 KOOK、Discord 和 TeamSpeak Rhythm 插件生成控制链接所用的 `publicBaseUrl`。这个值是新数据目录的
启动默认配置；初始化后仍由 Workbench 中的插件配置持久化管理，升级容器不会覆盖管理员已经保存的值。

## 公网入口

公网只暴露一个 HTTPS 域名，并将整站转发到 Gateway：

```text
https://music.example.com
  └─ 外层 TLS/Nginx
       └─ http://127.0.0.1:3310
            ├─ /、/r/*：内置 SPA 与 history fallback
            ├─ /assets/*：静态资源
            ├─ /streamer/*：业务 API、RPC 与事件流
            ├─ /__pluxel/*：固定 404
            └─ /_gateway/health：Gateway 健康检查
```

外层 Nginx 不需要按路径拆分，也不要代理 `3311`：

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

Gateway 会校验并继续传递外层的 `X-Forwarded-Proto`，使 backend 能把外部 HTTPS 与内部 HTTP hop 识别为同一个公开
origin。因此内置前端保持 `RHYTHM_ALLOWED_ORIGINS=[]`；不要为了反代链路把自己的同源地址加入 CORS allowlist。

纯离线内网可使用 `rhythm.home.arpa` 与 Caddy 内部 CA：

```dotenv
RHYTHM_PUBLIC_URL=https://rhythm.home.arpa
RHYTHM_DOMAIN=rhythm.home.arpa
RHYTHM_CADDY_TLS_DIRECTIVE="tls internal"
```

启动 overlay 后导出根证书，并安装到每台浏览器设备的系统信任库：

```sh
docker compose -f compose.yaml -f compose.https.yaml \
  cp caddy:/data/caddy/pki/authorities/local/root.crt ./rhythm-local-ca.crt
```

没有安装根证书的自签名页面仍不属于可信浏览器上下文。不要直接为裸 IP 维护证书；设备兼容性、SAN 和续期都更麻烦。

内置前端支持 `/r/<roomId>` 等客户端路由的直接访问和刷新。前端路由应避开 Gateway 保留的
`/streamer`、`/__pluxel`、`/_gateway/health` 和 `/assets` 命名空间。

## 使用其他前端

不使用内置前端也不影响 Gateway。其他位置部署的 Rhythm 前端在“添加服务器”中填写 Gateway 的公网根地址：

```text
https://music.example.com
```

不要追加 `/streamer`；前端会自行请求 `https://music.example.com/streamer/*`。在 Workbench 的
`RhythmApiPlugin.allowedOrigins` 中逐项填写外部前端的精确 HTTPS origin，例如：

```json
["https://player.example.net", "https://music.example.org"]
```

不要填写 `*`、路径或 API 地址。Gateway 自带前端与 API 同源，不需要加入这个列表。首次启动新数据目录时也可
直接在 `.env` 中填写 JSON 数组，不必先进入 Workbench：

```dotenv
RHYTHM_ALLOWED_ORIGINS=["https://player.example.net","https://music.example.org"]
```

Compose 会把这两个部署变量映射为 Pluxel 原生的分层 plugin config 环境变量。该值与
`RHYTHM_PUBLIC_URL` 分开：设置公开页面地址不会自动启用跨站 Cookie/CORS。

## Workbench

Workbench 只通过 SSH 隧道访问：

```sh
ssh -N -L 3311:127.0.0.1:3311 user@server
```

打开 `http://127.0.0.1:3311/__pluxel/workbench/` 完成 Bot、音乐来源和其他业务配置，也可以修改首次启动时由
env 初始化的 `allowedOrigins` 与 `publicBaseUrl`。Bot token、音乐账号、插件启停与业务配置由 Workbench 和 Vault
管理；不要将 3311 暴露到公网。

## 备份与升级

备份 `.env`、完整 `RHYTHM_DATA_DIR` 和外部 PostgreSQL；`RHYTHM_MUSIC_DIR` 是只读本地曲库。不要让两个
backend 容器同时写同一个数据目录。

升级前先备份，将两个镜像改为相同的新版本，然后运行：

```sh
docker compose pull
docker compose up -d --wait
docker compose ps
```

回滚时恢复对应备份，并将两个镜像一起改回原版本。
