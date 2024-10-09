#!/bin/bash
############################################################################
# Copyright Nash!Com, Daniel Nashed 2023 - APACHE 2.0 see LICENSE
############################################################################

BASE_IMAGE=registry.access.redhat.com/ubi9/ubi-minimal

export BUILDKIT_PROGRESS=plain

docker build --no-cache -t domino-nrpc-sni --build-arg BASE_IMAGE=$BASE_IMAGE --build-arg NGINX_VER=$NGINX_VER .
