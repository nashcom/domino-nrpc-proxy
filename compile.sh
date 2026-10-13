#!/bin/sh
############################################################################
# Copyright Nash!Com, Daniel Nashed 2023-2026 - APACHE 2.0 see LICENSE
############################################################################

set -e

export TARGET=${TARGET:-nginx}

. /current_version.txt

if [ "$TARGET" = "nginx" ]; then
  export TARGET_VERSION=${TARGET_VERSION:-$NGINX_VER}
else
  export TARGET_VERSION=${TARGET_VERSION:-$ANGIE_VER}
fi

# For testing: If binary and module are already present, skip build
if [ -e "/$TARGET" ] && [ -e /ngx_stream_nrpc_preread_module.so ] && { [ "$GEOIP_INSTALL" = "no" ] || { [ -e /ngx_http_geoip2_module.so ] && [ -e /ngx_stream_geoip2_module.so ]; }; }; then
  echo "$TARGET and module already present - No compile required"
  exit 0
fi

# --- Begin Helper functions ---

print_delim()
{
  echo "--------------------------------------------------------------------------------"
}

header()
{
  echo
  print_delim
  echo "$@"
  print_delim
  echo
}

log()
{
  echo
  echo "$@"
  echo
}

install_package()
{
  if [ -x /usr/bin/zypper ]; then
    /usr/bin/zypper install -y "$@"

  elif [ -x /usr/bin/dnf ]; then
    /usr/bin/dnf install -y "$@"

  elif [ -x /usr/bin/tdnf ]; then
    /usr/bin/tdnf install -y "$@"

  elif [ -x /usr/bin/microdnf ]; then
    /usr/bin/microdnf install -y "$@"

  elif [ -x /usr/bin/yum ]; then
    /usr/bin/yum install -y "$@"

  elif [ -x /usr/bin/apt-get ]; then
    /usr/bin/apt-get install -y "$@"

  elif [ -x /sbin/apk ]; then
    /sbin/apk add "$@"

  else
    echo "No package manager found!"
    exit 1
  fi
}

install_packages()
{
  for PACKAGE in "$@"; do
    install_package "$PACKAGE"
  done
}

check_linux_update()
{
  if [ -x /usr/bin/zypper ]; then
    header "Updating Linux via zypper"
    /usr/bin/zypper refresh
    /usr/bin/zypper update -y

  elif [ -x /usr/bin/dnf ]; then
    header "Updating Linux via dnf"
    /usr/bin/dnf update -y

  elif [ -x /usr/bin/tdnf ]; then
    header "Updating Linux via tdnf"
    /usr/bin/tdnf update -y

  elif [ -x /usr/bin/microdnf ]; then
    header "Updating Linux via microdnf"
    /usr/bin/microdnf update -y

  elif [ -x /usr/bin/yum ]; then
    header "Updating Linux via yum"
    /usr/bin/yum update -y

  elif [ -x /sbin/apk ]; then
    header "Updating Linux via apk"
    /sbin/apk update

  elif [ -x /usr/bin/apt-get ]; then
    header "Updating Linux via apt"
    echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections
    /usr/bin/apt-get update -y
    install_package apt-utils
    /usr/bin/apt-get upgrade -y
  fi
}

clean_linux_repo_cache()
{
  if [ -x /usr/bin/zypper ]; then
    header "Cleaning zypper cache"
    /usr/bin/zypper clean --all >/dev/null
    rm -fr /var/cache

  elif [ -x /usr/bin/dnf ]; then
    header "Cleaning dnf cache"
    /usr/bin/dnf clean all >/dev/null

  elif [ -x /usr/bin/tdnf ]; then
    header "Cleaning tdnf cache"
    /usr/bin/tdnf clean all >/dev/null

  elif [ -x /usr/bin/microdnf ]; then
    header "Cleaning microdnf cache"
    /usr/bin/microdnf clean all >/dev/null

  elif [ -x /usr/bin/yum ]; then
    header "Cleaning yum cache"
    /usr/bin/yum clean all >/dev/null
    rm -fr /var/cache/yum

  elif [ -x /usr/bin/apt-get ]; then
    header "Cleaning apt cache"
    /usr/bin/apt-get clean

  elif [ -x /sbin/apk ]; then
    header "Cleaning apk cache"
    /sbin/apk cache clean
  fi
}

# --- End Helper functions ---

check_linux_update

. /etc/os-release

case "$ID" in
  wolfi|alpine)
    install_packages gzip build-base curl pcre-dev zlib-dev openssl-dev git
    GEOIP_DEV_PACKAGE=libmaxminddb-dev
    ;;
  *)
    install_packages tar gzip gcc make zlib-devel pcre2-devel openssl-devel curl git
    GEOIP_DEV_PACKAGE=libmaxminddb-devel
    ;;
esac

# GeoIP2 modules are optional (build.sh -no-geoip)
if [ "$GEOIP_INSTALL" = "no" ]; then
  GEOIP_CONFIGURE=
else
  install_package "$GEOIP_DEV_PACKAGE"
  GEOIP_CONFIGURE="--add-dynamic-module=/ngx_http_geoip2_module"
fi

# Generate version header
echo "#define NRPC_MODULE_VERSION \"$NRPC_PROXY_VER\"" > /nrpc_version.h

# --------------------------------------------------------------------------
# Build functions
# --------------------------------------------------------------------------

# GeoIP2 HTTP + stream modules (https://github.com/leev/ngx_http_geoip2_module)
# Set GEOIP2_MODULE_VER to a tag to pin a version. Default is the current default branch.
fetch_geoip2()
{
  [ "$GEOIP_INSTALL" = "no" ] && return 0

  header "Fetching ngx_http_geoip2_module"
  git clone --depth 1 ${GEOIP2_MODULE_VER:+--branch "$GEOIP2_MODULE_VER"} https://github.com/leev/ngx_http_geoip2_module.git /ngx_http_geoip2_module
}

build_nginx()
{
  header "Building NGINX $TARGET_VERSION"

  fetch_geoip2

  curl -L "http://nginx.org/download/nginx-$TARGET_VERSION.tar.gz" | tar xz
  cd "nginx-$TARGET_VERSION"

  ./configure \
    --with-compat \
    --with-stream \
    --add-dynamic-module=.. \
    $GEOIP_CONFIGURE \
    --with-stream_ssl_preread_module \
    --with-stream_ssl_module \
    --with-stream_realip_module \
    --with-http_ssl_module \
    --with-http_v2_module \
    --with-http_v3_module \
    --with-http_realip_module \
    --with-http_auth_request_module \
    --with-http_stub_status_module \
    --with-http_gunzip_module \
    --with-http_gzip_static_module \
    --with-http_sub_module \
    --with-http_slice_module \
    --with-http_secure_link_module \
    --with-threads \
 \
    --prefix=/var/$TARGET \
    --sbin-path=/$TARGET \
    --conf-path=/tmp/$TARGET/$TARGET.conf \
    --error-log-path=stderr \
    --pid-path=/var/$TARGET/$TARGET.pid

  header "Building module"
  make modules
  cp objs/ngx_*_module.so /

  header "Building NGINX binary"
  make
  cp objs/nginx "/$TARGET"
}

build_angie()
{
  header "Building Angie $TARGET_VERSION"

  fetch_geoip2

  git clone https://github.com/webserver-llc/angie.git
  cd angie
  git checkout "Angie-$TARGET_VERSION"

  ./configure \
    --with-compat \
    --with-stream \
    --add-dynamic-module=.. \
    $GEOIP_CONFIGURE \
    --with-stream_ssl_preread_module \
    --with-stream_ssl_module \
    --with-stream_realip_module \
    --with-stream_mqtt_preread_module \
    --with-stream_rdp_preread_module \
    --with-stream_acme_module \
    --with-http_ssl_module \
    --with-http_v2_module \
    --with-http_v3_module \
    --with-http_acme_module \
    --with-http_realip_module \
    --with-http_auth_request_module \
    --with-http_stub_status_module \
    --with-http_gunzip_module \
    --with-http_gzip_static_module \
    --with-http_sub_module \
    --with-http_slice_module \
    --with-http_secure_link_module \
    --with-threads \
    \
    --prefix=/var/$TARGET \
    --sbin-path=/$TARGET \
    --conf-path=/tmp/$TARGET/$TARGET.conf \
    --error-log-path=stderr \
    --pid-path=/var/$TARGET/$TARGET.pid

  header "Building module"
  make modules
  cp objs/ngx_*_module.so /

  header "Building Angie binary"
  make
  cp objs/angie "/$TARGET"
}

# Use up to 4 CPU cores for make
if [[ -z "${MAKEFLAGS:-}" ]]; then
  BUILD_JOBS=$(nproc 2>/dev/null || echo 1)
  (( BUILD_JOBS > 4 )) && BUILD_JOBS=4
  export MAKEFLAGS="-j${BUILD_JOBS}"
  log "Parallel Build Jobs: ${BUILD_JOBS}"
fi

# --------------------------------------------------------------------------
# Dispatch
# --------------------------------------------------------------------------

case "$TARGET" in
  nginx) build_nginx ;;
  angie) build_angie ;;
  *)
    echo "Unsupported TARGET: $TARGET"
    exit 1
    ;;
esac

clean_linux_repo_cache
