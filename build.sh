#!/bin/bash
############################################################################
# Copyright Nash!Com, Daniel Nashed 2023-2026 - APACHE 2.0 see LICENSE
############################################################################

# Defaults
BASE_IMAGE="alpine"
TARGET=nginx

. ./current_version.txt

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

        *)
            echo "Invalid parameter [$arg]"
            exit 1
            ;;

    esac
done

case "$TARGET" in
  nginx)
    TARGET_NAME=NGINX
    VERSION=$NGINX_VER
    IMAGE_NAME="Domino NRPC Proxy"
    ;;
  angie)
    TARGET_NAME=Angie
    VERSION=$ANGIE_VER
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

header "Building $TARGET_NAME $VERSION on $BASE_IMAGE ..."

export BUILDKIT_PROGRESS=plain

case "$TARGET" in
  nginx) IMAGE_TAG=latest ;;
  angie) IMAGE_TAG=angie ;;
esac

docker build --no-cache -t domino-nrpc-proxy:$IMAGE_TAG \
  --build-arg BASE_IMAGE=$BASE_IMAGE \
  --build-arg TARGET=$TARGET \
  --build-arg VERSION=$VERSION \
  --build-arg IMAGE_NAME="$IMAGE_NAME" \
  --build-arg NRPC_PROXY_VER=$NRPC_PROXY_VER \
  --build-arg BUILD_DATE=$BUILD_DATE \
  --build-arg BUILDTIME="$BUILDTIME" \
  --label ${TARGET}-version=$VERSION \
  .

echo
print_runtime
