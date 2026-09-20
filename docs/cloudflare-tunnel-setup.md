# Setting up the Cloudflare Tunnel

The tunnel is the only way in from the internet. `cloudflared` connects outbound to Cloudflare and hands every request to the `auth-proxy` container, so no port needs to be opened on your router.

You need a Cloudflare account with your domain (examples use `example.com`) and Zero Trust enabled (the free plan is enough).

## 1. Create the tunnel

1. Open the Cloudflare dashboard and go to **Zero Trust > Networks > Tunnels**.
2. **Create a tunnel**, choose type **Cloudflared**, and name it, e.g. `home`.
3. On the install step, copy the token from the shown `cloudflared ... --token <TOKEN>` command. You don't need to run that command, since the compose stack runs `cloudflared` for you.
4. Put the token into `.env` as `CLOUD_FLARE_TUNNEL_TOKEN`.

## 2. Route the auth domain

Under the tunnel's **Public Hostname** tab, add a hostname:

| Field | Value |
| --- | --- |
| Subdomain / Domain | `auth` / `example.com` (this is your `AUTH_DOMAIN`) |
| Service type | `HTTP` |
| URL | `auth-proxy:80` |

`auth-proxy` is the container name, which `cloudflared` reaches over the shared `tunnel` network. Cloudflare creates the DNS record automatically.

Use `HTTP`, not `HTTPS`: TLS ends at Cloudflare, and the proxy uses the `X-Forwarded-Proto` header that Cloudflare sends.

## 3. Start the stack

Finish the Entra ID setup ([entra-id-setup.md](entra-id-setup.md)), then:

```sh
docker compose up -d --build
```

Check `docker compose logs cloudflared` for `Registered tunnel connection`, and that the tunnel shows as **Healthy** in the dashboard.

## Adding services after auth works

Once login works with the example service, every new service needs three things:

### 1. Run it on the `home-services` network

In the service's own compose file, join the external network. Do not publish ports; the proxy is the only entry.

```yaml
services:
  myapp:
    image: ghcr.io/example/myapp
    restart: unless-stopped
    networks:
      - services

networks:
  services:
    name: home-services
    external: true
```

Start the main stack first, since it creates the network. See [example-service/docker-compose.yml](../example-service/docker-compose.yml).

### 2. Map the domain in `config/hosts.conf`

Add one line with the domain, the container (service) name, and the port the app listens on:

```
myapp.example.com   myapp:8080
```

The proxy picks the change up within about 5 seconds, no restart needed. Check `docker compose logs auth-proxy` for `mapping reloaded`, or for a message if the line was rejected.

### 3. Route the domain through the tunnel

Cloudflare must send the domain to the tunnel. Either:

- **Per service**: on the tunnel's **Public Hostname** tab add `myapp.example.com` with type `HTTP` and URL `auth-proxy:80`. The URL is always `auth-proxy:80`, never the service itself, because the proxy does the routing.
- **Once for all services (wildcard)**: add a public hostname `*.example.com` with URL `auth-proxy:80`. The dashboard doesn't create DNS for wildcards, so add a proxied CNAME record in **DNS > Records**: name `*`, target `<tunnel-id>.cfargotunnel.com`. The tunnel ID is shown on the tunnel's overview page. After that, new services need only steps 1 and 2.

### Rules

- Domains must be subdomains of `COOKIE_DOMAIN` (e.g. `.example.com`), because the login cookie is shared. A domain like `other.org` will loop on login.
- One level of subdomain is covered by `*.example.com`. For `app.home.example.com`, Cloudflare's free universal certificate does not apply, so keep to single-level names.
- Unknown domains return `404 Unknown host` after login.

### Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| Cloudflare error 1033 | `cloudflared` isn't running or the token is wrong. |
| Cloudflare error 502/530 | The public hostname URL is wrong; it must be `auth-proxy:80`. |
| `NXDOMAIN` | No DNS record for the domain (no wildcard CNAME, no per-host entry). |
| 404 `Unknown host` | Missing or rejected line in `config/hosts.conf`. |
| 502 from nginx | The service container isn't running, is on another network, or the port is wrong. |
