ARG CADDY_VERSION=2.11.4
FROM docker.io/library/caddy:${CADDY_VERSION}-builder-alpine AS builder

ARG CADDY_CLOUDFLARE_VERSION=v0.2.4
RUN xcaddy build --with github.com/caddy-dns/cloudflare@${CADDY_CLOUDFLARE_VERSION}

FROM docker.io/library/caddy:${CADDY_VERSION}-alpine
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
