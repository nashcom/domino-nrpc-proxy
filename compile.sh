#!/bin/sh
############################################################################
# Copyright Nash!Com, Daniel Nashed 2023 - APACHE 2.0 see LICENSE
############################################################################

# For testing: If nginx and module are already present, don't start build
if [ -e /nginx ] && [ -e /ngx_stream_nrpc_preread_module.so ]; then
  echo "NGINX and module already present - No compile required"
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
  local PACKAGE=
  for PACKAGE in $*; do
    install_package $PACKAGE
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

    # Needed by Astra Linux, Ubuntu and Debian. Should be installed before updating Linux but after updating the repo!
    if [ -x /usr/bin/apt-get ]; then
      install_package apt-utils
    fi

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

    header "Cleaning apt cache"
    /sbin/apk cache clean
  fi
}

# --- End Helper functions ---

check_linux_update

if [ -x /sbin/apk ]; then
  # Alpine package names are different
  install_packages tar gzip gcc g++ make curl pcre-dev zlib-dev openssl-dev zlib-devel pcre-devel
else
  install_packages tar gzip gcc make zlib-devel pcre-devel
fi

if [ -z "$NGINX_VER" ]; then
  NGINX_VER=1.23.3
fi

curl -L http://nginx.org/download/nginx-$NGINX_VER.tar.gz | tar xz
cd nginx-$NGINX_VER

./configure --with-stream --add-dynamic-module=.. --with-stream_ssl_preread_module --with-http_ssl_module --with-ipv6 --prefix=/tmp/nginx --sbin-path=/nginx --conf-path=/tmp/nginx/nginx.conf --error-log-path=stderr --pid-path=/tmp/nginx/nginx.pid

# If NGINX is already build, just build module

if [ -e /nginx ]; then
  header "Building module only ..."
  make modules

else
  header "Building NGINX & module. This takes some time  ..."
  make
  cp objs/nginx /
fi

cp objs/ngx_stream_nrpc_preread_module.so /

