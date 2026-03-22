#!/bin/bash
############################################################################
# Copyright Nash!Com, Daniel Nashed 2023-2026 - APACHE 2.0 see LICENSE
############################################################################



# --------------------------------------------------------------------------
# Defaults
# --------------------------------------------------------------------------

BASE_IMAGE="alpine"
NGINX_VER="1.29.6"

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

        *)
            echo "Invalid parameter [$arg]"
            exit 1
            ;;

    esac
done


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

header "Building NGINX $NGINX_VER on $BASE_IMAGE ..."

export BUILDKIT_PROGRESS=plain

docker build --no-cache -t domino-nrpc-proxy --build-arg BASE_IMAGE=$BASE_IMAGE --build-arg NGINX_VER=$NGINX_VER .

echo
print_runtime
