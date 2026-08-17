FROM caddy:2-builder AS builder

RUN xcaddy build \
    --with github.com/caddy-dns/cloudflare \
    --with github.com/lucaslorentz/caddy-docker-proxy/v2 \
    --with github.com/hslatman/caddy-crowdsec-bouncer/http

FROM caddy:2

COPY --from=builder /usr/bin/caddy /usr/bin/caddy

# This command is required for the docker-proxy plugin to start
CMD ["caddy", "docker-proxy"]