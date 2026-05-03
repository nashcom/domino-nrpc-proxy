
. .env

IMAGE_TAG=latest
PROXY_MODE=nrpc

for arg in "$@"; do
  case "$arg" in
    -angie) IMAGE_TAG=angie ;;
    -https) PROXY_MODE=https ;;
    -*) ;;
    *) if [ -z "$NGINX_SERVER_NAME" ]; then
         NGINX_SERVER_NAME="$arg"
       elif [ -z "$NGINX_UPSTREAM" ]; then
         NGINX_UPSTREAM="$arg"
       fi ;;
  esac
done

docker stop $CONTAINER_NAME 2>/dev/null
docker rm   $CONTAINER_NAME 2>/dev/null

docker network create domino-net 2>/dev/null

NGINX_CONF_ARGS=
if [ -n "$NGINX_CONF" ]; then
  NGINX_CONF_ARGS="-v $NGINX_CONF:/$IMAGE_TAG.conf"
fi

if [ "$PROXY_MODE" = "https" ]; then
  PORT_ARGS="-p 80:80 -p 443:443"
  MODE_ARGS="-e PROXY_MODE=https -e NGINX_PORT=443 -e NGINX_SERVER_NAME=$NGINX_SERVER_NAME -e NGINX_UPSTREAM=$NGINX_UPSTREAM -e NGINX_ACME_SERVER=$NGINX_ACME_SERVER -e NGINX_ACME_EMAIL=$NGINX_ACME_EMAIL"
  ACME_ARGS="-v angie-acme:/acme"
else
  PORT_ARGS="-p $CONTAINER_PORT:1352"
  MODE_ARGS="-e PROXY_MODE=$PROXY_MODE"
  ACME_ARGS=
fi

docker run -d --name $CONTAINER_NAME --network domino-net $PORT_ARGS --ulimit nofile=65536:65536 $NGINX_CONF_ARGS $MODE_ARGS $ACME_ARGS -e NGINX_LOG_LEVEL=$NGINX_LOG_LEVEL --hostname $CONTAINER_HOSTNAME $CONTAINER_IMAGE:$IMAGE_TAG

docker logs $CONTAINER_NAME
