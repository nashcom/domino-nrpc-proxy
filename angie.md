# Angie Integration

## What is Angie?

[Angie](https://angie.software) is a high-performance web server and reverse proxy — a community fork of NGINX maintained by former core NGINX developers.
It is fully compatible with NGINX configuration syntax while adding features not available in standard NGINX, including:

- Built-in ACME client for automatic TLS certificate management
- Additional stream preread modules (MQTT, RDP)
- Extended configuration and monitoring options

## Why Angie?

Angie was added to the Domino NRPC Proxy project to expand its use cases beyond NRPC routing:

1. **Automatic TLS certificates** via the built-in ACME client — no external certificate management tool required
2. **Additional proxy modes** — the HTTPS mode with automated certificate management is Angie-specific
3. **A modern alternative** for users who need its extended feature set

## How Angie is Built

Angie is built from **official source releases** published on the [Angie GitHub repository](https://github.com/angie-pro/angie).
We compile Angie ourselves alongside the NRPC stream preread module.

This approach:

- Uses no pre-built Angie binaries or third-party container images
- Produces reproducible, auditable builds
- Supports multi-architecture (AMD64 and ARM64)
- Ensures the NRPC module matches the exact Angie version compiled

> **Note:** This project is not affiliated with the Angie project.
> We build from their published open-source releases from GitHub under the terms of their license.

## Modules Compiled with Angie

In addition to the NRPC preread module, the Angie target includes:

| Module                             | Description                        |
|------------------------------------|------------------------------------|
| `ngx_stream_mqtt_preread_module`   | MQTT protocol preread              |
| `ngx_stream_rdp_preread_module`    | RDP protocol preread               |
| `http_ssl_module`                  | SSL/TLS support                    |
| `http_acme_module`                 | Built-in ACME client               |

## Building the Angie Image

```bash
./build.sh -angie
```

Available base images:

```bash
./build.sh -angie          # Alpine (default)
./build.sh -angie -wolfi   # Chainguard Wolfi
```

The Angie image is tagged as `domino-nrpc-proxy:angie`.

## Running the Angie Container

```bash
./run.sh -angie
```

By default, the container starts in NRPC mode on port 1352 — the same behavior as the NGINX image.

## HTTPS with Automatic Certificates

Angie's built-in ACME client enables automatic TLS certificate management without external tools.
Certificates are issued and renewed automatically using the HTTP-01 challenge.

See the [Angie HTTPS example](examples/angie-https/README.md) for a complete working setup.

## Proxy Modes

Both the NGINX and Angie images support multiple proxy modes via the `PROXY_MODE` environment variable.
The HTTPS mode with ACME is only available on the Angie image.

See [Proxy Modes](proxy-modes.md) for full details.
