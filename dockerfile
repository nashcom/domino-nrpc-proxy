ARG BASE_IMAGE=alpine
ARG TARGET=nginx
ARG TARGET_VERSION

# Build stage
FROM $BASE_IMAGE AS build

ARG TARGET
ARG TARGET_VERSION

ENV TARGET=$TARGET
ENV TARGET_VERSION=$TARGET_VERSION

USER root

# Build inputs
COPY current_version.txt compile.sh config ngx_stream_nrpc_preread_module.c nrpc_version.h entrypoint.sh lego_deploy_hook.sh /
COPY cfg /cfg

# Build binary + module
RUN /compile.sh


# Runtime stage
FROM $BASE_IMAGE

ARG TARGET
ARG TARGET_VERSION
ARG BASE_IMAGE
ARG IMAGE_NAME="Domino NRPC Proxy"
ARG NRPC_PROXY_VER
ARG BUILD_DATE
ARG BUILDTIME
ARG LEGO_INSTALL

ENV TARGET=$TARGET

# Copy build artifacts
COPY --from=build /$TARGET /ngx_stream_nrpc_preread_module.so /entrypoint.sh /lego_deploy_hook.sh /
COPY --from=build /cfg /cfg

# Install + permissions
COPY install.sh /
RUN /install.sh && rm -f /install.sh

LABEL maintainer="daniel.nashed@nashcom.de" \
      vendor="Nash!Com" \
      name="$IMAGE_NAME" \
      description="HCL Domino NRPC reverse proxy" \
      summary="HCL Domino NRPC reverse proxy" \
      version="$NRPC_PROXY_VER" \
      base-image="$BASE_IMAGE" \
      target="$TARGET" \
      build-date="$BUILD_DATE" \
      buildtime="$BUILDTIME" \
      release="$BUILDTIME" \
      io.k8s.description="HCL Domino NRPC reverse proxy" \
      io.k8s.display-name="$IMAGE_NAME" \
      io.openshift.expose-services="1352:nrpc" \
      io.openshift.tags="nrpc proxy" \
      io.openshift.min-cpu="1" \
      io.openshift.min-memory="128Mi" \
      io.openshift.non-scalable="false"

EXPOSE 80 443 1352

ENTRYPOINT ["/entrypoint.sh"]

USER 1000
