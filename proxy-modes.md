# Proxy Modes

The container supports three proxy modes, selected at runtime via the `PROXY_MODE` environment variable.

| Mode     | Default | Runtime       | Description                                    |
|----------|---------|---------------|------------------------------------------------|
| `nrpc`   | ✓       | NGINX, Angie  | HCL Domino NRPC routing (port 1352)           |
| `stream` |         | NGINX, Angie  | Generic TCP stream proxy                       |
| `https`  |         | Angie         | HTTPS reverse proxy with ACME certificates     |

```sh
PROXY_MODE=nrpc     # default
PROXY_MODE=stream
PROXY_MODE=https
```

## Custom Configuration

Any mode can be overridden by mounting a custom config file at the standard path:

```sh
-v /path/to/my.conf:/nginx.conf   # for NGINX
-v /path/to/my.conf:/angie.conf   # for Angie
```

The mounted file is processed through `envsubst` — environment variables are substituted at startup, so you can still use `$NGINX_PORT` and other variables in your custom config.

---

## NRPC Mode (default)

NRPC mode routes HCL Domino NRPC traffic based on the server name extracted from the first packet.
This is the primary use case of the project. See the [main README](README.md) for full documentation.

### Key Variables

| Variable             | Default      | Description                              |
|----------------------|--------------|------------------------------------------|
| `NGINX_PORT`         | `1352`       | Listening port                           |
| `DOMINO_PORT`        | `1352`       | Target Domino port                       |
| `NGINX_MAP_DEFAULT`  | *(required)* | Default backend mapping                  |
| `NGINX_MAP_INET`     | *(required)* | Internet address backend mapping         |
| `DOMINO_DEFAULT_ORG` | `default`    | Org name when none present in request    |
| `NGINX_REPLACE_DOTS` | `on`         | Replace dots with underscores in names   |

---

## Stream Mode

Generic TCP stream proxy — forwards connections to a fixed upstream without NRPC inspection.
Useful for simple TCP proxying of any protocol.

```sh
PROXY_MODE=stream
```

### Key Variables

| Variable         | Default      | Description           |
|------------------|--------------|-----------------------|
| `NGINX_PORT`     | `1352`       | Listening port        |
| `NGINX_UPSTREAM` | *(required)* | Backend `host:port`   |

---

## HTTPS Mode

HTTPS reverse proxy with SSL termination. On the **Angie** target, TLS certificates are issued and
renewed automatically using the built-in ACME client (Let's Encrypt or compatible CA).

```sh
PROXY_MODE=https
```

> **Note:** ACME certificate management requires the Angie image (`./build.sh -angie`).
> The NGINX HTTPS template requires externally managed certificates mounted into the container.

### Key Variables

| Variable            | Default                              | Description                              |
|---------------------|--------------------------------------|------------------------------------------|
| `NGINX_PORT`        | `1352`                               | HTTPS listening port (use `8443`)        |
| `NGINX_HTTP_PORT`   | `8080`                               | HTTP port for ACME HTTP-01 challenge     |
| `NGINX_SERVER_NAME` | *(required)*                         | Public hostname for TLS certificate      |
| `NGINX_UPSTREAM`    | *(required)*                         | Backend `host:port`                      |
| `NGINX_ACME_SERVER` | Let's Encrypt staging                | ACME directory URL                       |
| `NGINX_ACME_EMAIL`  | *(required)*                         | Contact email for ACME account           |

### Port Mapping

The container binds to unprivileged ports (no elevated privileges or `setcap` required).
Map them externally for standard HTTPS access:

```yaml
ports:
  - "80:8080"    # ACME HTTP-01 challenge — must be reachable from the internet
  - "443:8443"   # HTTPS
```

### Certificate Storage

Certificates are stored at `/var/angie/acme_client/` inside the container:

| File              | Description                                       |
|-------------------|---------------------------------------------------|
| `account.key`     | ACME account registration key — do not lose this  |
| `certificate.pem` | Issued certificate                                |
| `private.key`     | Certificate private key                           |

Mount this directory as a persistent volume. Losing the volume means re-registering an ACME account
and re-issuing certificates. Let's Encrypt enforces rate limits on certificate issuance.

### ACME Servers

| URL                                                        | Use              |
|------------------------------------------------------------|------------------|
| `https://acme-staging-v02.api.letsencrypt.org/directory`  | Testing (default)|
| `https://acme-v02.api.letsencrypt.org/directory`          | Production       |

Always test with staging first. Staging certificates are functionally identical but not
browser-trusted. Switch to production once the full flow is confirmed working.

### Complete Example

See [examples/angie-https](examples/angie-https/README.md) for a complete working setup
with Docker Compose.
