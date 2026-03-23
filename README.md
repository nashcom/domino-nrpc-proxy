# nginx-nrpc-module

This project provides a NRPC proxy stream module to dispatch NRPC traffic.
It works similar to a TLS/SSL SNI stream module. The first package contains the server name and uses it to map the network connection to the right backend server.

The project provides a container base image build based on Alpine, Chainguard Wolfi or RedHat UBI minimal image.
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


# HCL Domino NRPC container configuration

The container uses a template-based approach. By default `nginx_template.conf` is used as the configuration template.
Environment variables defined in the template are substituted at container startup via `envsubst` to generate the final `nginx.conf`.

The container image provides configuration for Docker and Kubernetes and leverages the container name resolution.


# Module configuration

- **nrpc_preread on;**  
  Enables the NGINX module
  
- **nrpc_preread_replacedots on;**  
  Enables the replacement of dots to underscores.
  This is helpful because they would be difficult to be replaced by NGINX mappings
  

# Variables provided by the module

- **nrpc_preread_server_name**  
  CN of the Domino server name requested (CN=)  

- **nrpc_preread_org_name**  
  Organization name (O=) of the server

Both variables are used to map the requesting server name to the back-end server
  


## DNS Resolver

**NGINX_RESOLVER=**

By default server is read from container's /etc/resolve.conf and configured thru the template.
It can be overwritten by a custom name server IP.


## Domino target port (default 1352)

**DOMINO_PORT=1352**

The standard port should only be modified in special cases, when servers use separate local ports.


## Replace dots in CN with '-'.

**NGINX_REPLACE_DOTS=on**

Container names cannot have dots on Docker and Kubernetes.
The option replaces dots to dashes for incoming server names.
This allows to map the Domino CN to the container name/service. 
Blanks are always replaced to underscores. 


## Default organization name to assume if not present

**DOMINO_DEFAULT_ORG=default**

If not organization is found this organzation is assumed for mapping.


# Mapping for server name if not internet address

**NGINX_MAP_DEFAULT**

If no server is found the specified server is set in the NGINX map.
The setting allows to use NGINX defiend variables.

Examples:

```
NGINX_MAP_DEFAULT=$nrpc_preread_server_name.docker.local
NGINX_MAP_DEFAULT=$nrpc_preread_server_name.$nrpc_preread_org_name.svc.cluster.local
```


# Mapping for server name if internet address

In case an internet address is passed by NGINX, this setting defines which DNS name is returned.


Example:

```
NGINX_MAP_INET=$nrpc_preread_server_name.$nrpc_preread_org_name.svc.cluster.local
```


## NGINX configuration 


The following NGINX configuration template part of the container iamge and could be overwritten is an own configuration file.
In normal cases the environment variable configuration should be the  sufficient. 


```
load_module /ngx_stream_nrpc_preread_module.so;

worker_processes auto;
error_log stderr $NGINX_LOG_LEVEL;

pid /tmp/nginx/nginx.pid;

events {
    worker_connections $NGINX_CONNECTIONS;
}

stream {

  resolver $NGINX_RESOLVER valid=60s;

  map $nrpc_preread_org_name $name_org {

    ""        $DOMINO_DEFAULT_ORG;
    default   $nrpc_preread_org_name;
  }

  map $nrpc_preread_server_name $name {

    ~.*\..*$  $NGINX_MAP_INET:$DOMINO_PORT;
    default   $NGINX_MAP_DEFAULT:$DOMINO_PORT;
  }

  server {
    listen       $NGINX_PORT;
    proxy_pass   $name;

    nrpc_preread on;
    nrpc_preread_replacedots $NGINX_REPLACE_DOTS;
  }

}

```


## Log Levels

Log levels are the standard NGINX log levels

| Level  | Description |
|--------|-------------|
| debug  | Useful debugging information to help determine where the problem lies. |
| info   | Informational messages that aren't necessary to read but may be good to know. |
| notice | Something normal happened that is worth noting. |
| warn   | Something unexpected happened, however is not a cause for concern. |
| error  | Something was unsuccessful. |
| crit   | There are problems that need to be critically addressed. |
| alert  | Prompt action is required. |
| emerg  | The system is in an unusable state and requires immediate attention. |

