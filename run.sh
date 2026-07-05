
. .env

IMAGE_TAG=latest

# Default to nrpc mode
PROXY_MODE=nrpc

add_arg()
{
  if [ -z "$1" ]; then
    return 0
  fi

  if [ -z "$NGINX_CONF_ARGS" ]; then
    NGINX_CONF_ARGS="$1"
  else
    NGINX_CONF_ARGS="$NGINX_CONF_ARGS $1"
  fi
}


log()
{
  echo
  echo "$@"
  echo
}


NGINX_CONF_ARGS=

for arg in "$@"; do
  case "$arg" in

    -angie) IMAGE_TAG=angie ;;
    -https) PROXY_MODE=https ;;
    -debug) add_arg "-e DEBUG_SCRIPT=1" ;;
    -noconfig) NO_CONFIG=1 ;;
    -nosecret) NO_SECRET=1 ;;
    -lego) LEGO_OPTIONS="-e LEGO_ACCEPT_TOS=true -e LEGO_SERVER=letsencrypt-staging -p 80:80" ;;
    -entrypoint|-entry) add_arg "-v "$(pwd)/entrypoint.sh:/entrypoint.sh"" ;;
    -certmgr=*) CERTMGR_HOST="$(echo "$arg" | cut -f2 -d= -s)" ;;

    -*)
     echo "Invalid parameter: $arg"
     exit 1
     ;;

    log|logs)
     docker logs $CONTAINER_NAME
     exit 0
     ;;

    *) if [ -z "$NGINX_SERVER_NAME" ]; then
         NGINX_SERVER_NAME="$arg"
       elif [ -z "$NGINX_UPSTREAM" ]; then
         NGINX_UPSTREAM="$arg"
       fi ;;
  esac
done


if [ -z "$NO_CONFIG" ] && [ -d "/run/config/nginx" ]; then
  add_arg " -v /run/config/nginx:/run/config/nginx"
fi


if [ -z "$NO_SECRET" ] && [ -d /run/secrets/nginx ]; then
  add_arg "-v /run/secrets/nginx:/run/secrets/nginx"
fi


add_arg "-e PROXY_MODE=$PROXY_MODE"


if [ -n "$CERTMGR_HOST" ]; then
  add_arg "-e CERTMGR_HOST=$CERTMGR_HOST"
fi


if [ "$PROXY_MODE" = "https" ]; then
  PORT_ARGS="-p 8080:80 -p 8443:443 -p 9101:9100"
  add_arg "-e NGINX_PORT=443 -e NGINX_SERVER_NAME=$NGINX_SERVER_NAME -e NGINX_UPSTREAM=$NGINX_UPSTREAM"


  if [ "$IMAGE_TAG" = "angie" ]; then
    add_arg "-e NGINX_ACME_SERVER=$NGINX_ACME_SERVER -e NGINX_ACME_EMAIL=$NGINX_ACME_EMAIL ACME_ARGS=-v angie-acme:/acme"
  fi

else
  PORT_ARGS="-p $CONTAINER_PORT:1352"
fi

if [ -z "$CONTAINER_HOSTNAME" ]; then
  CONTAINER_HOSTNAME="$(hostname -f)"
fi

log "PROXY_MODE: $PROXY_MODE"
log  "--- NGINX_CONF_ARGS: ---"
echo "$NGINX_CONF_ARGS"
echo

docker stop $CONTAINER_NAME 2>/dev/null
docker rm   $CONTAINER_NAME 2>/dev/null
docker network create domino-net 2>/dev/null

docker volume rm nrpc_run_secrets 2>/dev/null

docker run -d --name $CONTAINER_NAME --network domino-net --ulimit nofile=65536:65536 -v "$(pwd)/cfg:/cfg" -v "$(pwd)/entrypoint.sh:/entrypoint.sh" $PORT_ARGS $NGINX_CONF_ARGS $MODE_ARGS $ACME_ARGS $LEGO_OPTIONS -e NGINX_LOG_LEVEL=$NGINX_LOG_LEVEL --hostname $CONTAINER_HOSTNAME $CONTAINER_IMAGE:$IMAGE_TAG

sleep 4

docker logs $CONTAINER_NAME

