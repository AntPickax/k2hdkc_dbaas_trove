k2hr3setup.sh
-------------
This is a tool to build a minimal K2HR3 system for the K2HDKC DBaaS Trove Trial environments(devstack).

## k2hr3setup.sh Overview
The minimal K2HR3 system for the K2HDKC DBaaS Trove Trial environments(devstack) is one in which all functions are implemented on a single Virtual Machine.  
`k2hr3setup.sh` is a tool to create an image for this Virtual Machine.  
The base image for this image is `Ubuntu(Jammy)`.  

This tool registers an image dedicated to the Virtual Machine in OpenStack(Glance), and also sets the access settings(security groups) to the K2HR3 system in OpenStack to use this from the K2HDKC server node of K2HDKC DBaaS Trove.  

Also, start `HAProxy` to directly access this K2HR3 system from the outsied of  K2HDKC DBaaS Trove Trial environments(devstack).  

`k2hr3setup.sh` internally uses tools from the [k2hr3_utils](https://github.com/yahoojapan/k2hr3_utils) repository.  

### Help
If you run `k2hr3setup.sh` with the `--help` option as shown below, it will show you how to use it.  
```
Usage:  k2hr3setup.sh [--no_clear(-nc) | --clear(-c)]
        [--use_parent_auto(-upa) | --use_parent_custom(-upc) <hostname or ip address> | --use_parent_nic(-upn) | --use_parent_name(-upn)]
        [--k2hr3_app_port(-app) <port>] [--k2hr3_app_port_ext(-appext) <port>] [--k2hr3_api_port(-api) <port>] [--k2hr3_api_port_ext(-apiext) <port>]
        [--up_wait_count(-uwc)]
        [--help(-h)]

        --clear(-c)                           Clear all resources about K2HR3 systems in OpenStack before setup(default)
        --no_clear(-nc)                       Not clear all resources about K2HR3 systems in OpenStack before setup
        --use_parent_auto(-upa)               Hotname(IP address) is automatically selected optimally for HAProxy(default)
        --use_parent_custom(-upc) <host>      Specify hostname or IP address for HAProxy
        --use_parent_nic(-upnic)              Force to use default NIC IP address for HAProxy
        --use_parent_name(-upname)            Force to use local hostname(IP address) for HAProxy
        --k2hr3_app_port(-app) <port>         K2HR3 APP port number on Virtual Machine(default: 28080)
        --k2hr3_app_port_ext(-appext) <port>  K2HR3 APP port number on Virtual Machine(default: 28080)
        --k2hr3_api_port(-api) <port>         K2HR3 APP port number on Virtual Machine(default: 18080)
        --k2hr3_api_port_ext(-apiext) <port>  K2HR3 APP port number on Virtual Machine(default: 18080)
        --up_wait_count(-uwc) <count>         Specify the waiting try count (1 time is 10sec) until the instance up, and 0(default) for no upper limit.
        --help(-h)                            print help
```

## k2hr3setup.sh Options
This section explains the options for `k2hr3setup.sh`.

### --help(-h)
Show help for `k2hr3setup.sh`.

### --clear(-c)
Before building a minimal K2HR3 system, clear any related resources(such as security groups) registered in OpenStack.
This option is the default.

### --no_clear(-nc)
Before building a minimal K2HR3 system, do not clear any related resources(such as security groups) registered in OpenStack.

### --use_parent_auto(-upa)
`k2hr3setup.sh` starts `HAProxy` to access the K2HR3 system from outside the host of the K2HDKC DBaaS Trove Trial environments(devstack).  
If you specify this option, it will automatically collect host information on the host where the K2HDKC DBaaS Trove Trial environments(devstack) is started and start `HAProxy`.  
This option is the default.  
This option is exclusive with `--use_parent_custom(-upc)`, `--use_parent_nic(-upnic)`, and `--use_parent_name(-upname)`.

### --use_parent_custom(-upc) <host>
Specify the host name(or IP address) of the host on which the K2HDKC DBaaS Trove Trial environments(devstack) is started directly for the `HAProxy` to be started.  
This option is exclusive with `--use_parent_auto(-upa)`, `--use_parent_nic(-upnic)`, and `--use_parent_name(-upname)`.

### --use_parent_nic(-upnic)
For the `HAProxy` you are starting, specify the default network interface name of the host on which the K2HDKC DBaaS Trove Trial environments(devstack) is started, and specify the host name(or IP address) set for that network interface.  
This option is exclusive with `--use_parent_auto(-upa)`, `--use_parent_custom(-upc)`, and `--use_parent_name(-upname)`.

### --use_parent_name(-upname)
The hostname(or IP address) of the host on which the K2HDKC DBaaS Trove Trial environments(devstack) is started is automatically determined and specified for the `HAProxy` to be started.  
This option is exclusive to `--use_parent_auto(-upa)`, `--use_parent_custom(-upc)`, and `--use_parent_nic(-upnic)`.

### --k2hr3_app_port(-app) <port>
Specify the port number on the Virtual Machine of the launched K2HR3 APP.  
If omitted, `28080` will be used as the default.

### --k2hr3_app_port_ext(-appext) <port>
Specify the port number on the K2HDKC DBaaS Trove Trial environments(devstack) of the launched K2HR3 APP.  
If omitted, `28080` will be used as the default.

### --k2hr3_api_port(-api) <port>
Specify the port number on the Virtual Machine of the started K2HR3 API.  
If omitted, `18080` will be used as the default.

### --k2hr3_api_port_ext(-apiext) <port>
Specify the port number on the K2HDKC DBaaS Trove Trial environments(devstack) of the launched K2HR3 API.  
If omitted, `18080` will be used as the default.

### --up_wait_count(-uwc) <count>
Specifies the number of attempts to start a K2HR3 instance.(One attempt is a 10 second wait.)  
If you specify `0` for this option, it will wait without limit(infinitely).  
If this value is omitted, the default is `0`.

## Environment Variable for k2hr3setup.sh
`k2hr3setup.sh` is affected by the following `PROXY` related environment variables.
- `HTTP_PROXY`(`http_proxy`)
- `HTTPS_PROXY`(`https_proxy`)
- `NO_PROXY`(`no_proxy`）

If the host environment of the Trial environments(devstack) requires a proxy, please set these environment variables appropriately when running `k2hr3setup.sh`.

## Execution example
Below is an example of executing `k2hr3setup.sh`.  

To run it, first `clone` this repository and then switch to the branch you want to use.  
```
$ git clone https://github.com/yahoojapan/k2hdkc_dbaas_trove.git
$ cd k2hdkc_dbaas_trove
$ git checkout stable/2024.1
```

This is an example of starting the K2HR3 system.  
```
$ cd k2hdkc_dbaas_trove/buildutils
$ ./k2hr3setup.sh --clear --use_parent_auto
```
