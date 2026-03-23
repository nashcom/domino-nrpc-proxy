
# nginx-nrpc-module

## Overview

This project provides an **NGINX stream module for NRPC (Notes Remote Procedure Call)** traffic routing.

It works similarly to **TLS/SSL SNI-based routing**, but instead of TLS metadata, it inspects the **first NRPC packet**, extracts the **Domino server name**, and dynamically routes the connection to the correct backend server.

### Key Characteristics

* NRPC-aware routing (no TLS required)
* Transparent TCP proxying
* No changes required on Domino servers
* Ideal for containerized environments (Docker / Kubernetes)
* Allows to use NRPC port 1352 for multiple Domino servers on the same IP address.

## NRPC Flow (Preread Routing)

```
 ┌──────────────┐
 │   NRPC Client│
 │ (Notes / App)│
 └──────┬───────┘
        │  NRPC (Port 1352)
        │
        ▼
 ┌───────────────────────────────┐
 │           NGINX               │
 │   stream + nrpc_preread       │
 │                               │
 │  1. Read first NRPC packet    │
 │  2. Extract server name       │
 │     CN=mail01 / O=Acme        │
 │                               │
 │  Variables:                   │
 │  - $nrpc_preread_server_name  │
 │  - $nrpc_preread_org_name     │
 └──────────────┬────────────────┘
                │
                │  Mapping logic
                │
                ▼
        ┌───────────────────────┐
        │   NGINX map{}         │
        │                       │
        │ mail01 →              │
        │ mail01.acme.svc       │
        │                       │
        └──────────┬────────────┘
                   │
                   │ proxy_pass
                   │
                   ▼
        ┌────────────────────────┐
        │  Domino Backend Server │
        │  (Resolved via DNS)    │
        └────────────────────────┘
```


## Container Image

The project provides a container base image built on:

* Alpine Linux
* Chainguard Wolfi
* Red Hat UBI Minimal

NGINX and the NRPC module are compiled together.
The main reason is that NGINX modules must always match the exact NGINX version they are built with.


## Build the Image

The build process uses a **multi-stage Docker build**:

1. Build NGINX + NRPC module
2. Copy runtime into a minimal base image

```bash
./build.sh
```


## Run the Container

1. Review and configure the `.env` file
2. Start the container:

```bash
./run.sh
```


# HCL Domino NRPC Container Configuration

The container uses a **template-based configuration approach**.

* Template: `nginx_template.conf`
* Variables are substituted at startup using `envsubst`
* Final configuration: `nginx.conf`

This works with:

* Docker DNS
* Kubernetes service discovery


# Module Configuration

### Enable NRPC preread

```nginx
nrpc_preread on;
```

### Replace dots in server names

```nginx
nrpc_preread_replacedots on;
```

Enables the replacement of dots to underscores.
This is helpful because they would be difficult to be replaced by NGINX mappings


# Variables Provided by the Module

| Variable                   | Description               |
| -------------------------- | ------------------------- |
| `nrpc_preread_server_name` | Domino server CN (CN=...) |
| `nrpc_preread_org_name`    | Organization name (O=...) |

These variables are used to determine the backend server.


# DNS Resolver

```
NGINX_RESOLVER=
```

* Defaults to `/etc/resolv.conf`
* Can be overridden with a custom DNS server


# Domino Target Port

```
DOMINO_PORT=1352
```

Only change if Domino uses a non-standard NRPC port.


# Replace Dots in Server Names

```
NGINX_REPLACE_DOTS=on
```

* Converts `.` → `-`
* Converts spaces → `_`

Useful for:

* Docker container names
* Kubernetes services


# Default Organization

```
DOMINO_DEFAULT_ORG=default
```

Used when no organization is present in the NRPC request.


# Mapping Configuration

## Default Mapping (Non-Internet Names)

```
NGINX_MAP_DEFAULT
```

Examples:

```
NGINX_MAP_DEFAULT=$nrpc_preread_server_name.docker.local
NGINX_MAP_DEFAULT=$nrpc_preread_server_name.$nrpc_preread_org_name.svc.cluster.local
```


## Internet Address Mapping

```
NGINX_MAP_INET
```

Example:

```
NGINX_MAP_INET=$nrpc_preread_server_name.$nrpc_preread_org_name.svc.cluster.local
```


# NGINX Configuration Template

The following configuration is included in the container image and can be overridden if needed.

```nginx
load_module /ngx_stream_nrpc_preread_module.so;

worker_processes auto;
error_log stderr $NGINX_LOG_LEVEL;

pid /tmp/nginx/nginx.pid;

events {
    worker_connections $NGINX_CONNECTIONS;
}

stream {

  resolver $NGINX_RESOLVER valid=60s;

  map $nrpc_preread_org_name $name_org {
    ""        $DOMINO_DEFAULT_ORG;
    default   $nrpc_preread_org_name;
  }

  map $nrpc_preread_server_name $name {
    ~.*\..*$  $NGINX_MAP_INET:$DOMINO_PORT;
    default   $NGINX_MAP_DEFAULT:$DOMINO_PORT;
  }

  server {
    listen       $NGINX_PORT;
    proxy_pass   $name;

    nrpc_preread on;
    nrpc_preread_replacedots $NGINX_REPLACE_DOTS;
  }

}
```


# Logging

Standard NGINX log levels are supported:

| Level  | Description                    |
| ------ | ------------------------------ |
| debug  | Detailed debugging information |
| info   | Informational messages         |
| notice | Normal but notable events      |
| warn   | Unexpected but non-critical    |
| error  | Errors occurred                |
| crit   | Critical conditions            |
| alert  | Immediate action required      |
| emerg  | System unusable                |

---

# Summary

* NRPC-aware routing using NGINX stream module
* Dynamic backend resolution based on Domino server names
* Designed for container and Kubernetes environments
* Lightweight, transparent and with additional security options thru NGINX

