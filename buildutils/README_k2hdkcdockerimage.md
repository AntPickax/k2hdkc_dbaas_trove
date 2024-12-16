k2hdkcdockerimage.sh
--------------------
This is a tool to create and upload Docker images for K2HDKC DBaaS Trove.

## About nodes in K2HDKC DBaaS Trove
K2HDKC DBaaS Trove runs database nodes in a Guest OS Virtual Machine (Guest Agent) just like OpenStack + Trove.  
Inside each Guest OS Virtual Machine (Guest Agent), a Docker container for the database is started as a Docker container.  
Thus, Docker containers are also started in K2HDKC DBaaS Trove.

### About Docker containers
K2HDKC DBaaS Trove requires the following two types of Docker images.

### k2hdkc-trove
This is the image for the K2HDKC server nodes.  
It is started as a Docker container in one Guest OS Virtual Machine (Guest Agent) and runs as a K2HDKC server node.  
The Docker base image for this image is assumed to be the [k2hdkc Docker image](https://hub.docker.com/r/antpickax/k2hdkc).  
If you want to prepare your own Docker base image, specify it in the options described below.  
However, this Docker base image must contain the same `K2HDKC` executable files as the [k2hdkc Docker image](https://hub.docker.com/r/antpickax/k2hdkc).

### k2hdkc-trove-backup
This is the Docker image that is started when backing up and restoring on the K2HDKC server node.  
This is the Docker container image that is started when backing up and restoring data held by the K2HDKC server node(`k2hdkc-trove` container) that runs in one Guest OS Virtual Machine (Guest Agent).

### Docker Image Types
The Docker images used by K2HDKC DBaaS Trove currently provide two types based on `Ubuntu` and `Alpine Linux`.  
By default, a lightweight Docker image based on `Alpine Linux` is used.

### Docker Image Distribution
The Docker images used by K2HDKC DBaaS Trove are distributed from [DockerHub](https://hub.docker.com/u/antpickax) for `AntPickax`.  
Each Docker image can be found below:
- [k2hdkc-trove](https://hub.docker.com/r/antpickax/k2hdkc-trove)
- [k2hdkc-trove-backup](https://hub.docker.com/r/antpickax/k2hdkc-trove-backup)

## k2hdkcdockerimage.sh Overview
`k2hdkcdockerimage.sh` is a tool that creates and uploads Docker images for K2HDKC DBaaS Trove.

This tool is usually used by developers of K2HDKC DBaaS Trove.

### Help
If you run `k2hdkcdockerimage.sh` with the `--help` option as shown below, it will show you how to use it.  
```
Usage: k2hdkcdockerimage.sh --help(-h)
       k2hdkcdockerimage.sh [cleanup(clean)/cleanup-all | generate_dockerfile(gen) | build_image(build) | upload_image(upload)] <options>

 [Command]
   cleanup(clean), cleanup-all             : Cleanup the working files etc. "cleanup-all" clean all docker images with docker build cache.
   generate_dockerfile(gen)                : Generate Dockerfiles for K2HDKC Trove Container images
   build_image(build)                      : Generate Dockerfiles and Build K2HDKC Trove Container images
   upload_image(upload)                    : Generate Dockerfiles and Build/Upload K2HDKC Trove Container images

 [Options]
   --help(-h)                              : Print usage

   --conf(-c) <confg file prefix>          : Specifies the prefix name for customized configuration files.
                                             The configuration file is "conf/xxxxx.conf" pattern, and specifies
                                             the file name without the ".conf".
                                             The default is null(it means unspecified custom configuration file).

   --base-registry(-br) <domain:port>      : Base K2HDKC Image Docker Registry Server and Port
   --base-repository(-bp) <path>           : Base K2HDKC Image Docker Repository name
   --registry(-r) <domain:port>            : Docker Registry Server and Port for upload(push)ing image
   --repository(-p) <path>                 : Docker Repository name for upload(push)ing image

   --os(-o) <type>                         : Target OS type(Ubunutu, Rocky, Alpine)
   --base-image-version(-b) <version>      : Base image(K2HDKC) version

   --image-version(-i) <version>           : Create image version
   --over-upload(-u)                       : Allow to over upload image(allow to remove same version in repository)
   --set-proxy-env(-e)                     : Set the PROXY environment variable in the Docker image(default: not set)

   --trove-repository-clone(-t)            : Clone the Trove base repository and apply the patch before building.
   --trove-repository-branch(-tb) <branch> : If you need to specify the branch name to clone, specify it.
                                             If omitted this option, "stable/2024.1" will be used as default.

 [Enviroments]
   HTTP_PROXY(http_proxy)                  : Using HTTP Proxy as this value
   HTTPS_PROXY(https_proxy)                : Using HTTPS Proxy as this value
   NO_PROXY(no_proxy)                      : Using No Proxy as this value
```

## k2hdkcdockerimage.sh mode
There are following types of execution modes for `k2hdkcdockerimage.sh`.

### cleanup(clean) mode
Cleans up any working files used during execution.

### cleanup-all mode
Like the `cleanup(clean)` mode, this will clean up the working files used during execution.  
It will also clear the build cache of Docker images held by the local Docker daemon.

### generate_dockerfile(gen) mode
`k2hdkcdockerimage.sh` dynamically generates two `Dockerfile` from the following two template files in the same directory as the executable file when it is executed.
This mode generates these `Dockerfile`:

- Dockerfile.backup.templ  
This is a `Dockerfile` template file for creating the `k2hdkc-trove` image.
- Dockerfile.trove.templ  
This is a `Dockerfile` template file for creating the `k2hdkc-trove-trove` image.

### build_image(build) mode
This mode generates two types of Docker images.  
This mode runs the `generate_dockerfile(gen)` mode in advance and generates the `k2hdkc-trove` and `k2hdkc-trove-trove` images based on the generated `Dockerfile`.

### upload_image(upload) mode
This mode generates two types of Docker images and uploads them to the Docker registry.  
This mode runs the `build_image(build)` mode in advance and uploads the generated `k2hdkc-trove` and `k2hdkc-trove-trove` images to the Docker registry.

## k2hdkcdockerimage.sh Options
This section explains the options for `k2hdkcdockerimage.sh`.

### [Common] --help(-h)
Show help for `k2hdkcdockerimage.sh`.

### [Common] --base-registry(-br) <domain:port> 
Specifies the Docker registry for the Docker base image to create the `k2hdkc-trove` image.  
If omitted, the default is `docker.io`.

### [Common] --base-repository(-bp) <path>
Specifies the Docker repository name of the Docker base image to create the `k2hdkc-trove` image.  
If omitted, the default is `antpickax`.

### [Common] --registry(-r) <domain:port>
Specify the Docker registry to upload the created `k2hdkc-trove` and `k2hdkc-trove-backup` images.  
If omitted, the default is `docker.io`.

### [Common] --repository(-p) <path>
Specify the Docker repository name to upload the created `k2hdkc-trove` and `k2hdkc-trove-backup` images.  
If omitted, the default is `antpickax`.

### [build_image/upload_image mode] --os(-o) <type>
Specify the OS type of the `k2hdkc-trove` and `k2hdkc-trove-backup` images to be created.  
The OS type that can be specified is either `ubuntu` or `alpine`.  
This option cannot be omitted.

### [build_image/upload_image mode] --base-image-version(-b) <version>
Specify the Docker base image version for the `k2hdkc-trove` and `k2hdkc-trove-backup` images to be created.  
This option cannot be omitted.

### [build_image/upload_image mode] --image-version(-i) <version>
Specifies the version of the `k2hdkc-trove` and `k2hdkc-trove-backup` images to be created.  
This option cannot be omitted.

### [upload_image mode] --over-upload(-u)
If an image of the same version exists at the destination where you are uploading a Docker image, that image will be deleted and re-uploaded.  
If the same version exists, the upload will fail if this option is not specified.  
You should specify this option and understand the risks of overwriting a Docker image, and should use this option for development Docker registries and repositories.

### [Common] --set-proxy-env(-e)
When this tool is started, if `PROXY` related environment variables (`HTTP_PROXY(http_proxy)`, `HTTPS_PROXY(https_proxy)`, `NO_PROXY(no_proxy)`) are set, they will be set in the Docker image.  
Normally, the `k2hdkc-trove` and `k2hdkc-trove-trove` images do not communicate with environments outside the OpenStack+Trove and Guest OS Virtual Machine (Guest Agent) in which they were started, so there is no need to specify this option.  
Set this when installing additional packages, etc. during development, etc.

### [build_image/upload_image mode] --trove-repository-clone(-t)
This script is called from `k2hdkcstack.sh` in addition to being started manually.  
In most cases when it is called from `k2hdkcstack.sh`, the `Trove` source code exists under `/opt/stack` (`stack` user home directory) and is used to create the image.  
If you do not have the `Trove` source code and start this script manually, you must extract the `Trove` source code locally and use it.  
If this option is specified, the original `Trove` source code is extracted, patches are applied, and the image is created using it.

### [build_image/upload_image mode] --trove-repository-branch(-tb) <branch>
If you specify the `--trove-repository-clone(-t)` option, you can specify the branch of the `Trove` source code with this option.  
If you specify the `--trove-repository-clone(-t)` option and do not specify this option, the default branch (stable/xxxx.x) will be used.

## Environment Variable for k2hdkcstack.sh
`k2hdkcdockerimage.sh` is affected by the following `PROXY` related environment variables.
- `HTTP_PROXY`(`http_proxy`)
- `HTTPS_PROXY`(`https_proxy`)
- `NO_PROXY`(`no_proxy`）

If the host environment of the trial environment (devstack) requires a proxy, please set these environment variables appropriately when executing `k2hdkcdockerimage.sh`.  
Also, if you want to set these environment variables for the Docker image you are creating, please refer to the description of the `--set-proxy-env(-e)` option.

## Execution example
Below is an example of executing `k2hdkcdockerimage.sh`.

When executing, first `clone` this repository and switch to the branch you want to use.
```
$ git clone https://github.com/yahoojapan/k2hdkc_dbaas_trove.git
$ cd k2hdkc_dbaas_trove
$ git checkout stable/2024.1
```

### cleanup / cleanup-all mode
#### Cleaning up working files
```
$ cd k2hdkc_dbaas_trove/buildutils
$ ./k2hdkcdockerimage.sh cleanup
```

#### Cleaning up working files and build cache
```
$ cd k2hdkc_dbaas_trove/buildutils
$ ./k2hdkcdockerimage.sh cleanup-all
```

### generate_dockerfile mode
Below are some examples depending on the Docker registry/repository:

#### docker.io/antpickax
```
$ cd k2hdkc_dbaas_trove/buildutils
$ ./k2hdkcdockerimage.sh generate_dockerfile -o alpine -b 1.0.14 --image-version 1.0.1
$ ./k2hdkcdockerimage.sh generate_dockerfile -o ubuntu -b 1.0.14 --image-version 1.0.1
```
#### docker.io/<user>
```
$ cd k2hdkc_dbaas_trove/buildutils
$ ./k2hdkcdockerimage.sh generate_dockerfile -o alpine -b 1.0.14 --image-version 1.0.1 --conf dockerhub-private
$ ./k2hdkcdockerimage.sh generate_dockerfile -o ubuntu -b 1.0.14 --image-version 1.0.1 --conf dockerhub-private
```

### build_image(build) mode
Below are some examples depending on the Docker registry/repository:

#### docker.io/antpickax
```
$ cd k2hdkc_dbaas_trove/buildutils
$ ./k2hdkcdockerimage.sh build_image -o alpine -b 1.0.14 --image-version 1.0.1
$ ./k2hdkcdockerimage.sh build_image -o ubuntu -b 1.0.14 --image-version 1.0.1
```
#### docker.io/<user>
```
$ cd k2hdkc_dbaas_trove/buildutils
$ ./k2hdkcdockerimage.sh build_image -o alpine -b 1.0.14 --image-version 1.0.1 --conf dockerhub-private
$ ./k2hdkcdockerimage.sh build_image -o ubuntu -b 1.0.14 --image-version 1.0.1 --conf dockerhub-private
```

### upload_image(upload) mode
Below are some examples depending on the Docker registry/repository:

#### docker.io/antpickax
```
$ cd k2hdkc_dbaas_trove/buildutils
$ ./k2hdkcdockerimage.sh upload_image -o alpine -b 1.0.14 --image-version 1.0.1
$ ./k2hdkcdockerimage.sh upload_image -o ubuntu -b 1.0.14 --image-version 1.0.1
```
#### docker.io/<user>
```
$ cd k2hdkc_dbaas_trove/buildutils
$ ./k2hdkcdockerimage.sh upload_image -o alpine -b 1.0.14 --image-version 1.0.1 --conf dockerhub-private
$ ./k2hdkcdockerimage.sh upload_image -o ubuntu -b 1.0.14 --image-version 1.0.1 --conf dockerhub-private
```
