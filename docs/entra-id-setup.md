# Setting up Microsoft Entra ID (Office 365) login

The proxy signs users in through an Entra ID app registration in your Microsoft 365 tenant. Only accounts of that tenant can log in, and you can narrow it further to specific users.

You need: admin access to the Entra admin center, and a domain on Cloudflare (examples use `example.com`, with the login callback on `auth.example.com`).

## 1. Register the application

1. Open <https://entra.microsoft.com> and sign in as an admin.
2. Go to **Entra ID > App registrations > New registration**.
3. Fill in:
   - **Name**: e.g. `Home Auth Proxy`
   - **Supported account types**: *Accounts in this organizational directory only (Single tenant)*
   - **Redirect URI**: platform **Web**, value `https://auth.example.com/oauth2/callback`
4. Click **Register**.

On the overview page, copy:

| Value | `.env` variable |
| --- | --- |
| Application (client) ID | `ENTRA_CLIENT_ID` |
| Directory (tenant) ID | `ENTRA_TENANT_ID` |

The redirect URI must match `https://<AUTH_DOMAIN>/oauth2/callback` exactly.

## 2. Create a client secret

1. **Certificates & secrets > Client secrets > New client secret**.
2. Choose a description and an expiry (max 24 months; put a reminder in your calendar).
3. Copy the **Value** right away (not the *Secret ID*). It is shown only once. It goes into `ENTRA_CLIENT_SECRET`.

## 3. Permissions

Under **API permissions**, the default `Microsoft Graph > User.Read` (delegated) is enough. Make sure these delegated permissions exist too: `openid`, `profile`, `email`. If your tenant requires it, click **Grant admin consent for <tenant>**.

## 4. Make sure the e-mail claim is present

oauth2-proxy identifies users by their e-mail address. Some accounts have no `email` claim by default.

1. **Token configuration > Add optional claim**.
2. Token type **ID**, select `email` (and optionally `upn`), and confirm. Accept the prompt to add the Graph `email` permission.

## 5. Restrict who may log in (recommended)

By default every user in your tenant can sign in. To allow only selected people:

1. Go to **Entra ID > Enterprise applications** and open your app.
2. **Properties > Assignment required? = Yes**, save.
3. **Users and groups > Add user/group** and assign the people (or a group) who may access your services.

Everyone else gets an Entra error page instead of reaching your services. Optionally, set `ALLOWED_EMAIL_DOMAINS` in `.env` as a second check.

## 6. Configure the stack

1. Copy `.env.example` to `.env` and fill in:
   - `ENTRA_TENANT_ID`, `ENTRA_CLIENT_ID`, `ENTRA_CLIENT_SECRET` from above.
   - `AUTH_DOMAIN=auth.example.com`
   - `COOKIE_DOMAIN=.example.com` (leading dot). All protected services must be subdomains of it, because a single sign-on cookie is shared across them.
   - `OAUTH2_COOKIE_SECRET`, generated with one of:

     ```sh
     openssl rand -base64 32 | tr -- '+/' '-_'
     ```

     ```powershell
     [Convert]::ToBase64String((1..32 | % { Get-Random -Maximum 256 }) -as [byte[]]).Replace('+','-').Replace('/','_')
     ```

2. Add your services to `config/hosts.conf` (see the comments in that file). `auth.example.com` does not need an entry.

## 7. Cloudflare tunnel

1. In Cloudflare Zero Trust go to **Networks > Tunnels**, create a tunnel, and copy its token into `CLOUD_FLARE_TUNNEL_TOKEN`.
2. Add a **public hostname** for each domain you use, including `auth.example.com`, with service type **HTTP** and URL `auth-proxy:80`.
   - For a catch-all, use `*.example.com`. The dashboard does not create DNS for wildcards, so add a proxied CNAME record `*` pointing to `<tunnel-id>.cfargotunnel.com` yourself.

## 8. Start and test

```sh
docker compose up -d --build
cd example-service && docker compose up -d
```

Open `https://hello.example.com`. You should be redirected to Microsoft, sign in, and land on the whoami page, which shows an `X-Auth-Request-Email` header with your address.

Backends receive the identity in `X-Auth-Request-User`/`X-Auth-Request-Email` (also as `X-Forwarded-User`/`X-Forwarded-Email`). Users can sign out at `https://<any-domain>/oauth2/sign_out`.

## Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| `AADSTS50011` redirect URI mismatch | The redirect URI in Entra differs from `https://<AUTH_DOMAIN>/oauth2/callback` (check scheme and trailing slash). |
| `AADSTS7000215` invalid client secret | You copied the secret ID instead of the value, or it expired. |
| `AADSTS50105` user not assigned | "Assignment required" is on and the user has no assignment. |
| Login loop | `COOKIE_DOMAIN` doesn't cover the service domain, or requests reach the proxy over plain HTTP without `X-Forwarded-Proto: https`. |
| 403 "unauthorized" from oauth2-proxy | No e-mail claim (see step 4) or `ALLOWED_EMAIL_DOMAINS` mismatch. Check `docker compose logs oauth2-proxy`. |
| 404 "Unknown host" after login | The domain is not listed in `config/hosts.conf`, or the line was rejected (`docker compose logs auth-proxy`). |
| 502 after login | The target container isn't running or isn't on the `home-services` network. |

Known limitation: after logging in you are returned to the original URL, but only up to the first `&` of its query string.

## Rotating the client secret

Create a new secret in Entra, update `ENTRA_CLIENT_SECRET`, run `docker compose up -d`, then delete the old secret.
