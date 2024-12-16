k2hdkcstack.sh
--------------
This is a bulk tool to create and delete Trial environments(devstack) for K2HDKC DBaaS Trove.

## Trial environments(devstack)
Trial environments(devstack) are environments where you can develop, debug, and test OpenStack(and Trove) products.  
Trial environments(devstack) include products such as Nova, Horizon, Neutron, and Keystone.  
Trial environments(devstack) can be built on a single Linux host.

## k2hdkcstack.sh Overview
`k2hdkcstack.sh` is a tool for building Trial environments(devstack) in bulk.  
When building the environment, you can create a Guest OS Virtual Machine image(Guest Agent) and a Docker image.  
In addition, Trial environments(devstack) built with `k2hdkcstack.sh` can be cleaned up(deleted) with `k2hdkcstack.sh`.  

This environment allows you to build, test, and debug K2HDKC DBaaS Trove.

### About Trial environments(devstack)
Trial environments(devstack) are development environments(tools) provided by OpenStack(and Trove).  
K2HDKC DBaaS Trove executes `k2hdkcstack.sh`(adding variables, files, databases, etc to `trove`) to prepare the environment for building Trial environments(devstack).   
Then, it executes the same procedures and tools internally as OpenStack(and Trove) to build Trial environments(devstack).  

In other words, Trial environments(devstack) of K2HDKC DBaaS Trove and the devstack environments provided by OpenStack(and Trove) are the same.  

The user who executes Trial environments(devstack) is `stack`, and that HOME directory is `/opt/stack`.  
The source files required for Trial environments(devstack) are extracted under the HOME directory(`/opt/stack`).

### Help
If you run `k2hdkcstack.sh` with the `--help` option as shown below, it will show you how to use it.  
```
Usage: k2hdkcstack.sh                 [--help(-h)] [--version(-v)]
       k2hdkcstack.sh clean(c)        [--with-repos(-r)] [--with-package-repos(-pr)]
       k2hdkcstack.sh start(s)        [--with-trove(-t) | --without-trove(-nt)]
                                      [--with-build-image(-i) | --without-build-image(-ni)]
                                      [--with-k2hr3(-k) | --without-k2hr3(-ki)]
                                      [--with-docker-image(-d) | --without-docker-image(-nd)]
                                      [--enable-guest-ipv6(-ipv6)]
                                      [--branch(-b) <branch>]
                                      [--password(-p) <password>]
                                      [--password(-p) <password>]
       k2hdkcstack.sh patch_update(u)
       k2hdkcstack.sh patch_test(t)

 [Parameter]
   clean(c)                       : Cleanup devstack
   start(s)                       : Setup and run devstack
   patch_update(u)                : Update patch files
   patch_test(t)                  : Test patch files

 [Options]
   --help(-h)                     : Print usage.
   --version(-v)                  : Print version.

   --with-repos(-r)               : Remove all repository directories. (default: "not remove repos")
   --with-package-repos(-pr)      : Remove package repositories for devstack and packages. (default: "not remove package repos")

   --with-build-image(-i)         : Start with biulding guest os image(default).
   --without-build-image(-ni)     : Start without biulding guest os image.
   --with-k2hr3(-k)               : Start with creating/launching K2HR3 cluster(default).
   --without-k2hr3(-nk)           : Start without creating/launching K2HR3 cluster.
   --with-docker-image(-d)        : Create and push docker image for K2HDKC.
   --without-docker-image(-nd)    : Not create and push docker image for K2HDKC.(default)

   --enable-guest-ipv6(-ipv6)     : Enable IPv6 on GuestAgent.(default disabled)

   --branch(-b) <branch>          : Repository branch name. (default: "stable/2024.1")
   --password(-p) <password>      : Openstack components password. (default: "password")
   --conf(-c) <confg file prefix> : Specifies the prefix name for customized configuration files.
                                    The configuration file is "conf/xxxxx.conf" pattern, and specifies
                                    the file name without the ".conf".
                                    The default is null(it means unspecified custom configuration file).
```

## Run modes of k2hdkcstack.sh
There are the following execution modes for `k2hdkcstack.sh`.

### clean(c) mode
Clean up(delete) Trial environments(devstack) built by `k2hdkcstack.sh`.

### start(s) mode
This mode builds Trial environments(devstack), creates Guest OS Virtual Machine images (Guest Agent), and creates and uploads Docker images.

### patch_update(u) mode
This is a mode for K2HDKC DBaaS Trove developers, and updates(or creates) files that need to be modified or added to the OpenStack and Trove source code.

### patch_test(t) mode
This is a mode for K2HDKC DBaaS Trove developers, and checks whether patch files for modifying OpenStack and Trove source code and files to be added are applicable.

## Options of k2hdkcstack.sh
The options for `k2hdkcstack.sh` are explained below.

### [Common] --help(-h)
Show help for `k2hdkcstack.sh`.

### [Common] --version(-v)
Display the version of `k2hdkcstack.sh`.

### [clean mode] --with-repos(-r)
This is the base directory for Trial environments(devstack), and deletes all directories for each OpenStack component deployed under the `stack` home directory(`/opt/stack`).

### [clean mode] --with-package-repos(-pr)
Deletes all packages installed in Trial environments(devstack).

### [start mode] --with-build-image(-i)
When building and starting Trial environments(devstack), generates an image for the Ubuntu(Jammy)-based Guest Agent OS and registers it in the trial environments (devstack).  
This option is enabled by default.

### [start mode] --without-build-image(-ni)
When building and starting Trial environments(devstack), do not generate an image for the Guest Agent OS.  
If you already have an image for the Guest Agent OS, you can shorten the time it takes to build Trial environments(devstack) by specifying this option.  
Note that you must manually register the image for the Guest Agent OS.

### [start mode] --with-k2hr3(-k)
After building Trial environments(devstack), build a minimal K2HR3 system in the environment.  
This will also create a Virtual Machine image for the K2HR3 system required for construction and register it in OpenStack.  
This option is enabled by default.

### [start mode] --without-k2hr3(-nk)
Do not build a K2HR3 system in Trial environments(devstack).  
Specify this option if you want to use a K2HR3 system outside of Trial environments(devstack).  
Note that you must manually configure the link with the K2HR3 system.

### [start mode] --with-docker-image(-d)
After constructing Trial environments(devstack), generate a K2HDKC Docker image for K2HDKC DBaaS Trove and upload it to the Docker registry.  
The base OS type of the Docker image and the Docker registry are specified in the configuration file.  
The configuration file is specified with the `--conf(-c)` option.

### [start mode] --without-docker-image(-nd)
After constructing Trial environments(devstack), do not generate a K2HDKC Docker image for K2HDKC DBaaS Trove.  
This option is enabled by default, and it is assumed that an existing Docker registry and image will be used.

### [start mode] --enable-guest-ipv6(-ipv6)
IPv6 is disabled for the Guest Agent OS of the constructed Trial environments(devstack) and the Docker containers started within it.  
This option lifts the restriction on IPv6 and enables IPv6.

### [start mode] --branch(-b) <branch>
Specifies the branch(release version) of OpenStack and Trove used in Trial environments(devstack).  
For example, `stable/2024.1`.

### [start mode] --password(-p) <password>
In Trial environments(devstack), the passphrase for each OpenStack component is the same, and the default is `password`.  
This option specifies this passphrase.

### [start mode] --conf(-c) <confgfile prefix> 
Specifies the configuration file to determine the Docker image and Docker registry of the Docker container launched as K2HDKC DBaaS Trove.  
If this option is not specified, the default value(Docker registry, etc.) will be set.  
The configuration file also sets the Docker image type and Docker registry when the `--with-docker-image(-d)` option is specified.  
There are pairs of `*.conf` and `*.vars` files under the `buildutils/conf` directory, so you should usually specify one of files(`*.conf`).  
If you want to use your own settings, you can create your own `.conf` and `.vars` and specify them.

## Environment Variable for k2hdkcstack.sh
`k2hdkcstack.sh` refers to the following `PROXY` related environment variables.  
- `HTTP_PROXY`(`http_proxy`)
- `HTTPS_PROXY`(`https_proxy`)
- `NO_PROXY`(`no_proxy`）

If the host environment of Trial environments(devstack) requires a proxy environments, please set these environment variables appropriately when running `k2hdkcstack.sh`.

## Execution example
Below is an example of executing `k2hdkcstack.sh`.  

When executing, first `clone` this repository and switch to the branch you want to use.  
```
$ git clone https://github.com/yahoojapan/k2hdkc_dbaas_trove.git
$ cd k2hdkc_dbaas_trove
$ git checkout stable/2024.1
```

### Cleanup Trial environments(devstack)

#### Stop
```
$ cd k2hdkc_dbaas_trove/buildutils
$ ./k2hdkcstack.sh clean
```

#### Stop and Remove repository directories
```
$ cd k2hdkc_dbaas_trove/buildutils
$ ./k2hdkcstack.sh clean --with-repos
```

#### Stop and Remove packages
```
$ cd k2hdkc_dbaas_trove/buildutils
$ ./k2hdkcstack.sh clean --with-package-repos
```

#### Stop and Remove both
```
$ cd k2hdkc_dbaas_trove/buildutils
$ ./k2hdkcstack.sh clean --with-repos --with-package-repos
```
This will allow you to remove most of the directories, packages, etc. related to OpenStack(and Trove) and K2HDKC DBaaS Trove from the host on which you were running Trial environments(devstack).

### Build and Run Trial environments(devstack)
```
$ cd k2hdkc_dbaas_trove/buildutils
$ ./k2hdkcstack.sh start --branch stable/2024.1 --password <your password>
```
Docker image and repository use DockerHub as the Docker registry, and use `k2hdkc-trove` and `k2hdkc-trove-backup` in the `antpickax` repository.  
Note that non-developers does not need to specify the Docker registry (`--conf(-c)` option).

### For developers of this repository
This repository contains patch files and additional files for K2HDKC DBaaS Trove into `trove` and `trove-dashboard` directories.  
This repository developer will modify these patch files and additional files.  
The following explains how to use two modes of this tool to create and update patch files.  

#### List of patch files
The `trove` and `trove-dashboard` directories in this repository contain their respective patch files and additional files.  
There is also a `patch_list` file at the top of each directory.  

The `patch_list` file lists the relative paths of the patch files and additional files.  
After building Trial environments(devstack), developers should list the required file names in this file.  

#### Update patch files
The patch files and additional files will be updated by running the following command.
```
$ cd k2hdkc_dbaas_trove/buildutils
$ ./k2hdkcstack.sh patch_update
```

#### Test patch files
You can check whether the updated patch files and additional files are properly applied to the trove and trove-dashboard repositories by running the following command.
```
$ cd k2hdkc_dbaas_trove/buildutils
$ ./k2hdkcstack.sh patch_test
```
