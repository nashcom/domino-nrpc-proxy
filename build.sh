#!/bin/bash
############################################################################
# Copyright Nash!Com, Daniel Nashed 2023-2024 - APACHE 2.0 see LICENSE
############################################################################


if [ -z "$BASE_IMAGE" ]; then
  BASE_IMAGE=registry.access.redhat.com/ubi9/ubi-minimal
fi


if [ -z "$NGINX_VER" ]; then
  NGINX_VER=1.27.2
fi

export BUILDKIT_PROGRESS=plain

docker build --no-cache -t domino-nrpc-sni --build-arg BASE_IMAGE=$BASE_IMAGE --build-arg NGINX_VER=$NGINX_VER .
