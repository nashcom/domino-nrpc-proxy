#!/bin/bash
############################################################################
# Copyright Nash!Com, Daniel Nashed 2023-2026 - APACHE 2.0 see LICENSE
############################################################################

# Defaults
BASE_IMAGE="alpine"
TARGET=nginx

. ./current_version.txt


usage()
{
   echo
   echo "Build Parameters"
   echo "----------------"
   echo
   echo "-alpine        Use Alpine as the base image (default)"
   echo "-wolfi         Use Chainguard Wolfi image as the base image"
   echo "-nginx=<ver>   Build image with specified NGINX version"
   echo "-angie         Build image with current Angie version"
   echo "-angie=<ver>   Build image with specified Angie version"
   echo "-no-lego       Build image without LEGO ACME support"
   echo
}

for arg in "$@"; do
    case "$arg" in

        -alpine)
            BASE_IMAGE="alpine"
            ;;

        -wolfi)
            BASE_IMAGE="cgr.dev/chainguard/wolfi-base"
            ;;

        -ubi)
            BASE_IMAGE="registry.access.redhat.com/ubi10/ubi-minimal"
            ;;

        -nginx=*)
            NGINX_VER="${arg#-nginx=}"
            ;;

        -angie)
            TARGET=angie
            ;;

        -angie=*)
            TARGET=angie
            ANGIE_VER="${arg#-angie=}"
            ;;

        -no-lego)
            LEGO_INSTALL="no"
            ;;

        -help|-h|-?)
            usage
            exit 0
            ;;

        *)
            echo "Invalid parameter [$arg]"
            exit 1
            ;;

    esac
done

case "$TARGET" in
  nginx)
    TARGET_NAME=NGINX
    TARGET_VERSION=$NGINX_VER
    IMAGE_NAME="Domino NRPC Proxy"
    ;;
  angie)
    TARGET_NAME=Angie
    TARGET_VERSION=$ANGIE_VER
    IMAGE_NAME="Domino NRPC Proxy (Angie)"
    ;;
esac

BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
BUILDTIME=$(date -u +"%d.%m.%Y %H:%M:%S")

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

log_build_env()
(
  # Running in a sub shell because of . /etc/os-release

  header "Host Information"

  local HOST_OS="unknown"
  local HOST_SELINUX="unknown"
  local LIBC_VERSION="unknown"

  if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    HOST_OS="${PRETTY_NAME:-unknown}"
  fi

  if [[ -r /sys/fs/selinux/enforce ]]; then
    if [[ "$(cat /sys/fs/selinux/enforce)" == "1" ]]; then
      HOST_SELINUX="enforcing"
    else
      HOST_SELINUX="permissive"
    fi
  else
    HOST_SELINUX="disabled"
  fi

  if command -v getconf >/dev/null 2>&1; then
    LIBC_VERSION=$(getconf GNU_LIBC_VERSION 2>/dev/null || true)
  fi

  echo "Host OS            : $HOST_OS"
  echo "Host Architecture  : $(uname -m 2>/dev/null)"
  echo "Host Kernel        : $(uname -r 2>/dev/null)"
  echo "Host SELinux       : $HOST_SELINUX"
  echo "Host libc          : $LIBC_VERSION"

  if command -v docker >/dev/null 2>&1; then
    header "Docker Environment"
    echo "Docker Client      : $(docker version --format '{{.Client.Version}}' 2>/dev/null)"
    echo "Docker Server      : $(docker version --format '{{.Server.Version}}' 2>/dev/null)"
    echo "Docker OS          : $(docker info --format '{{.OperatingSystem}}' 2>/dev/null)"
    echo "Docker Arch        : $(docker info --format '{{.Architecture}}' 2>/dev/null)"
    echo "Docker Kernel      : $(docker info --format '{{.KernelVersion}}' 2>/dev/null)"
    echo "Docker Driver      : $(docker info --format '{{.Driver}}' 2>/dev/null)"

    header "Container Information"

    docker run --rm "$BASE_IMAGE" sh -c '
      . /etc/os-release 2>/dev/null || true
      echo "Container OS            : ${PRETTY_NAME:-unknown}"
      echo "Container Architecture  : $(uname -m)"
      echo "Container Kernel        : $(uname -r)"
    '
  fi

  echo
  echo
)

print_runtime()
{
  hours=$((SECONDS / 3600))
  seconds=$((SECONDS % 3600))
  minutes=$((seconds / 60))
  seconds=$((seconds % 60))
  h=""; m=""; s=""
  if [ ! $hours = "1" ] ; then h="s"; fi
  if [ ! $minutes = "1" ] ; then m="s"; fi
  if [ ! $seconds = "1" ] ; then s="s"; fi
  if [ ! $hours = 0 ] ; then echo "Completed in $hours hour$h, $minutes minute$m and $seconds second$s"
  elif [ ! $minutes = 0 ] ; then echo "Completed in $minutes minute$m and $seconds second$s"
  else echo "Completed in $seconds second$s"; fi
  echo
}

log_build_env

header "Building $TARGET_NAME $TARGET_VERSION on $BASE_IMAGE ..."

export BUILDKIT_PROGRESS=plain

case "$TARGET" in
  nginx) IMAGE_TAG=latest ;;
  angie) IMAGE_TAG=angie ;;
esac

docker build --no-cache -t domino-nrpc-proxy:$IMAGE_TAG \
  --build-arg BASE_IMAGE=$BASE_IMAGE \
  --build-arg TARGET=$TARGET \
  --build-arg TARGET_VERSION=$TARGET_VERSION \
  --build-arg IMAGE_NAME="$IMAGE_NAME" \
  --build-arg NRPC_PROXY_VER=$NRPC_PROXY_VER \
  --build-arg BUILD_DATE=$BUILD_DATE \
  --build-arg BUILDTIME="$BUILDTIME" \
  --build-arg LEGO_INSTALL="$LEGO_INSTALL" \
  --label ${TARGET}-version=$TARGET_VERSION \
  .

echo
print_runtime
