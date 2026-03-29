ARG BASE_IMAGE=alpine
ARG TARGET=nginx
ARG VERSION

# =========================
# Build stage
# =========================
FROM $BASE_IMAGE AS build

ARG TARGET
ARG VERSION

ENV TARGET=$TARGET
ENV VERSION=$VERSION

USER root

# Build inputs
COPY current_version.txt /
COPY compile.sh /
COPY config /
COPY ngx_stream_nrpc_preread_module.c /
COPY nrpc_version.h /
COPY *_template.conf /
COPY entrypoint.sh /

# Build binary + module
RUN /compile.sh


# =========================
# Runtime stage
# =========================
FROM $BASE_IMAGE

ARG TARGET
ARG VERSION
ARG BASE_IMAGE
ARG IMAGE_NAME="Domino NRPC Proxy"
ARG NRPC_PROXY_VER
ARG BUILD_DATE
ARG BUILDTIME

ENV TARGET=$TARGET

# Copy build artifacts
COPY --from=build /$TARGET /
COPY --from=build /ngx_stream_nrpc_preread_module.so /
COPY --from=build /entrypoint.sh /
COPY --from=build /*_template.conf /

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
