#!/bin/sh
############################################################################
# Copyright Nash!Com, Daniel Nashed 2023-2026 - APACHE 2.0 see LICENSE
############################################################################


LEGO_INSTALL_PATH="${LEGO_INSTALL_PATH:-/lego}"

if [ -z "$LEGO_VERSION" ]; then
  LEGO_VERSION="5.2.2"
  LEGO_AMD64_SHA256="018de6d3f2da09630caa2fbbe8c6aa459323ad0ac0a053d0e808268914b38a8b"
  LEGO_ARM64_SHA256="92c9d7d2a6377cdd4702bfaf7e0f61ea167456f1686a3899a12f289fe863c49b"
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

remove_package()
{
  if [ -x /usr/bin/zypper ]; then
    /usr/bin/zypper rm -y "$@"

  elif [ -x /usr/bin/dnf ]; then
    /usr/bin/dnf remove -y "$@"

  elif [ -x /usr/bin/tdnf ]; then
    /usr/bin/tdnf remove -y "$@"

  elif [ -x /usr/bin/microdnf ]; then
    /usr/bin/microdnf remove -y "$@"

  elif [ -x /usr/bin/yum ]; then
    /usr/bin/yum remove -y "$@"

  elif [ -x /usr/bin/apt-get ]; then
    /usr/bin/apt-get remove -y "$@"

  elif [ -x /sbin/apk ]; then
    /sbin/apk del "$@"

 fi
}

remove_packages()
{
  local PACKAGE=
  for PACKAGE in $*; do
    remove_package $PACKAGE
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


create_dir()
{
  mkdir -p "$1"
  chown nginx:nginx "$1"
  chmod 750 "$1"
}


DownloadAndProcess()
{
  local DOWNLOAD_FILE="$1"
  local PROCESS_CMD="$2"
  local EXPECTED_HASH="${3:-}"

  local HASH=$(curl -fsSL "$DOWNLOAD_FILE" | tee >(eval "$PROCESS_CMD" 2>/dev/null) | sha256sum -b | awk '{print $1}')

  if [ -z "$HASH" ]; then
    echo "Download failed: $DOWNLOAD_FILE"
    exit 1
  fi

  if [ -n "$EXPECTED_HASH" ] && [ "$HASH" != "$EXPECTED_HASH" ]; then
    echo "SHA256 mismatch for $DOWNLOAD_FILE"
    echo "Expected: $EXPECTED_HASH"
    echo "Actual:   $HASH"
    exit 1
  fi

  echo "$HASH"
}


InstallLego()
{
  case "$(uname -m)" in
    x86_64|amd64)
      LEGO_ARCH=amd64
      LEGO_SHA256=$LEGO_AMD64_SHA256
      ;;
    aarch64|arm64)
      LEGO_ARCH=arm64
      LEGO_SHA256=$LEGO_ARM64_SHA256
      ;;
    *)
      echo "Unsupported architecture: $(uname -m)" >&2
      exit 1
      ;;
  esac

  local LEGO_URL="https://github.com/go-acme/lego/releases/download/v${LEGO_VERSION}/lego_v${LEGO_VERSION}_linux_${LEGO_ARCH}.tar.gz"
  local LEGO_HASH=$(DownloadAndProcess "$LEGO_URL" "tar -xzO lego > $LEGO_INSTALL_PATH" "$LEGO_SHA256")

  chmod 755 "$LEGO_INSTALL_PATH"

  echo "Installed lego $("$LEGO_INSTALL_PATH" --version 2>/dev/null | head -1) at $LEGO_INSTALL_PATH"
  echo "Archive SHA256: $LEGO_HASH"
}


# --- End Helper functions ---

check_linux_update

if [ -x /sbin/apk ]; then
  # Alpine package names are different
  install_packages gettext findutils shadow pcre bash openssl curl
else
  install_packages hostname gettext bind-utils findutils shadow-utils openssl curl
fi

useradd nginx -U

create_dir /tls
create_dir /var/nginx
create_dir /tmp/nginx
create_dir /tmp/angie
create_dir /var/angie
create_dir /var/angie/acme_client
create_dir /run/secrets/nginx

chown root:nginx /entrypoint.sh
chown root:nginx "/$TARGET"
chown root:nginx /ngx_stream_nrpc_preread_module.so
chown root:nginx /lego_deploy_hook.sh
chown root:nginx -R /run/secrets

chmod 550 /entrypoint.sh
chmod 550 "/$TARGET"
chmod 550 /ngx_stream_nrpc_preread_module.so
chmod 550 /lego_deploy_hook.sh
chmod 770 -R /run/secrets

chown root:nginx /*_template.conf
chmod 440 /*_template.conf

check_linux_update
clean_linux_repo_cache

# --- LEGO ACME support ---

if [ "$LEGO_INSTALL" = "no" ]; then
  echo "Skipping LEGO ACME support installation"
else
  header "Installing LEGO ACME Support"
  InstallLego
fi

