Buildutils - K2HDKC DBaaS Trove
-------------------------------
Bulduilts has tools for K2HDKC DBaaS Trove.  
These tools are mainly used to build a trial environment (devstack).  

## Tools
The tools used by users are explained below.

### k2hdkcstack.sh
This is a batch tool to build and delete a trial environment (devstack) for K2HDKC DBaaS Trove.  
You can also use this tool to create Guest OS Virtual Machine images (Guest Agnet) and Docker images required by K2HDKC DBaaS Trove.  
For more information, see [README_k2hdkcstack.md](README_k2hdkcstack.md).

### k2hdkcdockerimage.sh
This tool creates a Docker image for the server node of K2HDKC DBaaS that is started by K2HDKC DBaaS Trove.  
This tool allows you to create a Dockerfile for the Docker image, build the Docker image, and upload it.  
For details, see [README_k2hdkcdockerimage.md](README_k2hdkcdockerimage.md).

### k2hr3setup.sh
This tool builds the [K2HR3](https://k2hr3.antpick.ax/) system required by K2HDKC DBaaS Trove in the trial environment (devstack).  
Normally, it is called from k2hdkcstack.sh, so there is no need to use this tool directly.  
For details, see [README_k2hr3setup.md](README_k2hr3setup.md).

## Other
A brief explanation of other files.  
_You do not need to use these directly._

### make_release_version_file.sh
A utility that generates release version numbers, etc.

### k2hdkctrove.sh
An executable file for the EntryPoint of the Docker image.

### Dockerfile.trove.templ / Dockerfile.backup.templ
A Dockerfile template for creating a Docker image.

### custom_k2hr3_resource.txt / custom_production_api.templ / custom_production_app.templ
These are files required by the [K2HR3](https://k2hr3.antpick.ax/) system built in the trial environment (devstack).

### conf/*.conf, *.vars
This file contains variables that determine the behavior of k2hdkcstack.sh according to the environment in which the trial environment (devstack) is built.

### examples
Utilities and sample programs for K2HDKC DBaaS Trove.
