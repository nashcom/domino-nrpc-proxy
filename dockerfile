
ARG BASE_IMAGE=registry.access.redhat.com/ubi9/ubi-minimal
ARG NGINX_VER=$NGINX_VER
FROM $BASE_IMAGE

ARG NGINX_VER=$NGINX_VER

USER root

COPY compile.sh /  
COPY config /  
COPY ngx_stream_nrpc_preread_module.c /  
COPY nginx_template.conf /
COPY entrypoint.sh /

RUN /compile.sh

FROM $BASE_IMAGE

COPY --from=0 /nginx / 
COPY --from=0 /ngx_stream_nrpc_preread_module.so / 
COPY --from=0 /entrypoint.sh / 
COPY --from=0 /nginx_template.conf /nginx.conf

COPY install.sh /  
RUN /install.sh && \
  rm -f /install

EXPOSE 1352

ENTRYPOINT ["/entrypoint.sh"]

USER 1000
