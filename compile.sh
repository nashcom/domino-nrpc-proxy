#!/bin/sh
############################################################################
# Copyright Nash!Com, Daniel Nashed 2023-2026 - APACHE 2.0 see LICENSE
############################################################################

set -e

export TARGET=${TARGET:-nginx}

. /current_version.txt

if [ "$TARGET" = "nginx" ]; then
  export VERSION=${VERSION:-$NGINX_VER}
else
  export VERSION=${VERSION:-$ANGIE_VER}
fi

# For testing: If binary and module are already present, skip build
if [ -e "/$TARGET" ] && [ -e /ngx_stream_nrpc_preread_module.so ]; then
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
  echo "$1"
  print_delim
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
    ;;
  *)
    install_packages tar gzip gcc make zlib-devel pcre2-devel openssl-devel curl git
    ;;
esac

# Generate version header
echo "#define NRPC_MODULE_VERSION \"$NRPC_PROXY_VER\"" > /nrpc_version.h

# --------------------------------------------------------------------------
# Build functions
# --------------------------------------------------------------------------

build_nginx()
{
  header "Building NGINX $VERSION"

  curl -L "http://nginx.org/download/nginx-$VERSION.tar.gz" | tar xz
  cd "nginx-$VERSION"

  ./configure \
    --with-stream \
    --add-dynamic-module=.. \
    --with-stream_ssl_preread_module \
    --with-http_ssl_module \
    --with-ipv6 \
 \
    --prefix=/tmp/$TARGET \
    --sbin-path=/$TARGET \
    --conf-path=/tmp/$TARGET/$TARGET.conf \
    --error-log-path=stderr \
    --pid-path=/tmp/$TARGET/$TARGET.pid

  header "Building module"
  make modules
  cp objs/ngx_stream_nrpc_preread_module.so /

  header "Building NGINX binary"
  make
  cp objs/nginx "/$TARGET"
}

build_angie()
{
  header "Building Angie $VERSION"

  git clone https://github.com/webserver-llc/angie.git
  cd angie
  git checkout "Angie-$VERSION"

  ./configure \
    --with-stream \
    --add-dynamic-module=.. \
    --with-stream_ssl_preread_module \
    --with-stream_mqtt_preread_module \
    --with-stream_rdp_preread_module \
    --with-http_ssl_module \
    --with-http_acme_module \
 \
    --prefix=/tmp/$TARGET \
    --sbin-path=/$TARGET \
    --conf-path=/tmp/$TARGET/$TARGET.conf \
    --error-log-path=stderr \
    --pid-path=/tmp/$TARGET/$TARGET.pid

  header "Building module"
  make modules
  cp objs/ngx_stream_nrpc_preread_module.so /

  header "Building Angie binary"
  make
  cp objs/angie "/$TARGET"
}

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
