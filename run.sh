
. .env

docker stop $CONTAINER_NAME 
docker rm $CONTAINER_NAME 

docker network create domino-net

docker run -d --name $CONTAINER_NAME --network domino-net -p $CONTAINER_PORT:1352 -v $NGINX_CONF:/nginx.conf --hostname $CONTAINER_HOSTNAME  $CONTAINER_IMAGE

docker logs nrpc
