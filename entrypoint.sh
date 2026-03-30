#!/bin/sh

############################################################################
# Copyright Nash!Com, Daniel Nashed 2023-2026 - APACHE 2.0 see LICENSE
############################################################################

# Main entry point for runtime (nginx / angie)

set -e

# Set more paranoid umask to ensure files can be only read by user
umask 0077

if [ -x /nginx ]; then
  export RUNTIME=nginx
elif [ -x /angie ]; then
  export RUNTIME=angie
else
  echo
  echo "Invalid runtime! Must be NGINX or Angie"
  echo
  exit 1
fi

BIN="/$RUNTIME"
WORKDIR="/var/$RUNTIME"
TMPDIR="/tmp/$RUNTIME"

# Use mounted config if present, otherwise select template via PROXY_MODE
if [ -f "/$RUNTIME.conf" ]; then
  CONF="/$RUNTIME.conf"
else
  PROXY_MODE=${PROXY_MODE:-nrpc}
  CONF="/${RUNTIME}_${PROXY_MODE}_template.conf"
  if [ ! -f "$CONF" ]; then
    echo
    echo "Invalid PROXY_MODE [$PROXY_MODE] - no template found: $CONF"
    echo "Valid modes: nrpc, stream, https"
    echo
    exit 1
  fi
fi

# Create runtime directories
mkdir -p "$WORKDIR"
mkdir -p "$TMPDIR"

# --------------------------------------------------------------------------
# Defaults (external interface stays NGINX_*)
# --------------------------------------------------------------------------

export NGINX_LOG_LEVEL=${NGINX_LOG_LEVEL:-notice}
export NGINX_REPLACE_DOTS=${NGINX_REPLACE_DOTS:-off}
export NGINX_PORT=${NGINX_PORT:-1352}
export NGINX_HTTP_PORT=${NGINX_HTTP_PORT:-8080}
export DOMINO_PORT=${DOMINO_PORT:-1352}
export NGINX_CONNECTIONS=${NGINX_CONNECTIONS:-8000}
export NGINX_RLIMIT_NOFILE=${NGINX_RLIMIT_NOFILE:-65536}
export DOMINO_DEFAULT_ORG=${DOMINO_DEFAULT_ORG:-default}
export NGINX_SERVER_NAME=${NGINX_SERVER_NAME:-}
export NGINX_UPSTREAM=${NGINX_UPSTREAM:-}
export NGINX_ACME_SERVER=${NGINX_ACME_SERVER:-https://acme-staging-v02.api.letsencrypt.org/directory}
export NGINX_ACME_EMAIL=${NGINX_ACME_EMAIL:-}
export NGINX_METRICS_PORT=${NGINX_METRICS_PORT:-9100}
export NGINX_RESOLVER_IPV6=${NGINX_RESOLVER_IPV6:-ipv6=off}

if [ -z "$NGINX_RESOLVER" ]; then
  export NGINX_RESOLVER=$(grep -i '^nameserver' /etc/resolv.conf | head -n1 | cut -d ' ' -f2)
else
  export NGINX_RESOLVER
fi

if [ -z "$NGINX_MAP_DEFAULT" ]; then
  export NGINX_MAP_DEFAULT='$nrpc_preread_server_name'
else
  export NGINX_MAP_DEFAULT
fi

if [ -z "$NGINX_MAP_INET" ]; then
  export NGINX_MAP_INET='$nrpc_preread_server_name'
else
  export NGINX_MAP_INET
fi

# --------------------------------------------------------------------------
# Variables that must remain literal (not substituted)
# --------------------------------------------------------------------------

export name='$name'
export nrpc_preread_domino_server='$nrpc_preread_domino_server'
export nrpc_preread_server_name='$nrpc_preread_server_name'
export nrpc_preread_org_name='$nrpc_preread_org_name'
export name_org='$name_org'

export ssl_preread_server_name='$ssl_preread_server_name'
export upstream_group='$upstream_group'
export first_label='$first_label'

export host='$host'
export remote_addr='$remote_addr'
export proxy_add_x_forwarded_for='$proxy_add_x_forwarded_for'
export request_uri='$request_uri'

export acme_cert_default='$acme_cert_default'
export acme_cert_key_default='$acme_cert_key_default'

# --------------------------------------------------------------------------
# Dump environment
# --------------------------------------------------------------------------

set > "$WORKDIR/env.log"

# --------------------------------------------------------------------------
# Generate runtime configuration
# --------------------------------------------------------------------------

envsubst < "$CONF" > "$TMPDIR/$RUNTIME.conf"

# --------------------------------------------------------------------------
# Debug output
# --------------------------------------------------------------------------

LINUX_PRETTY_NAME=$(grep PRETTY_NAME= /etc/os-release | cut -d= -f2 | xargs)

if [ "$NGINX_LOG_LEVEL" = "debug" ]; then
  echo
  echo Environment
  echo ------------------------------------------------------------
  set
  echo ------------------------------------------------------------
  echo
  echo Configuration
  echo ------------------------------------------------------------
  cat -n "$TMPDIR/$RUNTIME.conf"
  echo ------------------------------------------------------------
  echo
fi

# --------------------------------------------------------------------------
# Startup information
# --------------------------------------------------------------------------

echo
echo "$LINUX_PRETTY_NAME"
echo ------------------------------------------------------------
echo
echo "$RUNTIME Server | Mode: ${PROXY_MODE:-custom} | Config: $CONF"
echo ------------------------------------------------------------
"$BIN" -V
echo ------------------------------------------------------------
echo

# --------------------------------------------------------------------------
# Start runtime
# --------------------------------------------------------------------------

exec "$BIN" -e stderr -c "$TMPDIR/$RUNTIME.conf" -g 'daemon off;'
