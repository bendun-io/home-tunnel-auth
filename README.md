# Home Authentication Service

Cloudflare Tunnel -> nginx -> Entra ID (Office 365) login -> your Docker services.

```
Internet -> cloudflared --(tunnel net)--> auth-proxy (nginx) --(home-services net)--> your services
                                              |
                                        (auth-internal net)
                                              v
                                        oauth2-proxy -> Microsoft Entra ID
```

- `cloudflared` and `auth-proxy` share the `tunnel` network.
- `auth-proxy` also sits on the `home-services` network, which any other compose project can join (`external: true`).
- Every request is checked by oauth2-proxy via nginx `auth_request`; unauthenticated users are redirected to Microsoft.
- `config/hosts.conf` maps domains to services. It is mounted read-only and re-read every few seconds, no restart needed.

## Quick start

1. Set up Entra ID ([docs/entra-id-setup.md](docs/entra-id-setup.md)) and the Cloudflare tunnel ([docs/cloudflare-tunnel-setup.md](docs/cloudflare-tunnel-setup.md))
2. `cp .env.example .env` and fill it in.
3. Edit `config/hosts.conf`.
4. `docker compose up -d --build`
5. Try the example: `cd example-service && docker compose up -d`

## Adding a service

Attach it to the external network and list it in `config/hosts.conf`:

```yaml
services:
  myapp:
    image: ...
    networks: [services]
networks:
  services:
    name: home-services
    external: true
```

```
myapp.example.com   myapp:8080
```

Also route `myapp.example.com` through the Cloudflare tunnel (or use a wildcard); see [docs/cloudflare-tunnel-setup.md](docs/cloudflare-tunnel-setup.md#adding-services-after-auth-works). Domains must be subdomains of `COOKIE_DOMAIN`.

Services receive the user in the `X-Auth-Request-User` and `X-Auth-Request-Email` headers. They should not publish ports, so the proxy stays the only way in.
