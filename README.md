# nginx-nrpc-module

This project provides a NRPC proxy stream module providing a dispatcer for NRPC traffic.
It works similar to a TLS/SSL SNI stream module. The first package contains the server name and uses it to map the network connection to the right backend server.

The project provides a container base image build based on the RedHat UBI minimal image.
It compiles the NGINX proxy including the module. This is important because NGINX version and the module must always be based on the same NGINX version.
In addition this build allows to build NGINX in the way needed.


## How to build the image

The build process is a multi stage build. The first build stage builds NGINX and the module.
The second stage uses the minimal configured Redhat UBI image containing the required run-time components only.

To build the image just invoke

```
./build.sh
```

## How to run the image

First review and configure the `.env` container configuration.
To run the image just use the following script.

```
./run.sh
```

## Configure the NGINX configuration

The NGINX configuration is essential for the module.

 
