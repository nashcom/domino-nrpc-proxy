
NGINX_VER=1.29.5

WORK_DIR=$(pwd)
cd software

log_message()
{
  echo
  echo "$@"
  echo
}

log_header()
{
  echo
  echo --------------------------------------------------------------------------------
  echo " $@"
  echo --------------------------------------------------------------------------------
  echo
}



log_header "Downloading NGINX sources $NGINX_VER"

curl -LO http://nginx.org/download/nginx-$NGINX_VER.tar.gz.asc

log_header "Downloading NGINX signature $NGINX_VER"

curl -LO http://nginx.org/download/nginx-$NGINX_VER.tar.gz

log_header "Verifying signature"

gpg --import $WORK_DIR/nginx_pub.asc
gpg --verify nginx-$NGINX_VER.tar.gz.asc nginx-$NGINX_VER.tar.gz

log_header "Signature Status --> $?"

