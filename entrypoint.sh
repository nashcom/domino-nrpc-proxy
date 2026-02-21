#!/bin/sh

############################################################################
# Copyright Nash!Com, Daniel Nashed 2023-2025 - APACHE 2.0 see LICENSE
############################################################################

# This script is the main entry point for the NGINX container.
# The entry point is invoked by the container run-time to start NGINX.

# Set more paranoid umask to ensure files can be only read by user
umask 0077

# Create log directory with owner nginx
mkdir -p /tmp/nginx
chown nginx:nginx /tmp/nginx

if [ -z "$NGINX_LOG_LEVEL" ]; then
  export NGINX_LOG_LEVEL=notice
fi

if [ -z "$NGINX_REPLACE_DOTS" ]; then
  export NGINX_REPLACE_DOTS=off
fi

if [ -z "$NGINX_RESOLVER" ]; then
  export NGINX_RESOLVER=$(cat /etc/resolv.conf |grep -i '^nameserver'|head -n1|cut -d ' ' -f2)
fi

if [ -z "$NGINX_PORT" ]; then
  export NGINX_PORT=1352
fi

if [ -z "$DOMINO_PORT" ]; then
  export DOMINO_PORT=1352
fi

if [ -z "$NGINX_CONNECTIONS" ]; then
  export NGINX_CONNECTIONS=8000
fi

if [ -z "$DOMINO_DEFAULT_ORG" ]; then
  export DOMINO_DEFAULT_ORG=default
fi

if [ -z "$NGINX_MAP_DEFAULT" ]; then
  export NGINX_MAP_DEFAULT='$nrpc_preread_server_name' 
fi

if [ -z "$NGINX_MAP_INET" ]; then
  export NGINX_MAP_INET='$nrpc_preread_server_name'
fi

# Export variables, which need to stay untranslated

export name='$name'
export nrpc_preread_domino_server='$nrpc_preread_domino_server'
export nrpc_preread_server_name='$nrpc_preread_server_name'
export nrpc_preread_org_name='$nrpc_preread_org_name'
export name_org='$name_org'

export ssl_preread_server_name='$ssl_preread_server_name'
export upstream_group='$upstream_group'
export first_label='$first_label'


# Dump environment
set > /tmp/nginx/env.log

# Substistute variables and create configuration
envsubst < /nginx.conf > /tmp/nginx/nginx.conf

LINUX_PRETTY_NAME=$(cat /etc/os-release | grep "PRETTY_NAME="| cut -d= -f2 | xargs)

if [ "$NGINX_LOG_LEVEL" = "debug" ]; then
  echo
  echo Environment
  echo ------------------------------------------------------------
  set 
  echo ------------------------------------------------------------
  echo
  echo Configuration 
  echo ------------------------------------------------------------
  cat -n /tmp/nginx/nginx.conf
  echo ------------------------------------------------------------
  echo
fi

echo
echo $LINUX_PRETTY_NAME
echo ------------------------------------------------------------
echo
echo NGINX Server 
echo ------------------------------------------------------------
/nginx -V
echo ------------------------------------------------------------
echo

/nginx -e stderr -c /tmp/nginx/nginx.conf -g 'daemon off;'

exit 0

