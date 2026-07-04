# entrypoint.sh — Functionality Documentation & Configuration

## Overview

`entrypoint.sh` is the container entry point for the Domino NRPC Proxy. It manages the full lifecycle of an **nginx** or **Angie** reverse-proxy process inside a container:

- Runtime detection (nginx vs. Angie)
- Template-based configuration rendering with environment-variable substitution
- Atomic config reload on template changes
- TLS certificate management — either via file-watch or remote Domino CertMgr download
- Prometheus metrics export
- Graceful shutdown on `SIGTERM`/`SIGINT`

---

## Environment Variables

Most variables have defaults and are registered for `envsubst` into nginx config templates.
The secrets run-time directory is `/tls`. Certificates and keys are copied from `/run/secrets/nginx` directory.


| Variable                  | Default                             | Description                                                                        |
|---------------------------|-------------------------------------|------------------------------------------------------------------------------------|
| `METRICS_FILE`            | `/tmp/nginx-metrics.prom`           | Path of the Prometheus metrics output file                                         |
| `INTERVAL_SECONDS`        | `10`                                | Main poll loop interval in seconds                                                 |
| `CERT_CHECK_INTERVAL`     | `30`                                | Minimum seconds between CertMgr remote checks                                      |
| `CONFIG_KEEP_RELEASES`    | `3`                                 | Number of old config release directories to retain                                 |
| `PROXY_MODE`              | `nrpc`                              | Template set to load when no mounted config is present (`nrpc`, `stream`, `https`) |
| `CERTMGR_HOST`            |                                     | Hostname of the Domino CertMgr server; enables remote cert download when set       |
| `DEBUG_SCRIPT`            |                                     | Set to any non-zero value to enable `log_debug` output                             |
| `NGINX_LOG_LEVEL`         | `notice`                            | nginx `error_log` severity                                                         |
| `NGINX_ACCESS_LOG`        | `off`                               | nginx access log path or `off`                                                     |
| `NGINX_REPLACE_DOTS`      | `off`                               | nginx `server_name_in_redirect` / dot-replacement setting                          |
| `NGINX_PORT`              | `1352`                              | NRPC listener port                                                                 |
| `NGINX_HTTP_PORT`         | `8080`                              | HTTP listener port                                                                 |
| `DOMINO_PORT`             | `1352`                              | Upstream Domino NRPC port                                                          |
| `NGINX_CONNECTIONS`       | `8000`                              | `worker_connections` value                                                         |
| `NGINX_RLIMIT_NOFILE`     | `65536`                             | `worker_rlimit_nofile` value                                                       |
| `DOMINO_DEFAULT_ORG`      | `default`                           | Default Domino organisation name                                                   |
| `NGINX_SERVER_NAME`       | `_`                                 | nginx `server_name` directive                                                      |
| `NGINX_UPSTREAM`          | `127.0.0.1`                         | Upstream host/IP for proxied connections                                           |
| `NGINX_METRICS_PORT`      | `9100`                              | Port nginx serves the metrics stub-status on                                       |
| `NGINX_SSL_CERT`          | `/run/secrets/nginx/tls.crt`        | Path of the TLS certificate                                                        |
| `NGINX_SSL_KEY`           | `/run/secrets/nginx/tls.key`        | Path of the TLS private key                                                        |
| `NGINX_SSL_PASSWORD_FILE` | `/run/secrets/nginx/tls.pass`       | Path of the TLS key password file                                                  |
| `NGINX_RESOLVER`          | First entry from `/etc/resolv.conf` | DNS resolver address for nginx                                                     |
| `NGINX_RESOLVER_IPV6`     | `ipv6=off`                          | IPv6 resolver option string                                                        |
| `NGINX_MAP_DEFAULT`       | `$nrpc_preread_server_name`         | Default mapping target in stream map block                                         |
| `NGINX_MAP_INET`          | `$nrpc_preread_server_name`         | INET mapping target in stream map block                                            |


## LEGO ACME environment variables

LEGO ACME is integrated into the container image by default.
The container image supports LEGO environment variables for configuration.
Check the [LEGO documentation](https://go-acme.github.io/lego/references/ref-flags/index.html) for a complete list of environment variables.


### Required parameters

| Variable                  | Default                             | Description                                                                        |
|---------------------------|-------------------------------------|------------------------------------------------------------------------------------|
| `LEGO_ACCEPT_TOS`         | -                                   | Must be set to `true` to enable the LEGO functionality                             |
| `LEGO_HTTP_WEBROOT`       | /tmp/lego_web_root                  | Specified in `nginx.conf` to define the NGINX ACME web-root                        |


## Angie specific Environment Variables

| Variable                  | Default                             | Description                                                                        |
|---------------------------|-------------------------------------|------------------------------------------------------------------------------------|
| `NGINX_ACME_SERVER`       | Let's Encrypt staging URL           | ACME directory URL                                                                 |
| `NGINX_ACME_EMAIL`        |                                     | ACME account e-mail                                                                |


---

## Directory Layout

| Path                       | Purpose                                                  |
|----------------------------|----------------------------------------------------------|
| `/run/config/nginx`        | Mount point for externally supplied config templates     |
| `/run/secrets/nginx`       | Mount point for TLS certificates and keys                |
| `/tmp/ngx_cfg`             | Working directory for rendered config releases           |
| `/tmp/ngx_cfg/current`     | Symlink pointing at the active config release directory  |
| `/tmp/ngx_cfg/<timestamp>` | Timestamped immutable config release directory           |
| `/tmp/nginx-metrics.prom`  | Prometheus metrics file (atomically replaced each cycle) |
| `/cfg/<runtime>_<mode>`    | Built-in config template sets, selected by `PROXY_MODE`  |

---

## Runtime Detection

At startup the script detects whether `/nginx` or `/angie` is executable and sets `RUNTIME` and `BIN` accordingly. If neither binary is found at the well-known path, it falls back to `nginx` on `PATH`. An empty `RUNTIME` is a fatal error.

---

## Configuration Template Rendering (`update_cfg`)

1. A new release directory is created at `/tmp/ngx_cfg/<YYYYMMDD-HHMMSS>`.
2. An environment-variable allow-list is built from `env_variables.txt` (searched in three locations: the persistent env-var file, the template directory, and `/`).
3. Every file in the template directory (excluding `*.txt`) is processed with `envsubst`, substituting only the declared variables.
4. The rendered config is validated with `nginx -t`.
5. On success, a `current.new` symlink is created and atomically promoted to `current` with `mv -Tf` — nginx never sees a partial config directory.
6. Old releases beyond `CONFIG_KEEP_RELEASES` are pruned by `cleanup_releases`.
7. On validation failure the bad release is left in place for inspection and `CONFIG_UPDATE_ERRORS` is incremented.

### Config Sources (priority order)

1. Mounted file at `/run/config/nginx/nginx.conf` — used as-is.
2. Built-in template selected by `PROXY_MODE` from `/cfg/<runtime>_<mode>/`.

---

## nginx Lifecycle

### Start (`nginx_start`)

Loops until a valid rendered config is available, then starts the nginx process. If the initial render fails but a previous `current` config exists, nginx starts on that fallback to avoid a cold-start outage.

### Reload (`nginx_reload`)

Sends `nginx -s reload` against the current config directory. Called after any successful config or certificate update.

### Graceful Shutdown

`SIGTERM` and `SIGINT` are trapped; they set `RUNNING=0`, which exits the main loop. `stop_nginx` is then called (defined in `entrypoint_legacy.sh` or the runtime itself).

---

## Certificate Management

Two modes, selected by whether `CERTMGR_HOST` is set:

### File-watch mode (`CERTMGR_HOST` unset)

- Watches `/run/secrets/nginx` for files newer than the last-checked timestamp.
- On any change, increments `CERT_UPDATE_COUNT` and triggers an nginx reload.

### CertMgr download mode (`CERTMGR_HOST` set)

Polled every `CERT_CHECK_INTERVAL` seconds:

1. For each `*.crt` file in `/run/secrets/nginx`, the hostname is extracted from the certificate's SAN list (`get_hostname_from_cert_file`):
   - The first non-wildcard DNS SAN is preferred.
   - A wildcard SAN falls back to `certmgr.<domain>`.
2. The certificate chain is downloaded from `CERTMGR_HOST:443` using `openssl s_client` (`check_cert_download`).
3. `cert_update` validates the download before installing:
   - If the SHA-256 fingerprint matches the installed cert, the download is silently discarded.
   - If the cert's public key does not match the local private key, the download is rejected, an error is logged, and the mismatched fingerprint is written to `/tmp/last_fingerprint_error.txt` to suppress duplicate error messages.
   - On a valid new cert, it is copied over the existing `.crt` file.
4. If any cert was updated, nginx is reloaded.

---

## Prometheus Metrics

Written atomically to `METRICS_FILE` (default `/tmp/nginx-metrics.prom`) each main-loop iteration via a temporary file + `mv`.

| Metric                                      | Type  | Description                                |
|---------------------------------------------|-------|--------------------------------------------|
| `DominoProxy_healthy`                       | gauge | Always `1` when the process loop runs      |
| `DominoProxy_config_status`                 | gauge | `0` = OK, `2` = last render failed         |
| `DominoProxy_config_update_count`           | gauge | Cumulative successful config renders       |
| `DominoProxy_config_update_errors`          | gauge | Cumulative failed config renders           |
| `DominoProxy_config_last_updated_timestamp` | gauge | Unix timestamp of last successful render   |
| `DominoProxy_cert_last_updated_timestamp`   | gauge | Unix timestamp of last certificate update  |
| `DominoProxy_cert_update_count`             | gauge | Cumulative certificate updates             |
| `DominoProxy_cert_update_errors`            | gauge | Cumulative certificate key-mismatch errors |
| `DominoProxy_stat_update_timestamp`         | gauge | Unix timestamp of the metrics write        |

---

## Main Loop

```
nginx_start
└─ loops until valid config, then starts nginx

process_loop  (first call, then every INTERVAL_SECONDS)
├─ check if templates are newer than current release
│   └─ if yes: update_cfg → nginx_reload
├─ cert_update_check
│   └─ file-watch or CertMgr poll → nginx_reload if changed
└─ write_metrics_file

trap SIGTERM/SIGINT → RUNNING=0 → stop_nginx
```

---

## Logging

| Function     | Output                                                                          |
|--------------|---------------------------------------------------------------------------------|
| `log`        | `YYYY/MM/DD HH:MM:SS <message>` to stdout                                       |
| `log_space`  | Same, surrounded by blank lines                                                 |
| `log_error`  | Prefixes `ERROR:`                                                               |
| `log_debug`  | Only when `DEBUG_SCRIPT` is set and non-zero                                    |
| `dump_file`  | Prints a file with a header delimiter; passes optional flags (e.g. `-n`) to `cat` |

---

## Security Notes

- `umask 0077` is set before any file is created, so rendered configs and temp files are owner-readable only.
- `set +e` is in effect in the function body; `set -e` is re-enabled at the main entry point so startup failures abort the process.
- Private-key/certificate pairing is verified by comparing public-key hashes before any cert is installed.


