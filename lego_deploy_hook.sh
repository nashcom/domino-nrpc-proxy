#!/bin/bash

############################################################################
# Copyright Nash!Com, Daniel Nashed 2026 - APACHE 2.0 see LICENSE
############################################################################


secure_tls_deploy()
{
  local cert="$1"
  local key="$2"

  chmod 644 "$cert"
  chmod 600 "$key"

  if [ "$(id -u)" = "0" ]; then
    chown "$NGINX_UID:$NGINX_GID" "$cert" "$key"
  else
    echo "[lego_cert] not running as root - cannot chown to $NGINX_UID:$NGINX_GID."
    echo "[lego_cert] making $(basename "$key") group/world-readable so UID $NGINX_UID can read it."
    chmod 644 "$key"
  fi
}


lego_deploy_hook()
{
  echo "[lego_cert] DEPLOY: certificate issued, deploying"

  local DEPLOY_DIR="${DEPLOY_DIR:-/run/secrets/nginx}"
  local CERT_NAME="${LEGO_CERT_NAME:-nginx}"

  mkdir -p "$DEPLOY_DIR"

  cp "$LEGO_PATH/certificates/${CERT_NAME}.crt" "$DEPLOY_DIR/tls.crt"
  cp "$LEGO_PATH/certificates/${CERT_NAME}.key" "$DEPLOY_DIR/tls.key"

  secure_tls_deploy "$DEPLOY_DIR/tls.crt" "$DEPLOY_DIR/tls.key"

  # Reload the nginx serving this certificate to pick up the new files.
  if pgrep -x nginx > /dev/null 2>&1; then
    nginx -s reload
    echo "[lego_cert] DEPLOY: nginx reloaded"
  else
    echo "[lego_cert] DEPLOY: nginx not running, skipped reload"
  fi
}

