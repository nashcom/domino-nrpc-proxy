#!/bin/bash

############################################################################
# Copyright Nash!Com, Daniel Nashed 2026 - APACHE 2.0 see LICENSE
############################################################################

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


show_cert()
{
  if [ -z "$1" ]; then
    return 0
  fi

  if [ ! -e "$1" ]; then
    return 0
  fi

  header "New Certificate"

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



secure_tls_deploy()
{
  local cert="$1"
  local key="$2"

  chmod 644 "$cert"
  chmod 600 "$key"

  if [ "$(id -u)" = "0" ]; then
    chown "$NGINX_UID:$NGINX_GID" "$cert" "$key"
  fi
}


lego_deploy_hook()
{
  NGINX_CERT_DIR=/tls

  header "Deploying certificate to $NGINX_CERT_DIR"

  local CERT_NAME="${LEGO_CERT_NAME:-nginx}"

  cp "$LEGO_PATH/certificates/${CERT_NAME}.crt" "$NGINX_CERT_DIR/tls.crt"
  cp "$LEGO_PATH/certificates/${CERT_NAME}.key" "$NGINX_CERT_DIR/tls.key"

  secure_tls_deploy "$NGINX_CERT_DIR/tls.crt" "$NGINX_CERT_DIR/tls.key"

  header "LEGO ACME Certificates"
  /lego certificates list
}


lego_deploy_hook
