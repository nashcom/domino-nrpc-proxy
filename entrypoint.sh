#!/bin/bash

############################################################################
# Copyright Nash!Com, Daniel Nashed 2023-2026 - APACHE 2.0 see LICENSE
##########################################################################

# Ignore errors to not fail the container
set +e

PREFIX="${PREFIX:-DominoProxy}"
METRICS_FILE="${METRICS_FILE:-/tmp/nginx-metrics.prom}"

NGINX_CFG_TEMPLATE_DIR="/run/config/nginx"
NGINX_CERT_DIR="/run/secrets/nginx"

NGINX_CFG_BASE_DIR=/tmp/ngx_cfg
NGINX_CFG_DIR="$NGINX_CFG_BASE_DIR/current"
NGINX_CFG="$NGINX_CFG_DIR/nginx.conf"
NGINX_ENV_VAR_FILE="$NGINX_CFG_BASE_DIR/env_variables.txt"
NGINX_STARTED=

INTERVAL_SECONDS="${INTERVAL_SECONDS:-10}"
CERT_CHECK_INTERVAL="${CERT_CHECK_INTERVAL:-30}"

CONFIG_CURRENT_RELEASE_ID_FILE="$NGINX_CFG_BASE_DIR/current_release_id.txt"
CERTS_LAST_UPDATE_CHECK_FILE="$NGINX_CFG_BASE_DIR/certs_last_update_checked.txt"
CERTS_LAST_UPDATED=
CERTS_UPDATED=
CONFIG_LAST_UPDATED=
CONFIG_UPDATE_COUNT=0
CONFIG_UPDATE_ERRORS=0

CERT_LAST_CHECK_EPOCH=0
CERT_UPDATE_COUNT=0
CERT_UPDATE_ERRORS=0

LINUX_PRETTY_NAME=$(grep PRETTY_NAME= /etc/os-release | cut -d= -f2 | xargs)

log()
{
  printf "%s %s\n" "$(date '+%Y/%m/%d %H:%M:%S')" "$*"
}


log_space()
{
  echo
  log "$@"
  echo
}


log_error()
{
  log "ERROR: $@"
}


log_debug()
{
  if [ -z "$DEBUG_SCRIPT" ] || [ "$DEBUG_SCRIPT" = "0" ]; then
    return 0
  fi

  printf "%s [debug] %s\n" "$(date '+%Y/%m/%d %H:%M:%S')" "$*"
}


delim()
{
  echo "----------------------------------------"
}

delim_long()
{
  echo "------------------------------------------------------------"
}


header()
{
  echo
  delim
  echo "$@"
  delim
  echo
}


dump_file()
{
  if [ -z "$1" ]; then
    return 0
  fi

  header "$1"

  if [ ! -e "$1" ]; then
    log "File does not exist: $1"
    return 0
  fi

  cat $2 "$1"
  echo
}


remove_file()
{
  if [ -z "$1" ]; then
    return 0
  fi

  if [ ! -e "$1" ]; then
    return 0
  fi

 if [ ! -e "$1" ]; then
    echo "Warning: Cannot delete [$1], because it is not a file"
    return 0
  fi

  rm -f "$1" >/dev/null 2>/dev/null || true

  if [ -e "$1" ]; then
    echo "Warning: File not deleted [$1]"
  fi

  return 0
}


copy_file()
{
  if [ -z "$1" ]; then
    return 0
  fi

  if [ ! -e "$1" ]; then
    return 0
  fi

  if [ -z "$2" ]; then
    return 0
  fi

  if [ ! -w "$2" ]; then
    echo "Warning: Cannot copy file $1 -> $2"
    return 0
  fi

  cp -f "$1" "$2" >/dev/null 2>/dev/null || echo "Warning: Cannot copy file $1 -> $2"

  return 0
}


move_file()
{
  if [ -z "$1" ]; then
    return 0
  fi

  if [ ! -e "$1" ]; then
    return 0
  fi

  if [ -z "$2" ]; then
    return 0
  fi

  if [ ! -w "$2" ]; then
    echo "Warning: Cannot move file ($1 -> $2)"
    return 0
  fi

  mv -f "$1" "$2" >/dev/null 2>/dev/null || echo "Warning: Cannot move file ($1 -> $2)"

  return 0
}


nginx_reload()
{
  header "NGINX config reload"
  "$BIN" -s reload -p "$NGINX_CFG_DIR" -c "$NGINX_CFG"
  echo
}


update_cfg()
{
  CONFIG_UPDATED=0
  RELEASE_ID="$(date +%Y%m%d-%H%M%S)"
  CONFIG_RELEASE_DIR="$NGINX_CFG_BASE_DIR/$RELEASE_ID"

  local REL_PATH=
  local DST_FILE=
  local ENV_VARS=
  local ENV_VAR_FILE=

  if [ -f "$NGINX_ENV_VAR_FILE" ]; then
    ENV_VAR_FILE="$NGINX_ENV_VAR_FILE"

  elif [ -f "$NGINX_CFG_TEMPLATE_DIR/env_variables.txt" ]; then
    ENV_VAR_FILE="$NGINX_CFG_TEMPLATE_DIR/env_variables.txt"

  elif [ -f "/nginx_env_variables.txt" ]; then
    ENV_VAR_FILE="/nginx_env_variables.txt"
  fi

  log_debug "ENV_VAR_FILE: $ENV_VAR_FILE"

  if [ -n "$ENV_VAR_FILE" ]; then
    ENV_VARS=$(sed -e '/^#/d' -e '/^$/d' -e 's/^/$/g' "$ENV_VAR_FILE" | xargs)
  fi

  log_debug "ENV_VARS: $ENV_VARS"

  mkdir -p "$CONFIG_RELEASE_DIR"

  if [ -d "$NGINX_CFG_TEMPLATE_DIR" ]; then

    while IFS= read -r -d '' SRC_FILE
    do
      REL_PATH="${SRC_FILE#$NGINX_CFG_TEMPLATE_DIR/}"
      DST_FILE="$CONFIG_RELEASE_DIR/$REL_PATH"

      log_debug "Writing $REL_PATH -> $DST_FILE"

      mkdir -p "$(dirname "$DST_FILE")"

      envsubst "$ENV_VARS" < "$SRC_FILE" > "$DST_FILE"

    done < <(find "$NGINX_CFG_TEMPLATE_DIR" -type f ! -name "*.txt" -print0)
  fi

  CONFIG_LAST_UPDATED="$EPOCH"
  echo "$RELEASE_ID" > "$CONFIG_CURRENT_RELEASE_ID_FILE"

  if "$BIN" -t -p "$CONFIG_RELEASE_DIR" -c "$CONFIG_RELEASE_DIR/nginx.conf"; then
    ln -s "$CONFIG_RELEASE_DIR" "$NGINX_CFG_BASE_DIR/current.new"

    # Atomic promotion: Only replace the symlink, not moving the config tree.
    mv -Tf "$NGINX_CFG_BASE_DIR/current.new" "$NGINX_CFG_DIR"

    log "Configuration ($CONFIG_RELEASE_DIR -> $NGINX_CFG_DIR)"

    CONFIG_UPDATED=1
    CONFIG_STATUS=0
    CONFIG_UPDATE_COUNT=$((CONFIG_UPDATE_COUNT + 1))

  else
    log_error "FAILED to load: $NGINX_CFG"
    dump_file "$CONFIG_RELEASE_DIR/nginx.conf" "-n"
    CONFIG_STATUS=2
    CONFIG_UPDATE_ERRORS=$((CONFIG_UPDATE_ERRORS + 1))
  fi

  cleanup_releases
}


nginx_check_cfg_reload()
{
  CONFIG_UPDATED=0
  update_cfg

  if [ "$CONFIG_UPDATED" != "1" ]; then
    return 0
  fi

  nginx_reload
}


nginx_start()
{
  CONFIG_UPDATED=0

  echo
  echo "$LINUX_PRETTY_NAME"
  delim_long
  echo
  echo "$RUNTIME Server | Mode: ${PROXY_MODE:-custom} | Config: $NGINX_CFG_TEMPLATE_DIR"
  delim_long
  "$BIN" -V 2>&1
  delim_long
  echo

  while true
  do
    update_cfg

    if [ "$CONFIG_UPDATED" = "1" ]; then
      "$BIN" -p "$NGINX_CFG_DIR" -c "$NGINX_CFG"
      return 0
    fi

    if [ -f $NGINX_CFG ]; then
      log_space "Invalid configuration. Trying last good configuration ($NGINX_CFG)"

      "$BIN" -p "$NGINX_CFG_DIR" -c "$NGINX_CFG"
      return 0
    fi

    log_space "Waiting for configuration ($NGINX_CFG)"
    sleep "$INTERVAL_SECONDS"
  done
}


show_cert()
{
  if [ -z "$1" ]; then
    return 0
  fi

  if [ ! -e "$1" ]; then
    return 0
  fi

  local SAN=$(openssl x509 -in "$1" -noout -ext subjectAltName | grep -E 'DNS:|IP Address:' | xargs )
  local SUBJECT=$(openssl x509 -in "$1" -noout -subject | cut -d '=' -f 2- )
  local ISSUER=$(openssl x509 -in "$1" -noout -issuer | cut -d '=' -f 2- )
  local EXPIRATION=$(openssl x509 -in "$1" -noout -enddate | cut -d '=' -f 2- )
  local FINGERPRINT=$(openssl x509 -in "$1" -noout -fingerprint | cut -d '=' -f 2- )
  local SERIAL=$(openssl x509 -in "$1" -noout -serial | cut -d '=' -f 2- )

  echo
  echo "SAN         : $SAN"
  echo "Subject     : $SUBJECT"
  echo "Issuer      : $ISSUER"
  echo "Expiration  : $EXPIRATION"
  echo "Fingerprint : $FINGERPRINT"
  echo "Serial      : $SERIAL"
  echo "File        : $1"
  echo
}


cert_update()
{
  local NEW_PEM="$1"
  local CURRENT_PEM="$2"
  local CURRENT_KEY="$3"
  local CHECK_FINGERPRINT=
  local LAST_FINGERPRINT_ERROR=/tmp/last_fingerprint_error.txt

  if [ -z "$NEW_PEM" ]; then
    log_error "No new PEM specified"
     return 0
  fi

  if [ ! -e "$NEW_PEM" ]; then
    log_error "New PEM does not exist [$NEW_PEM]"
    return 0
  fi

  if [ -z "$CURRENT_PEM" ]; then
    log_error "No curren PEM specified"
    remove_file "$NEW_PEM"
    return 0
  fi

  if [ -z "$CURRENT_KEY" ]; then
    log_error "No new current key specified"
    remove_file "$NEW_PEM"
    return 0
  fi

  # Compare if there is an existing cert, else update in any case
  if [ -e "$CURRENT_PEM" ]; then

    # Get Fingerprints
    local FINGER_PRINT_UPD=$(openssl x509 -in "$NEW_PEM" -noout -fingerprint -sha256 | cut -d '=' -f 2)
    local FINGER_PRINT=$(openssl x509 -in "$CURRENT_PEM" -noout -fingerprint -sha256 | cut -d '=' -f 2)

    if [ "$FINGER_PRINT" = "$FINGER_PRINT_UPD" ]; then
      remove_file "$NEW_PEM"
      return 0
    fi
  fi

  # Get public key hash of updated cert and current key
  local PUB_KEY_HASH=$(openssl x509 -in "$NEW_PEM" -noout -pubkey | openssl sha1 | cut -d ' ' -f 2)
  local PUB_PKEY_HASH=$(openssl pkey -in "$CURRENT_KEY" -pubout | openssl sha1 | cut -d ' ' -f 2)

  # Both keys must be the same when matching certificate for existing key
  if [ "$PUB_KEY_HASH" = "$PUB_PKEY_HASH" ]; then

    echo
    echo "Certificate Update"
    echo "------------------"
    show_cert "$NEW_PEM"

  else

    if [ -e "$LAST_FINGERPRINT_ERROR" ]; then
      CHECK_FINGERPRINT=$(cat "$LAST_FINGERPRINT_ERROR")
    else
      CHECK_FINGERPRINT=
    fi

    if [ "$CHECK_FINGERPRINT" = "$FINGER_PRINT_UPD" ]; then
      log_debug "Key and cert did not match"

    else
      log_error "Certificate does not match key --> Not updating certificate"

      echo "NEW"
      echo "---"
      show_cert "$NEW_PEM"

      echo "OLD"
      echo "---"
      show_cert "$CURRENT_PEM"

      CONFIG_UPDATE_ERRORS=$((CONFIG_UPDATE_ERRORS + 1))
    fi

    remove_file "$NEW_PEM"

    # Remember hash of last cert that did not match
    echo "$FINGER_PRINT_UPD" > "$LAST_FINGERPRINT_ERROR"
    return 0
  fi

  # Update certificate
  log_debug "Copying updated certificate [$NEW_PEM] -> [$CURRENT_PEM]"

  # Better copy it if deleting the original fails
  copy_file "$NEW_PEM" "$CURRENT_PEM"
  remove_file "$NEW_PEM"
  CERTS_UPDATED=1

  return 0
}


check_cert_download()
{
  # Downloads certificate from server (usually a CertMgr server)
  # Returns 0 if updated
  # All other cases return an error

  local SERVER_KEY=$1
  local SERVER_CERT=$2
  local CERTMGR_HOST=$3
  local HOST_NAME=$4
  local CERT_TMP_FILE=$(mktemp /tmp/nginx_cert_update_pem_XXXXXXXXXX)

  if [ -z "$CERTMGR_HOST" ]; then
    return 0
  fi

  if [ ! -e "$SERVER_KEY" ]; then
    log_debug "No key found when checking CertMgr server"
    return 0
  fi

  log_debug "Checking for certificate update on [$CERTMGR_HOST] for [$HOST_NAME]"

  # Just in case remove the template file
  remove_file "$CERT_TMP_FILE"

  # Check for new certificate
  openssl s_client -servername "$HOST_NAME" -showcerts "$CERTMGR_HOST:443" </dev/null 2>/dev/null | sed -ne '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' > "$CERT_TMP_FILE"

  if [ ! "$?" = "0" ]; then
    log_error "Cannot retrieve certificate from CertMgr server [$CERTMGR_HOST]"
    remove_file "$CERT_TMP_FILE"
    return 0
  fi

  if [ ! -s "$CERT_TMP_FILE" ]; then
    log_error "No certificate returned by CertMgr server"
    remove_file "$CERT_TMP_FILE"
    return 0
  fi

  cert_update "$CERT_TMP_FILE" "$SERVER_CERT" "$SERVER_KEY"

  remove_file "$CERT_TMP_FILE"
  return 0
}


get_hostname_from_cert_file()
{
  if [ -z "$1" ]; then
    return 0
  fi

  if [ ! -f "$1" ]; then
    return 0
  fi

  local CERT_NAME=
  local WILDCARD_SAN=
  local SAN=

  while read -r SAN
  do
    SAN=$(echo "$SAN" | xargs)

    case "$SAN" in

      \**)
        [ -z "$WILDCARD_SAN" ] && WILDCARD_SAN="$SAN"
        ;;

      *)
        CERT_NAME="$SAN"
        break
      ;;

    esac

  done < <(openssl x509 -in "$1" -noout -ext subjectAltName | grep 'DNS:' | tr ',' '\n' | cut -d: -f2)

  # Wildcard fallback

  if [ -z "$CERT_NAME" ] && [ -n "$WILDCARD_SAN" ]; then
    CERT_NAME="certmgr.${WILDCARD_SAN#*.}"
  fi

  echo "$CERT_NAME"
}


process_certificate()
{
  local SERVER_CERT="$1"
  local SERVER_KEY="${SERVER_CERT%.*}.key"
  local HOST_NAME=$(get_hostname_from_cert_file "$SERVER_CERT")

  if [ -z "$HOST_NAME" ]; then
    log_space "Warning: No host name returned"
    return 0
  fi

  check_cert_download "$SERVER_KEY" "$SERVER_CERT" "$CERTMGR_HOST" "$HOST_NAME"
}


cert_update_check()
{
  local NOW
  local ELAPSED

  # If no CertMgr server is configured, just check certificate files have been updated
  if [ -z "$CERTMGR_HOST" ]; then
    local FILES_MODIFIED=

    if [ -z "$CERTS_LAST_UPDATED" ]; then
      # No update needed if certs don't need to be copied
      FILES_MODIFIED=

    elif [ -e "$CERTS_LAST_UPDATE_CHECK_FILE" ]; then

      if [ -d "$NGINX_CERT_DIR" ]; then
        FILES_MODIFIED=$(find "$NGINX_CERT_DIR" -type f -newer "$CERTS_LAST_UPDATE_CHECK_FILE")
      fi

    else
      FILES_MODIFIED="FirstTime"
    fi

    if [ -z "$FILES_MODIFIED" ]; then
      return 0
    fi

    CERTS_LAST_UPDATED="$EPOCH"
    echo "$EPOCH" > "$CERTS_LAST_UPDATE_CHECK_FILE"
    log "Certificate/Key update detected in $NGINX_CERT_DIR"

    CERT_UPDATE_COUNT=$((CERT_UPDATE_COUNT + 1))
    nginx_reload

    return 0
  fi

  # If configured invoke CertMgr remote cert update

  NOW=$(date +%s)
  ELAPSED=$((NOW - CERT_LAST_CHECK_EPOCH))

  if [ "$ELAPSED" -lt "$CERT_CHECK_INTERVAL" ]; then
    return 0
  fi

  CERT_LAST_CHECK_EPOCH="$NOW"
  CERTS_UPDATED=

  while IFS= read -r -d '' CERT_FILE
  do
    process_certificate "$CERT_FILE"
  done < <(find "$NGINX_CERT_DIR" -type f -name "*.crt" -print0)

  if [ -z "$CERTS_UPDATED" ]; then
    return 0
  fi

  CERT_UPDATE_COUNT=$((CERT_UPDATE_COUNT + 1))
  nginx_reload
  return 0
}


cleanup_releases()
{
  local KEEP_RELEASES="${CONFIG_KEEP_RELEASES:-3}"
  local CURRENT_RELEASE=
  local RELEASES=
  local RELEASE=
  local COUNT=0

  # Resolve current active release
  if [ -L "$NGINX_CFG_DIR" ]; then
    CURRENT_RELEASE=$(readlink -f "$NGINX_CFG_DIR")
  fi

  # Find all release directories sorted newest first
  RELEASES=$(find "$NGINX_CFG_BASE_DIR" -mindepth 1 -maxdepth 1 -type d | sort -r)

  for RELEASE in $RELEASES
  do
    if [ "$RELEASE" = "$CURRENT_RELEASE" ]; then
      continue
    fi

    COUNT=$((COUNT + 1))

    # Keep newest N inactive releases
    if [ "$COUNT" -le "$KEEP_RELEASES" ]; then
      continue
    fi

    log "Removing old release [$RELEASE]"
    rm -rf "$RELEASE"

  done
}


write_metric()
{
    local NAME="${PREFIX}_${1}"
    local TYPE="$2"
    local HELP="$3"
    local VALUE="$4"
    local LABELS="${5:-}"

    echo "# HELP $NAME $HELP" >> "$TMP_FILE"
    echo "# TYPE $NAME $TYPE" >> "$TMP_FILE"

    if [ -n "$LABELS" ]; then
        echo "$NAME{$LABELS} $VALUE" >> "$TMP_FILE"
    else
        echo "$NAME $VALUE" >> "$TMP_FILE"
    fi
}


write_metrics_file()
{

  # Write metrics file

  local TMP_FILE="$METRICS_FILE.tmp"
  : > "$TMP_FILE"

  write_metric "healthy" "gauge" "Health status" "$HEALTHY"
  write_metric "config_status" "gauge" "NGINX configuration status (0=OK, 1=Warning, 2=Error)" "$CONFIG_STATUS"
  write_metric "config_update_count" "gauge" "Number of configuration updates" "$CONFIG_UPDATE_COUNT"
  write_metric "config_update_errors" "gauge" "Number of configuration update errors" "$CONFIG_UPDATE_ERRORS"
  write_metric "config_last_updated_timestamp" "gauge" "NGINX configuration last updated" "$CONFIG_LAST_UPDATED"

  write_metric "cert_last_updated_timestamp" "gauge" "Certificates last updated" "$CERTS_LAST_UPDATED"
  write_metric "cert_update_count" "gauge" "Number of certificate updates" "$CERT_UPDATE_COUNT"
  write_metric "cert_update_errors" "gauge" "Number of certificate update errors" "$CERT_UPDATE_ERRORS"

  write_metric "stat_update_timestamp" "gauge" "Stats last updated" "$EPOCH"

  mv "$TMP_FILE" "$METRICS_FILE"
}


process_loop()
{
  HEALTHY=1
  local FILES_MODIFIED=
  EPOCH=$(date +%s)

  if [ -z "$CONFIG_LAST_UPDATED" ]; then
    FILES_MODIFIED="FirstTime"

  elif [ -e "$CONFIG_CURRENT_RELEASE_ID_FILE" ]; then
    FILES_MODIFIED=$(find "$NGINX_CFG_TEMPLATE_DIR" -type f -newer "$CONFIG_CURRENT_RELEASE_ID_FILE")

  else
    FILES_MODIFIED="FirstTime"
  fi

  if [ -n "$FILES_MODIFIED" ]; then
    nginx_check_cfg_reload
  fi

  cert_update_check
  write_metrics_file
}


register_var()
{
  if [ -z "$1" ]; then
    return 0
  fi

  export "$1"="$2"
  echo "$1" >> "$NGINX_ENV_VAR_FILE"
}


register_variables()
{

  if [ -z "$NGINX_RESOLVER" ]; then
    NGINX_RESOLVER=$(grep -i '^nameserver' /etc/resolv.conf | head -n1 | cut -d ' ' -f2)
  fi

  if [ -z "$NGINX_MAP_DEFAULT" ]; then
    NGINX_MAP_DEFAULT='$nrpc_preread_server_name'
  fi

  if [ -z "$NGINX_MAP_INET" ]; then
    NGINX_MAP_INET='$nrpc_preread_server_name'
  fi

  if [ -z "$NGINX_SSL_CERT" ]; then
    NGINX_SSL_CERT="$NGINX_CERT_DIR/tls.crt"
  fi

  if [ -z "$NGINX_SSL_KEY" ]; then
    NGINX_SSL_KEY="$NGINX_CERT_DIR/tls.key"
  fi

  : > "$NGINX_ENV_VAR_FILE"

  register_var NGINX_LOG_LEVEL "${NGINX_LOG_LEVEL:-notice}"
  register_var NGINX_ACCESS_LOG "${NGINX_ACCESS_LOG:-off}"
  register_var NGINX_REPLACE_DOTS "${NGINX_REPLACE_DOTS:-off}"
  register_var NGINX_PORT "${NGINX_PORT:-1352}"
  register_var NGINX_HTTP_PORT "${NGINX_HTTP_PORT:-8080}"
  register_var DOMINO_PORT "${DOMINO_PORT:-1352}"
  register_var NGINX_CONNECTIONS "${NGINX_CONNECTIONS:-8000}"
  register_var NGINX_RLIMIT_NOFILE "${NGINX_RLIMIT_NOFILE:-65536}"
  register_var DOMINO_DEFAULT_ORG "${DOMINO_DEFAULT_ORG:-default}"
  register_var NGINX_SERVER_NAME "${NGINX_SERVER_NAME:-_}"
  register_var NGINX_UPSTREAM "${NGINX_UPSTREAM:-127.0.0.1}"
  register_var NGINX_ACME_SERVER "${NGINX_ACME_SERVER:-https://acme-staging-v02.api.letsencrypt.org/directory}"
  register_var NGINX_ACME_EMAIL "${NGINX_ACME_EMAIL:-}"
  register_var NGINX_METRICS_PORT "${NGINX_METRICS_PORT:-9100}"
  register_var NGINX_SSL_CERT "$NGINX_SSL_CERT"
  register_var NGINX_SSL_KEY "$NGINX_SSL_KEY"
  register_var NGINX_RESOLVER "${NGINX_RESOLVER:-127.0.0.1}"
  register_var NGINX_RESOLVER_IPV6 "${NGINX_RESOLVER_IPV6:-ipv6=off}"
  register_var NGINX_MAP_DEFAULT "$NGINX_MAP_DEFAULT"
  register_var NGINX_MAP_INET "$NGINX_MAP_INET"
}


# --- Main ---


# Main entry point for runtime (nginx / angie)

log_debug "--- entrypoint.sh ---"

set -e

# Set more paranoid umask to ensure files can be only read by user
umask 0077

if [ -x /nginx ]; then
  export RUNTIME=nginx
  BIN="/$RUNTIME"
elif [ -x /angie ]; then
  export RUNTIME=angie
  BIN="/$RUNTIME"
else
  export RUNTIME=nginx
  BIN=nginx
fi

if [ -z "$RUNTIME" ]; then
  log_space "Invalid runtime! Must be NGINX or Angie"
  exit 1
fi

WORKDIR="/var/$RUNTIME"
TMPDIR="/tmp/$RUNTIME"

# Use mounted config if present, otherwise select template via PROXY_MODE

if [ -f "$NGINX_CFG_TEMPLATE_DIR/nginx.conf" ]; then
  log_debug "Configuration: $NGINX_CFG_TEMPLATE_DIR/nginx.conf"

else
  PROXY_MODE=${PROXY_MODE:-nrpc}
  NGINX_CFG_TEMPLATE_DIR="/cfg/${RUNTIME}_${PROXY_MODE}"

  log_debug "Configuration: $NGINX_CFG_TEMPLATE_DIR"

  if [ ! -f "$NGINX_CFG_TEMPLATE_DIR/nginx.conf" ]; then
    echo
    echo "Invalid PROXY_MODE [$PROXY_MODE] - No template found in: $NGINX_CFG_TEMPLATE_DIR"
    echo "Valid modes: nrpc, stream, https"
    echo
    exit 1
  fi
fi


mkdir -p "$NGINX_CFG_BASE_DIR"

register_variables

EPOCH=$(date +%s)
nginx_start || true
process_loop || true

echo
header "Configuration"

echo "Domino CertMgr        :  $CERTMGR_HOST"
echo "Interval (sec)        :  $INTERVAL_SECONDS"
echo "Cert Check Interval   :  $CERT_CHECK_INTERVAL"
echo "Config Directory      :  $NGINX_CFG_TEMPLATE_DIR"
echo "Certificate Directory :  $NGINX_CERT_DIR"
echo

dump_file "$NGINX_CFG"

RUNNING=1
trap 'RUNNING=0' TERM INT

while [ "$RUNNING" -eq 1 ]
do
  sleep "$INTERVAL_SECONDS" || break
  process_loop || true
done

stop_nginx

echo "Entrypoint terminated"

