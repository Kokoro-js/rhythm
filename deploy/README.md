# Rhythm 部署包

在 Linux x86-64 服务器安装 Docker Engine 与 Docker Compose plugin，然后进入本目录。

## 启动

```sh
cp .env.example .env
mkdir -p data music
docker compose pull
docker compose up -d --wait
docker compose ps
```

默认使用 `data/` 中的持久化 PGlite。需要外部 PostgreSQL 时填写：

```dotenv
DATABASE_URL=postgresql://rhythm:PASSWORD@db.example.com:5432/rhythm?sslmode=verify-full
RHYTHM_REQUIRE_POSTGRES=true
```

生产部署还应将 `RHYTHM_IMAGE` 与 `RHYTHM_GATEWAY_IMAGE` 固定为同一个 release 或 `sha-*` 标签。

## 公网入口

将公网 HTTPS 域名完整转发到 `http://127.0.0.1:3310`。gateway 已处理静态前端、SPA fallback、
`/streamer/*` 长连接和管理面隔离；外层反代不需要单独拆分路径。

Workbench 只通过 SSH 隧道访问：

```sh
ssh -N -L 3311:127.0.0.1:3311 user@server
```

打开 `http://127.0.0.1:3311/__pluxel/workbench/` 完成 Bot、音乐来源、`allowedOrigins` 和
`publicBaseUrl` 配置。Bot token、音乐账号、插件启停与业务配置都在 Workbench 中管理，不需要写入 `.env`；
`.env` 只负责镜像、端口、数据目录和可选数据库。不要将 3311 暴露到公网。

## 备份与升级

备份 `.env` 与 `RHYTHM_DATA_DIR`；使用外部 PostgreSQL 时同时备份数据库。

升级前先备份，将两个镜像改为相同的新版本，然后运行：

```sh
docker compose pull
docker compose up -d --wait
docker compose ps
```

回滚时恢复对应备份，并将两个镜像一起改回原版本。
