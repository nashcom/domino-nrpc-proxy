
. .env

IMAGE_TAG=latest

for arg in "$@"; do
  case "$arg" in
    -angie) IMAGE_TAG=angie ;;
  esac
done

docker stop $CONTAINER_NAME
docker rm $CONTAINER_NAME

docker network create domino-net

NGINX_CONF_ARGS=
if [ -n "$NGINX_CONF" ]; then
  NGINX_CONF_ARGS="-e NGINX_CONF=/nginx.conf -v $NGINX_CONF:/nginx.conf"
fi

docker run -d --name $CONTAINER_NAME --network domino-net -p $CONTAINER_PORT:1352 --ulimit nofile=65536:65536 $NGINX_CONF_ARGS -e NGINX_LOG_LEVEL=debug --hostname $CONTAINER_HOSTNAME $CONTAINER_IMAGE:$IMAGE_TAG

docker logs $CONTAINER_NAME
