IMAGE_NAME=domino-nrpc-proxy.tgz
docker save domino-nrpc-proxy:latest | gzip > $IMAGE_NAME

echo
if [ -e "$IMAGE_NAME" ]; then
  IMAGE_SIZE=$(du -h domino-nrpc-proxy.tgz | cut -f1)
  echo "Image exported ($IMAGE_SIZE)"
else
  echo "Image NOT exported!"
fi
echo
