# Angie HTTPS Reverse Proxy Example

This example demonstrates how to run the Domino NRPC Proxy in HTTPS mode using
[Angie](https://angie.software) with automatic TLS certificate management via
[Let's Encrypt](https://letsencrypt.org).

Certificates are obtained and renewed automatically using the built-in ACME client —
no manual certificate management required.

A [whoami](https://github.com/traefik/whoami) backend is included for testing.
Replace it with your actual backend once everything is working.

## Prerequisites

- Docker and Docker Compose installed
- A public hostname with a DNS A record pointing to this machine
- Ports **80** and **443** open and accessible from the internet
  (port 80 is required for the ACME HTTP-01 challenge)
- The `domino-nrpc-proxy:angie` image built locally or pulled from a registry

## Quick Start

**1. Copy the example environment file:**
```sh
cp env.example .env
```

**2. Edit `.env` and set your hostname and email:**
```sh
NGINX_SERVER_NAME=your.domain.example.com
NGINX_ACME_EMAIL=admin@example.com
```

**3. Start the stack:**
```sh
docker compose up -d
```

**4. Check the logs to confirm the certificate was issued:**
```sh
docker compose logs -f proxy
```

**5. Test the backend response:**
```sh
curl -k https://your.domain.example.com
```
The `-k` flag is needed while using the Let's Encrypt staging CA.
Staging certificates are not trusted by browsers but are otherwise identical to
production certificates — ideal for testing the full flow without hitting
production rate limits.

## Switching to Production

Once everything is working with staging, edit `.env` and switch the ACME server:

```sh
NGINX_ACME_SERVER=https://acme-v02.api.letsencrypt.org/directory
```

Remove the existing staging certificate data and restart:

```sh
docker compose down
docker volume rm angie-https_angie-acme
docker compose up -d
```

## Configuration

| Variable           | Default                                              | Description                              |
|--------------------|------------------------------------------------------|------------------------------------------|
| `NGINX_SERVER_NAME`| *(required)*                                         | Public hostname for the TLS certificate  |
| `NGINX_ACME_EMAIL` | *(required)*                                         | Contact email for Let's Encrypt account  |
| `NGINX_ACME_SERVER`| Let's Encrypt staging                                | ACME directory URL                       |
| `NGINX_LOG_LEVEL`  | `notice`                                             | Log level (debug, info, notice, warn...) |

## Certificate Persistence

Certificate data is stored in the `angie-acme` Docker named volume and persists
across container restarts and upgrades. Back this volume up if you want to
preserve your certificates.

## Replacing the Backend

The `whoami` backend is for testing only. Replace it in `docker-compose.yml`:

```yaml
  backend:
    image: your-actual-backend-image
    container_name: nrpc-proxy-backend
    networks:
      - proxy-net
```

The proxy forwards all HTTPS traffic to `http://backend:80` on the internal network.
