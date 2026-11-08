#!/bin/sh
############################################################################
# Copyright Nash!Com, Daniel Nashed 2026 - APACHE 2.0 see LICENSE
############################################################################

set -e

export TARGET=${TARGET:-nginx}

. /current_version.txt

if [ "$TARGET" = "nginx" ]; then
  export TARGET_VERSION=${TARGET_VERSION:-$NGINX_VER}
else
  export TARGET_VERSION=${TARGET_VERSION:-$ANGIE_VER}
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
    install_packages gzip build-base binutils file curl git linux-headers pcre2-dev pcre2-static zlib-dev zlib-static openssl-dev openssl-libs-static
    ;;
  *)
    install_packages tar gzip gcc make binutils file zlib-devel zlib-static pcre2-devel pcre2-static openssl-devel openssl-static curl git
    ;;
esac


# Generate version header
echo "#define NRPC_MODULE_VERSION \"$NRPC_PROXY_VER\"" > /nrpc_version.h

# --------------------------------------------------------------------------
# Build functions
# --------------------------------------------------------------------------


build_nginx()
{
  header "Building NGINX $TARGET_VERSION"

  curl -L "http://nginx.org/download/nginx-$TARGET_VERSION.tar.gz" | tar xz
  cd "nginx-$TARGET_VERSION"

  ./configure \
    --with-ld-opt="-static" \
    --with-compat \
    --with-stream \
    --add-module=.. \
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
    --prefix=/tmp/$TARGET \
    --sbin-path=/usr/bin/$TARGET \
    --conf-path=/etc/$TARGET/$TARGET.conf \
    --error-log-path=stderr \
    --http-log-path=/dev/null \
    --pid-path=/tmp/$TARGET/$TARGET.pid

  header "Building NGINX binary"
  make
  strip "objs/${TARGET}"
  cp "objs/${TARGET}" "/${TARGET}"
  cp conf/mime.types /
}


build_angie()
{
  header "Building Angie $TARGET_VERSION"

  git clone https://github.com/webserver-llc/angie.git /angie-src
  cd /angie-src
  git checkout "Angie-$TARGET_VERSION"

  ./configure \
    --with-ld-opt="-static" \
    --with-compat \
    --with-stream \
    --add-module=.. \
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
    --prefix=/tmp/$TARGET \
    --sbin-path=/usr/bin/$TARGET \
    --conf-path=/etc/$TARGET/$TARGET.conf \
    --error-log-path=stderr \
    --http-log-path=/dev/null \
    --pid-path=/tmp/$TARGET/$TARGET.pid

  header "Building Angie binary"
  make
  strip "objs/${TARGET}"
  cp "objs/${TARGET}" "/${TARGET}"
  cp conf/mime.types /
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

