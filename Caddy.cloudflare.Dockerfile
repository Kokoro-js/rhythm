FROM docker.io/library/caddy:2.11.4-builder-alpine AS builder

RUN xcaddy build --with github.com/caddy-dns/cloudflare@v0.2.4

FROM docker.io/library/caddy:2.11.4-alpine
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
