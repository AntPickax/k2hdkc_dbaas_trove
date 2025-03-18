#!/bin/sh
#
# K2HDKC DBaaS based on Trove
#
# Copyright 2020 Yahoo Japan Corporation
#
# K2HDKC DBaaS is a Database as a Service compatible with Trove which
# is DBaaS for OpenStack.
# Using K2HR3 as backend and incorporating it into Trove to provide
# DBaaS functionality. K2HDKC, K2HR3, CHMPX and K2HASH are components
# provided as AntPickax.
# 
# For the full copyright and license information, please view
# the license file that was distributed with this source code.
#
# AUTHOR:   Takeshi Nakatani
# CREATE:   Mon Sep 14 2020
# REVISION:
#

#
# This script is one tool for building a test execution environment
# for the K2HDKC DBaaS on Trove (k2hdkc dbaas) system.
# This script will automatically build a K2HR3 system on one of the
# running Trove (OpenStack) Virtual Machines.
# The K2HR3 system that is built boots in a specialized state for Trove.
#
#==============================================================
# Common Variables
#==============================================================
export LANG=C

#
# Instead of pipefail(for shells not support "set -o pipefail")
#
PIPEFAILURE_FILE="/tmp/.pipefailure.$(od -An -tu4 -N4 /dev/random | tr -d ' \n')"

SCRIPTNAME=$(basename "${0}")
SCRIPTDIR=$(dirname "${0}")
SCRIPTDIR=$(cd "${SCRIPTDIR}" || exit 1; pwd)
SRCTOPDIR=$(cd "${SCRIPTDIR}/.." || exit 1; pwd)
SCRIPTDIRNAME=$(basename "${SCRIPTDIR}")
SRCTOPDIRNAME=$(basename "${SRCTOPDIR}")

#==============================================================
# Common Variables and Utility functions
#==============================================================
#
# Escape sequence
#
if [ -t 1 ]; then
	# shellcheck disable=SC2034
	CBLD=$(printf '\033[1m')
	CREV=$(printf '\033[7m')
	CRED=$(printf '\033[31m')
	CYEL=$(printf '\033[33m')
	CGRN=$(printf '\033[32m')
	CDEF=$(printf '\033[0m')
else
	# shellcheck disable=SC2034
	CBLD=""
	CREV=""
	CRED=""
	CYEL=""
	CGRN=""
	CDEF=""
fi

#--------------------------------------------------------------
# Message functions
#--------------------------------------------------------------
PRNERR()
{
	echo "    ${CBLD}${CRED}[ERROR]${CDEF} ${CRED}$*${CDEF}"
}

PRNWARN()
{
	echo "    ${CYEL}${CREV}[WARNING]${CDEF} $*"
}

PRNMSG()
{
	echo ""
	echo "${CYEL}${CREV}[MSG]${CDEF} $*"
}

PRNINFO()
{
	echo "    ${CREV}[INFO]${CDEF} $*"
}

PRNTITLE()
{
	echo ""
	echo "${CGRN}---------------------------------------------------------------------${CDEF}"
	echo "${CGRN}${CREV}[TITLE]${CDEF} ${CGRN}$*${CDEF}"
	echo "${CGRN}---------------------------------------------------------------------${CDEF}"
}

PRNSUCCESS()
{
	CURRENT_TIME=$(date '+%Y-%m-%d-%H:%M:%S,%3N')
	echo ""
	echo "${CGRN}[SUCCESS]${CDEF} $* (${CURRENT_TIME})"
}

#----------------------------------------------------------
# Utility Functions
#----------------------------------------------------------
#
# Set OpenStack Environments for trove
#
# [Input]
#	$1	User name
#	$2	Project name
#
# [Output Environments]
#	OS_AUTH_URL
#	OS_PROJECT_NAME
#	OS_USER_DOMAIN_NAME
#	OS_PROJECT_DOMAIN_ID
#	OS_USERNAME
#	OS_REGION_NAME
#	OS_INTERFACE
#	OS_IDENTITY_API_VERSION
#	OS_PASSWORD
#	OS_PROJECT_ID
#
# [Clear Environments]
#	OS_TENANT_ID
#	OS_TENANT_NAME
#
SetOpenStackAuthEnv()
{
	if [ $# -ne 2 ]; then
		PRNERR "Internal error : parameter wrong."
		return 1
	fi
	OS_USERNAME="$1"
	OS_PROJECT_NAME="$2"

	PRNINFO "Setup environments for ${OS_USERNAME} user ${OS_PROJECT_NAME} project to build K2HR3 system."

	#
	# Set static environments
	#
	export OS_USERNAME
	export OS_PROJECT_NAME
	export OS_AUTH_URL="http://${IDENTIRY_HOST}/identity"
	export OS_USER_DOMAIN_NAME="Default"
	export OS_PROJECT_DOMAIN_ID="default"
	export OS_REGION_NAME="RegionOne"
	export OS_INTERFACE=public
	export OS_IDENTITY_API_VERSION=3

	#
	# Clear environments
	#
	unset OS_TENANT_ID
	unset OS_TENANT_NAME

	#
	# Set Password
	#
	if [ -z "${OS_PASSWORD}" ]; then
		LOCAL_CONF_FILE="/opt/stack/devstack/local.conf"
		if [ -f "${LOCAL_CONF_FILE}" ]; then
			OS_PASSWORD=$(grep ADMIN_PASSWORD "${LOCAL_CONF_FILE}" 2>/dev/null | cut -d '=' -f 2 2>/dev/null)
		fi
		if [ -z "${OS_PASSWORD}" ]; then
			printf "\n%s" "* Please input \"${OS_USERNAME}\" user passphrase(no input is displayed) : "
			# shellcheck disable=SC3045
			read -sr OS_PASSWORD_INPUT
			echo ""
			OS_PASSWORD="${OS_PASSWORD_INPUT}"
		else
			PRNINFO "Found ${LOCAL_CONF_FILE} file and it has ADMIN_PASSWORD value, so use it for ${OS_USERNAME} user passphrase."
		fi
	else
		PRNINFO "OS_PASSWORD environment is set, use it for ${OS_USERNAME} user passphrase."
	fi
	export OS_PASSWORD

	#
	# Set Project ID
	#
	unset OS_PROJECT_ID
	OS_PROJECT_ID=$(openstack project list -f value | grep "^.*[[:space:]]${OS_PROJECT_NAME}[[:space:]]*$" | awk '{print $1}')
	if [ -z "${OS_PROJECT_ID}" ]; then
		PRNERR "Could not get project id for \"${OS_PROJECT_NAME}\" project."
		return 1
	fi
	export OS_PROJECT_ID

	return 0
}

#
# Setup Apt configuration file for PROXY
#
# Input:	$1	SSH option(always "StrictHostKeyChecking=no")
#			$2	SSH private key file path
#			$3	SSH User and Host name(ex. "ubuntu@0.0.0.0")
#
# Result:	[0/1]
#
SetupAptConfig()
{
	if [ $# -ne 3 ]; then
		PRNERR "Internal error : parameters are wrong."
		return 1
	fi
	TMP_SSH_OPTION="$1"
	TMP_PRIVATE_KEY_FILE="$2"
	TMP_USER_AND_HOST="$3"

	#
	# Read current PROXY environments
	#
	HTTP_PROXY_VAL=""
	HTTPS_PROXY_VAL=""
	HTTP_PROXY_NOSCHIMA_VAL=""
	HTTPS_PROXY_NOSCHIMA_VAL=""
	NO_PROXY_VAL=""

	if [ -n "${HTTP_PROXY}" ]; then
		HTTP_PROXY_VAL="${HTTP_PROXY}"
	elif [ -n "${http_proxy}" ]; then
		HTTP_PROXY_VAL="${http_proxy}"
	fi
	if [ -n "${HTTPS_PROXY}" ]; then
		HTTPS_PROXY_VAL="${HTTPS_PROXY}"
	elif [ -n "${https_proxy}" ]; then
		HTTPS_PROXY_VAL="${https_proxy}"
	fi
	if [ -n "${NO_PROXY}" ]; then
		NO_PROXY_VAL="${NO_PROXY}"
	elif [ -n "${no_proxy}" ]; then
		NO_PROXY_VAL="${no_proxy}"
	fi
	if [ -z "${HTTP_PROXY}" ] || [ -n "${HTTPS_PROXY}" ]; then
		HTTP_PROXY_VAL="${HTTPS_PROXY_VAL}"
	elif [ -z "${HTTPS_PROXY}" ] || [ -n "${HTTP_PROXY}" ]; then
		HTTPS_PROXY_VAL="${HTTP_PROXY_VAL}"
	fi
	if [ -n "${HTTP_PROXY_VAL}" ]; then
		if echo "${HTTP_PROXY_VAL}" | grep -q -e '^http://' -e '^https://'; then
			HTTP_PROXY_NOSCHIMA_VAL=$(echo "${HTTP_PROXY_VAL}" | sed -e 's#^http[s]*://##g')
		else
			HTTP_PROXY_NOSCHIMA_VAL="${HTTP_PROXY_VAL}"
			HTTP_PROXY_VAL="http://${HTTP_PROXY_NOSCHIMA_VAL}"
		fi
	fi
	if [ -n "${HTTPS_PROXY_VAL}" ]; then
		if echo "${HTTPS_PROXY_VAL}" | grep -q -e '^http://' -e '^https://'; then
			HTTPS_PROXY_NOSCHIMA_VAL=$(echo "${HTTPS_PROXY_VAL}" | sed -e 's#^http[s]*://##g')
		else
			HTTPS_PROXY_NOSCHIMA_VAL="${HTTPS_PROXY_VAL}"
			HTTPS_PROXY_VAL="http://${HTTPS_PROXY_NOSCHIMA_VAL}"
		fi
	fi

	#
	# Check PROXY Environment exist
	#
	if [ -z "${HTTP_PROXY_VAL}" ] && [ -z "${HTTPS_PROXY_VAL}" ]; then
		#
		# Not need to setup apt configuration for PROXY
		#
		PRNINFO "No PROXY environments, so do not need to set ${APT_PROXY_CONF_FILENAME} file."
		return 0
	fi

	#
	# Put 00-aptproxy.conf file
	#
	rm -f "${LOCAL_APT_PROXY_CONF}"
	{
		if [ -n "${HTTP_PROXY_VAL}" ]; then
			echo "Acquire::http::Proxy \"${HTTP_PROXY_VAL}\";"
		fi
		if [ -n "${HTTPS_PROXY_VAL}" ]; then
			echo "Acquire::https::Proxy \"${HTTPS_PROXY_VAL}\";"
		fi
	} > "${LOCAL_APT_PROXY_CONF}"

	#
	# Copy 00-aptproxy.conf file
	#
	if ! scp -o "${TMP_SSH_OPTION}" -i "${TMP_PRIVATE_KEY_FILE}" "${LOCAL_APT_PROXY_CONF}" "${TMP_USER_AND_HOST}:/tmp" >/dev/null 2>&1; then
		PRNERR "Could not copy ${LOCAL_APT_PROXY_CONF} to ${TMP_USER_AND_HOST}:/tmp."
		rm -f "${LOCAL_APT_PROXY_CONF}"
		return 1
	fi
	if ! ssh -o "${TMP_SSH_OPTION}" -i "${TMP_PRIVATE_KEY_FILE}" "${TMP_USER_AND_HOST}" "/bin/sh -c \"sudo cp /tmp/${APT_PROXY_CONF_FILENAME} ${APT_PROXY_CONF}\""; then
		PRNERR "Could not copy ${LOCAL_APT_PROXY_CONF} to ${TMP_USER_AND_HOST}:${APT_PROXY_CONF}."
		rm -f "${LOCAL_APT_PROXY_CONF}"
		return 1
	fi
	rm -f "${LOCAL_APT_PROXY_CONF}"

	PRNINFO "Setup ${TMP_USER_AND_HOST}:${APT_PROXY_CONF} file."

	return 0
}

#
# Setup /etc/systemd/resolved.conf for PROXY
#
# Input:	$1	SSH option(always "StrictHostKeyChecking=no")
#			$2	SSH private key file path
#			$3	SSH User and Host name(ex. "ubuntu@0.0.0.0")
#
# Result:	[0/1]
#
SetupResolvedConfig()
{
	if [ $# -ne 3 ]; then
		PRNERR "Internal error : parameters are wrong."
		return 1
	fi
	TMP_SSH_OPTION="$1"
	TMP_PRIVATE_KEY_FILE="$2"
	TMP_USER_AND_HOST="$3"

	#
	# Get Node host's DNS IP address or hostname in resolv.conf
	#
	HOST_DNS_RESOLV_IPS=$(grep '^[[:space:]]*nameserver' /etc/resolv.conf | awk '{print $2}' | sort | uniq | tr '\n' ' ')
	if [ -z "${HOST_DNS_RESOLV_IPS}" ]; then
		PRNINFO "Not found any DNS resolv IP addresses for devstack host(node), so nothing to set ${RESOLV_CONF_FILE}."
		return 0
	fi

	#
	# Add DNS IPs(names) to /etc/systemd/resolved.conf
	#
	if ! ssh -o "${TMP_SSH_OPTION}" -i "${TMP_PRIVATE_KEY_FILE}" "${TMP_USER_AND_HOST}" "/bin/sh -c \"echo 'DNS=${HOST_DNS_RESOLV_IPS}' | sudo tee -a ${RESOLV_CONF_FILE} >/dev/null\""; then
		PRNERR "Could not add DNS IPs(names) = ${HOST_DNS_RESOLV_IPS} to ${TMP_USER_AND_HOST}:${RESOLV_CONF_FILE}."
		return 1
	fi

	#
	# Restart systemd-resolved.service
	#
	if ! ssh -o "${TMP_SSH_OPTION}" -i "${TMP_PRIVATE_KEY_FILE}" "${TMP_USER_AND_HOST}" "/bin/sh -c \"sudo systemctl restart systemd-resolved.service\""; then
		PRNERR "Could not restart systemd-resolved.service service in ${TMP_USER_AND_HOST}."
		return 1
	fi

	PRNINFO "Setup resolved configration for ${TMP_USER_AND_HOST}."

	return 0
}

#----------------------------------------------------------
# Print usage
#----------------------------------------------------------
func_usage()
{
	#
	# $1:	Program name
	#
	echo ""
	echo "Usage:  $1 [--no_clear(-nc) | --clear(-c)]"
	echo "        [--use_parent_auto(-upa) | --use_parent_custom(-upc) <hostname or ip address> | --use_parent_nic(-upn) | --use_parent_name(-upn)]"
	echo "        [--k2hr3_app_port(-app) <port>] [--k2hr3_app_port_ext(-appext) <port>] [--k2hr3_api_port(-api) <port>] [--k2hr3_api_port_ext(-apiext) <port>]"
	echo "        [--up_wait_count(-uwc)]"
	echo "        [--help(-h)]"
	echo ""
	echo "        --clear(-c)                           Clear all resources about K2HR3 systems in OpenStack before setup(default)"
	echo "        --no_clear(-nc)                       Not clear all resources about K2HR3 systems in OpenStack before setup"
	echo "        --use_parent_auto(-upa)               Hotname(IP address) is automatically selected optimally for HAProxy(default)"
	echo "        --use_parent_custom(-upc) <host>      Specify hostname or IP address for HAProxy"
	echo "        --use_parent_nic(-upnic)              Force to use default NIC IP address for HAProxy"
	echo "        --use_parent_name(-upname)            Force to use local hostname(IP address) for HAProxy"
	echo "        --k2hr3_app_port(-app) <port>         K2HR3 APP port number on Virtual Machine(default: 28080)"
	echo "        --k2hr3_app_port_ext(-appext) <port>  K2HR3 APP port number on Virtual Machine(default: 28080)"
	echo "        --k2hr3_api_port(-api) <port>         K2HR3 APP port number on Virtual Machine(default: 18080)"
	echo "        --k2hr3_api_port_ext(-apiext) <port>  K2HR3 APP port number on Virtual Machine(default: 18080)"
	echo "        --up_wait_count(-uwc) <count>         Specify the waiting try count (1 time is 10sec) until the instance up, and 0(default) for no upper limit."
	echo "        --help(-h)                            print help"
	echo ""
}

#----------------------------------------------------------
# Check current user and Switch stack user
#----------------------------------------------------------
#
# Switch stack user
#
STACK_USER_NAME="stack"
CURRENT_USER_NAME=$(id -u -n)

if [ "${CURRENT_USER_NAME}" != "${STACK_USER_NAME}" ]; then
	if ! id -u -n "${STACK_USER_NAME}" >/dev/null 2>&1; then
		PRNERR "Not found ${STACK_USER_NAME} on this host."
		exit 1
	fi

	PRNMSG "Switch stack user and run ${SCRIPTNAME}"

	if ! /bin/sh -c "sudo -u ${STACK_USER_NAME} -i ${SCRIPTDIR}/${SCRIPTNAME} $*"; then
		PRNERR "Failed to run ${SCRIPTNAME} as stack user."
		exit 1
	fi
	exit 0
fi

PRNTITLE "Start K2HR3 Cluster for K2HDKC DBaaS Trove"

#----------------------------------------------------------
# Check and Create work directory
#----------------------------------------------------------
PRNMSG "Check and Create work directory"

STACK_USER_HOME=$(grep "^${STACK_USER_NAME}" /etc/passwd | awk -F':' '{print $6}' | tr -d '\n')
SRCTOPDIRNAME=$(basename "${SRCTOPDIR}")

if [ ! -d "${STACK_USER_HOME}/${SRCTOPDIRNAME}/${SCRIPTDIRNAME}" ]; then
	if [ ! -d "${STACK_USER_HOME}/${SRCTOPDIRNAME}" ]; then
		PRNINFO "Create ${STACK_USER_HOME}/${SRCTOPDIRNAME} directory."

		if ! mkdir -p "${STACK_USER_HOME}/${SRCTOPDIRNAME}" >/dev/null 2>&1; then
			PRNERR "Failed to create ${STACK_USER_HOME}/${SRCTOPDIRNAME} directory."
			exit 1
		fi
	fi

	PRNINFO "Create(Copy) ${STACK_USER_HOME}/${SRCTOPDIRNAME}/${SCRIPTDIRNAME} directory."

	_TMP_ARCHIVE_FILE="/tmp/${SCRIPTNAME}.$$.tar"
	if ! tar cvf "${_TMP_ARCHIVE_FILE}" -C "${SRCTOPDIR}" "${SCRIPTDIRNAME}" >/dev/null 2>&1; then
		PRNERR "Failed to create archive file(${_TMP_ARCHIVE_FILE}) for ${SRCTOPDIR}/${SCRIPTDIRNAME} directory."
		rm -f "${_TMP_ARCHIVE_FILE}"
		exit 1
	fi
	if ! tar xvf "${_TMP_ARCHIVE_FILE}" -C "${STACK_USER_HOME}/${SRCTOPDIRNAME}" >/dev/null 2>&1; then
		PRNERR "Failed to extract file(/tmp/${_TMP_ARCHIVE_FILE}) into ${STACK_USER_HOME}/${SRCTOPDIRNAME} directory."
		rm -f "${_TMP_ARCHIVE_FILE}"
		exit 1
	fi
	rm -f "${_TMP_ARCHIVE_FILE}"
fi

#
# Change current
#
cd "${STACK_USER_HOME}/${SRCTOPDIRNAME}/${SCRIPTDIRNAME}" || exit 1

CURRENT_DIR=$(pwd)

PRNINFO "Change current directory to work directory."

#----------------------------------------------------------
# Options
#----------------------------------------------------------
#
# Check options
#
PRNMSG "Check option and programs, etc"

OPT_DO_CLEAR=
OPT_UP_WAIT_COUNT=
OPT_APP_PORT=
OPT_APP_PORT_EXT=
OPT_API_PORT=
OPT_API_PORT_EXT=
OPT_PARENT_TYPE=
TYPE_CUSTOM_PARENT_HOSTNAME=
TYPE_CUSTOM_PARENT_IP=

while [ $# -ne 0 ]; do
	if [ -z "$1" ]; then
		break

	elif echo "$1" | grep -q -i -e "^-h$" -e "^--help$"; then
		func_usage "${SCRIPTNAME}"
		exit 0

	elif echo "$1" | grep -q -i -e "^-c$" -e "^--clear$"; then
		if [ -n "${OPT_DO_CLEAR}" ]; then
			PRNERR "Already specified \"--clear\" or \"--no_clear\" options."
			exit 1
		fi
		OPT_DO_CLEAR=1

	elif echo "$1" | grep -q -i -e "^-nc$" -e "^--no_clear$"; then
		if [ -n "${OPT_DO_CLEAR}" ]; then
			PRNERR "Already specified \"--clear\" or \"--no_clear\" options."
			exit 1
		fi
		OPT_DO_CLEAR=0

	elif echo "$1" | grep -q -i -e "^-upa$" -e "^--use_parent_auto$"; then
		if [ -n "${OPT_PARENT_TYPE}" ]; then
			PRNERR "Already specified \"--use_parent_auto\" or \"--use_parent_custom\" or \"--use_parent_nic\" or \"--use_parent_name\" options."
			exit 1
		fi
		OPT_PARENT_TYPE="Auto"

	elif echo "$1" | grep -q -i -e "^-upc$" -e "^--use_parent_custom$"; then
		if [ -n "${OPT_PARENT_TYPE}" ]; then
			PRNERR "Already specified \"--use_parent_auto\" or \"--use_parent_custom\" or \"--use_parent_nic\" or \"--use_parent_name\" options."
			exit 1
		fi
		shift
		if [ -z "$1" ]; then
			PRNERR "\"--use_parent_custom(-upc)\" option needs parameter(hostname or ip address)."
			exit 1
		fi
		OPT_PARENT_TYPE="Custom"
		TYPE_CUSTOM_PARENT_HOSTNAME=
		TYPE_CUSTOM_PARENT_IP="$1"

	elif echo "$1" | grep -q -i -e "^-upnic$" -e "^--use_parent_nic$"; then
		if [ -n "${OPT_PARENT_TYPE}" ]; then
			PRNERR "Already specified \"--use_parent_auto\" or \"--use_parent_custom\" or \"--use_parent_nic\" or \"--use_parent_name\" options."
			exit 1
		fi
		OPT_PARENT_TYPE="Nic"

	elif echo "$1" | grep -q -i -e "^-upname$" -e "^--use_parent_name$"; then
		if [ -n "${OPT_PARENT_TYPE}" ]; then
			PRNERR "Already specified \"--use_parent_auto\" or \"--use_parent_custom\" or \"--use_parent_nic\" or \"--use_parent_name\" options."
			exit 1
		fi
		OPT_PARENT_TYPE="Name"

	elif echo "$1" | grep -q -i -e "^-app$" -e "^--k2hr3_app_port$"; then
		if [ -n "${OPT_APP_PORT}" ]; then
			PRNERR "Already specified \"--k2hr3_app_port(-app)\" option."
			exit 1
		fi
		shift
		if [ -z "$1" ]; then
			PRNERR "\"--k2hr3_app_port(-app)\" option needs parameter(number)."
			exit 1
		fi
		if echo "$1" | grep -q "[^0-9]"; then
			PRNERR "\"--k2hr3_app_port(-app)\" option parameter($1) must be 0 or positive number."
			exit 1
		fi
		OPT_APP_PORT="$1"

	elif echo "$1" | grep -q -i -e "^-appext$" -e "^--k2hr3_app_port_ext$"; then
		if [ -n "${OPT_APP_PORT_EXT}" ]; then
			PRNERR "Already specified \"--k2hr3_app_port_ext(-appext)\" option."
			exit 1
		fi
		shift
		if [ -z "$1" ]; then
			PRNERR "\"--k2hr3_app_port_ext(-appext)\" option needs parameter(number)."
			exit 1
		fi
		if echo "$1" | grep -q "[^0-9]"; then
			PRNERR "\"--k2hr3_app_port_ext(-appext)\" option parameter($1) must be 0 or positive number."
			exit 1
		fi
		OPT_APP_PORT_EXT="$1"

	elif echo "$1" | grep -q -i -e "^-api$" -e "^--k2hr3_api_port$"; then
		if [ -n "${OPT_API_PORT}" ]; then
			PRNERR "Already specified \"--k2hr3_api_port(-api)\" option."
			exit 1
		fi
		shift
		if [ -z "$1" ]; then
			PRNERR "\"--k2hr3_api_port(-api)\" option needs parameter(number)."
			exit 1
		fi
		if echo "$1" | grep -q "[^0-9]"; then
			PRNERR "\"--k2hr3_api_port(-api)\" option parameter($1) must be 0 or positive number."
			exit 1
		fi
		OPT_API_PORT="$1"

	elif echo "$1" | grep -q -i -e "^-apiext$" -e "^--k2hr3_api_port_ext$"; then
		if [ -n "${OPT_API_PORT_EXT}" ]; then
			PRNERR "Already specified \"--k2hr3_api_port_ext(-apiext)\" option."
			exit 1
		fi
		shift
		if [ -z "$1" ]; then
			PRNERR "\"--k2hr3_api_port_ext(-apiext)\" option needs parameter(number)."
			exit 1
		fi
		if echo "$1" | grep -q "[^0-9]"; then
			PRNERR "\"--k2hr3_api_port_ext(-apiext)\" option parameter($1) must be 0 or positive number."
			exit 1
		fi
		OPT_API_PORT_EXT="$1"

	elif echo "$1" | grep -q -i -e "^-uwc$" -e "^--up_wait_count$"; then
		if [ -n "${OPT_UP_WAIT_COUNT}" ]; then
			PRNERR "Already specified \"--up_wait_count\" option."
			exit 1
		fi
		shift
		if [ -z "$1" ]; then
			PRNERR "\"--up_wait_count(-uwc)\" option needs parameter(number)."
			exit 1
		fi
		if echo "$1" | grep -q "[^0-9]"; then
			PRNERR "\"--up_wait_count(-uwc)\" option parameter($1) must be 0 or positive number."
			exit 1
		fi
		OPT_UP_WAIT_COUNT="$1"

	else
		PRNERR "$1 option is unknown."
		exit 1
	fi
	shift
done

#
# Set default value
#
if [ -z "${OPT_DO_CLEAR}" ]; then
	OPT_DO_CLEAR=1
fi
if [ -z "${OPT_PARENT_TYPE}" ]; then
	OPT_PARENT_TYPE="Auto"
fi
if [ -z "${OPT_APP_PORT}" ]; then
	OPT_APP_PORT=28080
fi
if [ -z "${OPT_APP_PORT_EXT}" ]; then
	OPT_APP_PORT_EXT=28080
fi
if [ -z "${OPT_API_PORT}" ]; then
	OPT_API_PORT=18080
fi
if [ -z "${OPT_API_PORT_EXT}" ]; then
	OPT_API_PORT_EXT=18080
fi
if [ -z "${OPT_UP_WAIT_COUNT}" ]; then
	OPT_UP_WAIT_COUNT=0
fi

PRNINFO "Succeed to check option."

#----------------------------------------------------------
# Variables
#----------------------------------------------------------
#
# Python
#
if ! python --version >/dev/null 2>&1; then
	if ! python3 --version >/dev/null 2>&1; then
		PRNERR "The python program could not be found."
		exit 1
	fi
	PYBIN="python3"
else
	PYBIN="python"
fi
PRNINFO "Succeed to check python(${PYBIN})."

#----------------------------------------------------------
# Decision : Hostname and IP address
#----------------------------------------------------------
#
# Get parent hostname and IP address from local hostname
# (All cases are needed this because it used by openstack identiy url)
#
PRNMSG "Decision Hostname and IP address"

TYPE_NAME_PARENT_HOSTNAME=$(hostname)
TYPE_NAME_PARENT_IP=
if [ -z "${TYPE_NAME_PARENT_HOSTNAME}" ]; then
	PRNINFO "Could not get local hostname."
else
	if command -v dig >/dev/null 2>&1; then
		TYPE_NAME_PARENT_IP=$(dig "${TYPE_NAME_PARENT_HOSTNAME}" | grep "${TYPE_NAME_PARENT_HOSTNAME}" | grep -v '^;' | sed -e 's/IN A//g' | awk '{print $3}')
		if [ -z "${TYPE_NAME_PARENT_IP}" ]; then
			PRNINFO "Could not get IP address for local hostname."
			TYPE_NAME_PARENT_HOSTNAME=
		else
			PRNINFO "Local hostname is ${TYPE_NAME_PARENT_HOSTNAME} and IP address is ${TYPE_NAME_PARENT_IP}."
		fi
	else
		PRNINFO "Not found dig command, you should install dig command(ex. ${CYEL}\"bind-utils\"${CDEF} on centos, or ${CYEL}\"dnsutils\"${CDEF} on ubuntu)."
		TYPE_NAME_PARENT_HOSTNAME=
	fi
fi

#
# Get parent IP address from default nic
#
TYPE_NIC_PARENT_HOSTNAME=
TYPE_NIC_PARENT_IP=
if [ "${OPT_PARENT_TYPE}" = "Auto" ] || [ "${OPT_PARENT_TYPE}" = "Nic" ]; then
	PARENT_IP_NIC_NAME=$(ip -f inet route | grep default  | awk '{print $5}')

	if [ -n "${PARENT_IP_NIC_NAME}" ]; then
		TYPE_NIC_PARENT_IP=$(ip -f inet addr show "${PARENT_IP_NIC_NAME}" | grep inet | awk '{print $2}' | sed 's#/# #g' | awk '{print $1}')

		if [ -z "${TYPE_NIC_PARENT_IP}" ]; then
			PRNINFO "Could not get IP address from default NIC."
		else
			PRNINFO "Default NIC IP address is ${TYPE_NIC_PARENT_IP}."
			TYPE_NIC_PARENT_HOSTNAME=${TYPE_NIC_PARENT_IP}
		fi
	else
		PRNINFO "Could not get IP address from default NIC."
	fi
fi

#
# Decide parent hostname and ip address and IP address for identity URL
#
IDENTIRY_HOST=${TYPE_NAME_PARENT_IP}
K2HR3_EXTERNAL_HOSTNAME=
K2HR3_EXTERNAL_HOSTIP=
if [ "${OPT_PARENT_TYPE}" = "Custom" ]; then
	PRNINFO "Decide hostname or IP address(${TYPE_CUSTOM_PARENT_IP}) for external access by \"--use_parent_custom\" option."
	K2HR3_EXTERNAL_HOSTNAME=${TYPE_CUSTOM_PARENT_HOSTNAME}
	K2HR3_EXTERNAL_HOSTIP=${TYPE_CUSTOM_PARENT_IP}

	if [ -z "${IDENTIRY_HOST}" ]; then
		PRNINFO "Not found local host ip address, then use specified host(${TYPE_CUSTOM_PARENT_IP}) for Identiy IP address."
		IDENTIRY_HOST=${TYPE_CUSTOM_PARENT_IP}
	else
		PRNINFO "Decide Identiy IP address(${TYPE_NAME_PARENT_IP}) from local hostname."
	fi

elif [ "${OPT_PARENT_TYPE}" = "Auto" ]; then
	if [ -z "${TYPE_NIC_PARENT_IP}" ]; then
		if [ -z "${TYPE_NAME_PARENT_IP}" ]; then
			PRNERR "Could not find IP address for host, you should specify \"--use_parent_custom\" or \"--use_parent_nic\" or \"--use_parent_name\" options for deciding it."
			exit 1
		fi

		PRNINFO "Decide hostname/IP address(${TYPE_NAME_PARENT_HOSTNAME}/${TYPE_NAME_PARENT_IP}) for external access from local hostanme."
		K2HR3_EXTERNAL_HOSTNAME=${TYPE_NAME_PARENT_HOSTNAME}
		K2HR3_EXTERNAL_HOSTIP=${TYPE_NAME_PARENT_IP}

		if [ -z "${IDENTIRY_HOST}" ]; then
			PRNINFO "Not found local host ip address, then use local host IP address(${TYPE_NAME_PARENT_IP}) for Identiy IP address."
			IDENTIRY_HOST=${TYPE_NAME_PARENT_IP}
		else
			PRNINFO "Decide Identiy IP address(${TYPE_NAME_PARENT_IP}) from local hostname."
		fi
	else
		PRNINFO "Decide IP address(${TYPE_NIC_PARENT_IP}) for external access from default NIC."
		K2HR3_EXTERNAL_HOSTNAME=${TYPE_NIC_PARENT_HOSTNAME}
		K2HR3_EXTERNAL_HOSTIP=${TYPE_NIC_PARENT_IP}

		if [ -z "${IDENTIRY_HOST}" ]; then
			PRNINFO "Not found local host ip address, then use default NIC IP address(${TYPE_NIC_PARENT_IP}) for Identiy IP address."
			IDENTIRY_HOST=${TYPE_NIC_PARENT_IP}
		else
			PRNINFO "Decide Identiy IP address(${TYPE_NAME_PARENT_IP}) from local hostname."
		fi
	fi

elif [ "${OPT_PARENT_TYPE}" = "Name" ]; then
	PRNINFO "Decide hostname/IP address(${TYPE_NAME_PARENT_HOSTNAME}/${TYPE_NAME_PARENT_IP}) for external access from local hostanme(\"--use_parent_name\" option)."
	K2HR3_EXTERNAL_HOSTNAME=${TYPE_NAME_PARENT_HOSTNAME}
	K2HR3_EXTERNAL_HOSTIP=${TYPE_NAME_PARENT_IP}

	if [ -z "${IDENTIRY_HOST}" ]; then
		PRNINFO "Not found local host ip address, then use local host IP address(${TYPE_NAME_PARENT_IP}) for Identiy IP address."
		IDENTIRY_HOST=${TYPE_NAME_PARENT_IP}
	else
		PRNINFO "Decide Identiy IP address(${TYPE_NAME_PARENT_IP}) from local hostname."
	fi

elif [ "${OPT_PARENT_TYPE}" = "Nic" ]; then
	PRNINFO "Decide IP address(${TYPE_NIC_PARENT_IP}) for external access from default NIC(\"--use_parent_nic\" option)."
	K2HR3_EXTERNAL_HOSTNAME=${TYPE_NIC_PARENT_HOSTNAME}
	K2HR3_EXTERNAL_HOSTIP=${TYPE_NIC_PARENT_IP}

	if [ -z "${IDENTIRY_HOST}" ]; then
		PRNINFO "Not found local host ip address, then use default NIC IP address(${TYPE_NIC_PARENT_IP}) for Identiy IP address."
		IDENTIRY_HOST=${TYPE_NIC_PARENT_IP}
	else
		PRNINFO "Decide Identiy IP address(${TYPE_NAME_PARENT_IP}) from local hostname."
	fi
fi

#----------------------------------------------------------
# Check devpack directory in k2hr3 utilities and utils
#----------------------------------------------------------
PRNMSG "Check devpack directory in k2hr3 utilities and utils"

K2HR3_DEVPACK_TEMPL_DIR="${CURRENT_DIR}"
K2HR3_UTILS_DIR="${CURRENT_DIR}/k2hr3_utils"
K2HR3_DEVPACK_NAME="devpack"
K2HR3_DEVPACK_DIR="${K2HR3_UTILS_DIR}/${K2HR3_DEVPACK_NAME}"
K2HR3_DEVPACK_CONF_DIR="${K2HR3_DEVPACK_DIR}/conf"
K2HR3_DEVPACK_API_CONF_TEMPL_FILE="custom_production_api.templ"
K2HR3_DEVPACK_APP_CONF_TEMPL_FILE="custom_production_app.templ"

if [ -z "${K2HR3_UTILS_GITURL}" ]; then
	K2HR3_UTILS_GIT_URL="https://github.com/yahoojapan/k2hr3_utils.git"
fi

#
# Check k2hr3_utils/devpack directory
#
if [ ! -d "${K2HR3_DEVPACK_DIR}" ]; then
	PRNINFO "Not found ${K2HR3_DEVPACK_DIR} directory, so try to clone k2hr3_utils git repository."

	#
	# Bypassing directory permissions
	#
	if ! sudo mkdir "${K2HR3_UTILS_DIR}" >/dev/null 2>&1; then
		PRNERR "Failed to create ${K2HR3_UTILS_DIR} directory."
		exit 1
	fi
	if ! sudo chmod 777 "${K2HR3_UTILS_DIR}" >/dev/null 2>&1; then
		PRNERR "Failed to set premission ${K2HR3_UTILS_DIR} directory."
		exit 1
	fi

	if ! command -v git >/dev/null 2>&1; then
		PRNERR "Not found git command, please install git command."
		exit 1
	fi
	if ! git clone "${K2HR3_UTILS_GIT_URL}" >/dev/null 2>&1; then
		PRNERR "Failed to clone ${K2HR3_UTILS_GIT_URL} repository."
		exit 1
	fi
	if [ ! -d "${K2HR3_DEVPACK_DIR}" ]; then
		PRNERR "Not found ${K2HR3_DEVPACK_DIR}."
		exit 1
	fi
fi

#
# Check the directory to K2HR3 configuration template file
#
if [ ! -d "${K2HR3_DEVPACK_CONF_DIR}" ]; then
	PRNERR "Could not find ${K2HR3_DEVPACK_CONF_DIR} directory."
	exit 1
fi

PRNINFO "Succeed to check devpack directory in k2hr3 utilities and utils"

#----------------------------------------------------------
# Set OpenStack Environments for trove
#----------------------------------------------------------
# [NOTE]
# This script uses "trove" user and "service" project.
#
PRNMSG "Setup environments for trove user to build K2HR3 system"

if ! SetOpenStackAuthEnv "trove" "service"; then
	exit 1
fi

#----------------------------------------------------------
# Check and clear existed OpenStack resources
#----------------------------------------------------------
PRNMSG "Check and clear existed OpenStack resources"

K2HR3_HOSTNAME="k2hdkc-dbaas-k2hr3"
KEYPAIR_NAME="k2hr3key"
PRIVATE_KEY_PATH="${K2HR3_DEVPACK_CONF_DIR}"
PRIVATE_KEY_FILE="${PRIVATE_KEY_PATH}/${KEYPAIR_NAME}_private.pem"
K2HR3_SECURITY_GROUP_NAME="k2hdkc-dbaas-k2hr3-secgroup"
HAPROXY_CFG_FILE="${K2HR3_DEVPACK_CONF_DIR}/haproxy.cfg"
HAPROXY_LOG_FILE="${K2HR3_DEVPACK_DIR}/log/haproxy.log"

if [ "${OPT_DO_CLEAR}" -eq 1 ]; then
	#
	# Check Virtual Machine for K2HR3 system and remove it
	#
	K2HR3_HOST_TMP=$(openstack server list | grep "${K2HR3_HOSTNAME}")
	if [ -n "${K2HR3_HOST_TMP}" ]; then
		PRNINFO "Already run \"${K2HR3_HOSTNAME}\" instance, then remove it."
		openstack server delete "${K2HR3_HOSTNAME}"
		sleep 10
	fi

	#
	# Check private key file(pem) and remove it
	#
	if [ -f "${PRIVATE_KEY_FILE}" ]; then
		PRNINFO "\"${PRIVATE_KEY_FILE}\" for \"${KEYPAIR_NAME}\" keypair private file exists, then remove it."
		if ! rm "${PRIVATE_KEY_FILE}" 2>/dev/null; then
			PRNINFO "Could not remove \"${PRIVATE_KEY_FILE}\" for \"${KEYPAIR_NAME}\" keypair private file."
			exit 1
		fi
	fi

	#
	# Check k2hr3key keypair in OpenStack
	#
	KEYPAIR_TMP=$(openstack keypair list -f value | grep "${KEYPAIR_NAME}")
	if [ -n "${KEYPAIR_TMP}" ]; then
		PRNINFO "Already has \"${KEYPAIR_NAME}\" keypair, then remove it."
		openstack keypair delete "${KEYPAIR_NAME}"
		sleep 10
	fi

	#
	# Check K2HR3 security group in OpenStack
	#
	SECURITY_GROUP_TMP=$(openstack security group list | grep "${K2HR3_SECURITY_GROUP_NAME}")
	if [ -n "${SECURITY_GROUP_TMP}" ]; then
		PRNINFO "Already has \"${K2HR3_SECURITY_GROUP_NAME}\" security group, then remove it."
		#
		# Check security group ids for k2hdkc-dbaas-k2hr3-secgroup
		#
		SECURITY_GROUP_IDS=$(openstack security group list | grep "${K2HR3_SECURITY_GROUP_NAME}" | tr -d '|' | awk '{print $1}')
		for _one_group_id in ${SECURITY_GROUP_IDS}; do
			#
			# Remove all rules in security group
			#
			SECURITY_RULES_IN_GROUP_ID=$(openstack security group rule list -f value -c ID "${_one_group_id}")
			for _one_rule_id in ${SECURITY_RULES_IN_GROUP_ID}; do
				PRNINFO "Remove rule(${_one_rule_id}) in \"${K2HR3_SECURITY_GROUP_NAME}\" security group."
				openstack security group rule delete "${_one_rule_id}"
			done

			PRNINFO "Remove security group is(${_one_group_id}) in \"${K2HR3_SECURITY_GROUP_NAME}\"."
			openstack security group delete "${_one_group_id}"
		done
	fi

	#
	# Check and stop old HAProxy
	#
	# shellcheck disable=SC2009
	OLD_HAPROXY_PIDS=$(ps ax | grep haproxy | grep "${HAPROXY_CFG_FILE}" | grep -v grep | awk '{print $1}')
	if [ -n "${OLD_HAPROXY_PIDS}" ]; then
		PRNINFO "Found old HAProxys(${OLD_HAPROXY_PIDS}), then stop these."
		kill -TERM "${OLD_HAPROXY_PIDS}"
	fi
fi

PRNINFO "Succeed to check and clear existed OpenStack resources"

#----------------------------------------------------------
# Create related OpenStack resources
#----------------------------------------------------------
PRNMSG "Create related OpenStack resources"

#
# Get Flavor ID ( = 'ds1G' )
#
FLAVOR_ID=$(openstack flavor list -f value | grep 'ds1G' | awk '{print $1}')
if [ -z "${FLAVOR_ID}" ]; then
	PRNERR "Could not get flavor id for \"ds1G\"."
	exit 1
fi

#
# Get Network ID ( = 'private' )
#
NETWORK_ID=$(openstack network list -f value | grep private | awk '{print $1}')
if [ -z "${NETWORK_ID}" ]; then
	PRNERR "Could not get network id for \"private\"."
	exit 1
fi

#
# Image upload ( Ubuntu 22.04(jammy) )
#
PRNINFO "Download and register os image(ubuntu) for K2HR3 system."

IMAGE_NAME="k2hdkc-dbaas-k2hr3-ubuntu-2204"
EXIST_IMAGE_TMP=$(openstack image list -f value | grep "${IMAGE_NAME}")
if [ -n "${EXIST_IMAGE_TMP}" ]; then
	PRNWARN "Already has ${IMAGE_NAME} image, thus skip image upload."
else
	if [ ! -f "${CURRENT_DIR}/jammy-server-cloudimg-amd64.img" ]; then
		wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img
	else
		PRNINFO "Already jammy-server-cloudimg-amd64.img in ${CURRENT_DIR}, so skip download it."
	fi

	# [NOTE]
	# Need to set upload user = admin and project = admin,
	# because trove:service is going to failure to upload.
	# So we run sub-process for changing environments
	#
	(
		if ! SetOpenStackAuthEnv "admin" "admin"; then
			exit 1
		fi
		if ! openstack image create "${IMAGE_NAME}" --disk-format qcow2 --container-format bare --public < jammy-server-cloudimg-amd64.img; then
			PRNERR "Failed to upload image \"${IMAGE_NAME}\" from jammy-server-cloudimg-amd64.img file."
			exit 1
		fi
	)

	# [NOTE]
	# Do not remove original image, manually do it if you need.
	#
	#rm -f jammy-server-cloudimg-amd64.img
fi

#
# Get Image ID ( = 'Ubuntu2204' )
#
IMAGE_ID=$(openstack image list -f value | grep "${IMAGE_NAME}" | awk '{print $1}')
if [ -z "${IMAGE_ID}" ]; then
	PRNERR "Could not get \"${IMAGE_NAME}\" image id."
	exit 1
fi

#
# Create Keypair
#
PRNINFO "Make key pair for K2HR3 system to access by ssh manually."

if [ -f "${PRIVATE_KEY_FILE}" ]; then
	PRNERR "\"${PRIVATE_KEY_FILE}\" for \"${KEYPAIR_NAME}\" keypair private file exists."
	exit 1
fi
KEYPAIR_TMP=$(openstack keypair list -f value | grep "${KEYPAIR_NAME}")
if [ -n "${KEYPAIR_TMP}" ]; then
	PRNERR "Already has \"${KEYPAIR_NAME}\" keypair."
	exit 1
fi

openstack keypair create --private-key "${PRIVATE_KEY_FILE}" "${KEYPAIR_NAME}" 2>&1 | sed -e 's|^|    |g'

KEYPAIR_TMP=$(openstack keypair list -f value | grep "${KEYPAIR_NAME}")
if [ -z "${KEYPAIR_TMP}" ]; then
	PRNERR "Could not create \"${KEYPAIR_NAME}\" keypair."
	exit 1
fi
if [ ! -f "${PRIVATE_KEY_FILE}" ]; then
	PRNERR "Could not create \"${PRIVATE_KEY_FILE}\" for \"${KEYPAIR_NAME}\" keypair private file."
	exit 1
fi
chmod 0600 "${PRIVATE_KEY_FILE}"

#
# Create Security Group
#
PRNINFO "Create security group(k2hdkc-dbaas-k2hr3-secgroup) for K2HR3 system."

SECURITY_GROUP_TMP=$(openstack security group list | grep "${K2HR3_SECURITY_GROUP_NAME}")
if [ -n "${SECURITY_GROUP_TMP}" ]; then
	PRNERR "Already has \"${K2HR3_SECURITY_GROUP_NAME}\" security group."
	exit 1
fi

if ({ openstack security group create --description 'security group for k2hr3 system' "${K2HR3_SECURITY_GROUP_NAME}" 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
	PRNERR "Could not create \"${K2HR3_SECURITY_GROUP_NAME}\" security group."
	exit 1
fi

if ({ openstack security group rule create --ingress --ethertype IPv4 --project "${OS_PROJECT_ID}" --dst-port 22:22 --protocol tcp --description 'ssh port' "${K2HR3_SECURITY_GROUP_NAME}" 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
	PRNERR "Could not add ssh port(22) to \"${K2HR3_SECURITY_GROUP_NAME}\" security group."
	exit 1
fi

if ({ openstack security group rule create --ingress --ethertype IPv4 --project "${OS_PROJECT_ID}" --dst-port "${OPT_APP_PORT}:${OPT_APP_PORT}" --protocol tcp --description 'k2hr3 app http port' "${K2HR3_SECURITY_GROUP_NAME}" 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
	PRNERR "Could not add k2hr3 app http port(${OPT_APP_PORT}) to \"${K2HR3_SECURITY_GROUP_NAME}\" security group."
	exit 1
fi

if ({ openstack security group rule create --ingress --ethertype IPv4 --project "${OS_PROJECT_ID}" --dst-port "${OPT_API_PORT}:${OPT_API_PORT}" --protocol tcp --description 'k2hr3 api http port' "${K2HR3_SECURITY_GROUP_NAME}" 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
	PRNERR "Could not add k2hr3 api http port(${OPT_API_PORT}) to \"${K2HR3_SECURITY_GROUP_NAME}\" security group."
	exit 1
fi

#
# Make user data file
#
PRNINFO "Create a instance(k2hdkc-dbaas-k2hr3)  for K2HR3 system."

USERDATA_FILE="/tmp/k2hr3_userdata.txt"
{
	echo '#cloud-config'
	echo 'password: ubuntu'
	echo 'chpasswd: { expire: False }'
	echo 'ssh_pwauth: True'
} > "${USERDATA_FILE}"

#
# Create Virtual Machine for K2HR3 system
#
K2HR3_HOSTNAME="k2hdkc-dbaas-k2hr3"

K2HR3_HOST_TMP=$(openstack server list | grep "${K2HR3_HOSTNAME}")
if [ -n "${K2HR3_HOST_TMP}" ]; then
	PRNERR "Already run \"${K2HR3_HOSTNAME}\" instance."
	exit 1
fi

openstack server create --flavor "${FLAVOR_ID}" --image "${IMAGE_ID}" --key-name "${KEYPAIR_NAME}" --user-data "${USERDATA_FILE}" --security-group "${K2HR3_SECURITY_GROUP_NAME}" --network "${NETWORK_ID}" "${K2HR3_HOSTNAME}" 2>&1 | sed -e 's|^|    |g'
rm -f "${USERDATA_FILE}"

#
# Wait for instance up(status becomes ACTIVE)
#
PRNINFO "Wait for instance(k2hdkc-dbaas-k2hr3) up."
if [ "${OPT_UP_WAIT_COUNT}" -eq 0 ]; then
	#
	# No retry upper limit
	#
	WAIT_COUNT=-1
else
	WAIT_COUNT=${OPT_UP_WAIT_COUNT}
fi

IS_INSTANCE_UP=0
while [ "${WAIT_COUNT}" -ne 0 ]; do
	sleep 10
	INSTANCE_STATUS=$(openstack server list | grep "${K2HR3_HOSTNAME}" | tr -d '|' | awk '{print $3}')
	if [ "${INSTANCE_STATUS}" = "ACTIVE" ]; then
		IS_INSTANCE_UP=1
		break;
	fi
	if [ "${WAIT_COUNT}" -gt 0 ]; then
		WAIT_COUNT=$((WAIT_COUNT - 1))
	fi
done
if [ "${IS_INSTANCE_UP}" -ne 1 ]; then
	PRNERR "Instance \"${K2HR3_HOSTNAME}\" did not start until the timeout."
	exit 1
fi

#
# Create Floating IP
#
if ! K2HR3_FLOATING_IP_ADDRESS=$(openstack floating ip create public -f yaml | grep '^floating_ip_address:' | awk '{print $2}'); then
	PRNERR "Failed to create Floating IP."
	exit 1
fi
if [ -z "${K2HR3_FLOATING_IP_ADDRESS}" ]; then
	PRNERR "Failed to create Floating IP."
	exit 1
fi

#
# Set Floating IP to instance
#
if ! openstack server add floating ip "${K2HR3_HOSTNAME}" "${K2HR3_FLOATING_IP_ADDRESS}"; then
	PRNERR "Failed to add Floating IP(${K2HR3_FLOATING_IP_ADDRESS}) to ${K2HR3_HOSTNAME} server."
	exit 1
fi

#
# Get Server ID and Private IP Address
#
K2HR3_SERVER_ID=$(openstack server list -f value | grep "${K2HR3_HOSTNAME}" | grep ACTIVE | awk '{print $1}')
if [ -z "${K2HR3_SERVER_ID}" ]; then
	PRNERR "Could not create \"${K2HR3_HOSTNAME}\" instance."
	exit 1
fi

K2HR3_PRIVATE_IP_ADDRESSES=$(openstack server show "${K2HR3_SERVER_ID}" -f value | grep "'private':" | sed -e "s|private'[[:space:]]*:[[:space:]]*||g" | tr -d "'" | tr -d  '[' | tr -d  ']' | tr -d  '{' | tr -d  '}' | tr -d ',')
for _one_ip_address in ${K2HR3_PRIVATE_IP_ADDRESSES}; do
	if echo "${_one_ip_address}" | grep -q ':'; then
		K2HR3_PRIVATE_IPV6_ADDRESS="${_one_ip_address}"
	elif [ "${_one_ip_address}" != "${K2HR3_FLOATING_IP_ADDRESS}" ]; then
		K2HR3_PRIVATE_IPV4_ADDRESS="${_one_ip_address}"
	fi
done
if [ -n "${K2HR3_PRIVATE_IPV4_ADDRESS}" ]; then
	K2HR3_PRIVATE_IP_ADDRESS="${K2HR3_PRIVATE_IPV4_ADDRESS}"
else
	K2HR3_PRIVATE_IP_ADDRESS="${K2HR3_PRIVATE_IPV6_ADDRESS}"
fi
if [ -z "${K2HR3_PRIVATE_IP_ADDRESS}" ]; then
	PRNERR "Could not get IP address for \"${K2HR3_HOSTNAME}\" instance."
	exit 1
fi

PRNINFO "Succeed to check and clear existed OpenStack resources"

#----------------------------------------------------------
# Setup NO_PROXY
#----------------------------------------------------------
PRNMSG "Setup NO_PROXY environments for adding k2hr3 host ip addresses."

_ADDITIONAL_NO_PROXY_IPS=""

if [ -n "${K2HR3_EXTERNAL_HOSTIP}" ]; then
	if [ -n "${_ADDITIONAL_NO_PROXY_IPS}" ]; then
		_ADDITIONAL_NO_PROXY_IPS="${_ADDITIONAL_NO_PROXY_IPS},"
	fi
	_ADDITIONAL_NO_PROXY_IPS="${_ADDITIONAL_NO_PROXY_IPS}${K2HR3_EXTERNAL_HOSTIP}"
fi
if [ -n "${K2HR3_FLOATING_IP_ADDRESS}" ]; then
	if [ -n "${_ADDITIONAL_NO_PROXY_IPS}" ]; then
		_ADDITIONAL_NO_PROXY_IPS="${_ADDITIONAL_NO_PROXY_IPS},"
	fi
	_ADDITIONAL_NO_PROXY_IPS="${_ADDITIONAL_NO_PROXY_IPS}${K2HR3_FLOATING_IP_ADDRESS}"
fi
if [ -n "${K2HR3_PRIVATE_IP_ADDRESS}" ]; then
	if [ -n "${_ADDITIONAL_NO_PROXY_IPS}" ]; then
		_ADDITIONAL_NO_PROXY_IPS="${_ADDITIONAL_NO_PROXY_IPS},"
	fi
	_ADDITIONAL_NO_PROXY_IPS="${_ADDITIONAL_NO_PROXY_IPS}${K2HR3_PRIVATE_IP_ADDRESS}"
fi

if [ -n "${_ADDITIONAL_NO_PROXY_IPS}" ]; then
	#
	# The filename for additional no proxy ip addresses 
	#
	_ADDITIONAL_NO_PROXY_FILENAME=".no_proxy_k2hr3"

	#
	# Create the file for current user
	#
	_CUR_USERNAME=$(id -u -n)
	_CUR_USER_HOMEDIR=$(getent passwd "${_CUR_USERNAME}" | cut -d: -f6)

	if [ -f "${_CUR_USER_HOMEDIR}/${_ADDITIONAL_NO_PROXY_FILENAME}" ]; then
		rm -f "${_CUR_USER_HOMEDIR}/${_ADDITIONAL_NO_PROXY_FILENAME}"
	fi
	printf "%s" "${_ADDITIONAL_NO_PROXY_IPS}" > "${_CUR_USER_HOMEDIR}/${_ADDITIONAL_NO_PROXY_FILENAME}"

	#
	# Create the file for sudo user
	#
	if [ -n "${SUDO_USER}" ] && [ "${_CUR_USERNAME}" != "${SUDO_USER}" ]; then
		_SUDO_USER_HOMEDIR=$(getent passwd "${SUDO_USER}" | cut -d: -f6)

		if ! sudo -u "${SUDO_USER}" cp -p "${_CUR_USER_HOMEDIR}/${_ADDITIONAL_NO_PROXY_FILENAME}" "${_SUDO_USER_HOMEDIR}/${_ADDITIONAL_NO_PROXY_FILENAME}" 2>/dev/null; then
			PRNWARN "Could not create file(${_SUDO_USER_HOMEDIR}/${_ADDITIONAL_NO_PROXY_FILENAME}), but continue..."
		fi
	fi

	#
	# Setup NO_PROXY environment
	#
	if [ -n "${NO_PROXY_VAL}" ]; then
		NO_PROXY="${_ADDITIONAL_NO_PROXY_IPS},${NO_PROXY_VAL}"
	else
		NO_PROXY="${_ADDITIONAL_NO_PROXY_IPS}"
	fi
	no_proxy="${NO_PROXY}"

	export NO_PROXY
	export no_proxy
else
	PRNINFO "Added no IP addresses."
fi

PRNINFO "Succeed to setup NO_PROXY environments for adding k2hr3 host ip addresses."

#----------------------------------------------------------
# Create K2HR3 system
#----------------------------------------------------------
PRNMSG "Setup programs on instance(k2hdkc-dbaas-k2hr3) for K2HR3 system."

#
# SSH options
#
SSH_OPTION="StrictHostKeyChecking=no"
USER_AND_HOST="ubuntu@${K2HR3_FLOATING_IP_ADDRESS}"

#
# Check and wait for instance SSH up
#
PRNINFO "Wait for instance(k2hdkc-dbaas-k2hr3) SSH up."
if [ "${OPT_UP_WAIT_COUNT}" -eq 0 ]; then
	#
	# No retry upper limit
	#
	WAIT_COUNT=-1
else
	WAIT_COUNT="${OPT_UP_WAIT_COUNT}"
fi

IS_INSTANCE_SSH_UP=0
while [ "${WAIT_COUNT}" -ne 0 ]; do
	#
	# Use dummy command
	#
	if ssh -o "${SSH_OPTION}" -i "${PRIVATE_KEY_FILE}" "${USER_AND_HOST}" "pwd >/dev/null" >/dev/null 2>&1; then
		IS_INSTANCE_SSH_UP=1
		break;
	fi
	if [ "${WAIT_COUNT}" -gt 0 ]; then
		WAIT_COUNT=$((WAIT_COUNT - 1))
	fi
	sleep 10
done
if [ "${IS_INSTANCE_SSH_UP}" -ne 1 ]; then
	PRNERR "Instance \"${K2HR3_HOSTNAME}\" SSH did not up until the timeout."
	exit 1
fi

#
# Copy apt configuration for PROXY
#
APT_PROXY_CONF_FILENAME="00-aptproxy.conf"
LOCAL_APT_PROXY_CONF="${CURRENT_DIR}/${APT_PROXY_CONF_FILENAME}"
APT_PROXY_CONF="/etc/apt/apt.conf.d/${APT_PROXY_CONF_FILENAME}"

if ! SetupAptConfig "${SSH_OPTION}" "${PRIVATE_KEY_FILE}" "${USER_AND_HOST}"; then
	exit 1
fi

#
# Setup /etc/systemd/resolved.conf
#
RESOLV_CONF_FILE="/etc/systemd/resolved.conf"

if ! SetupResolvedConfig "${SSH_OPTION}" "${PRIVATE_KEY_FILE}" "${USER_AND_HOST}"; then
	exit 1
fi

#
# Copy custom files for devpack in K2HR3 Utilities
#
if [ -f "${K2HR3_DEVPACK_TEMPL_DIR}/${K2HR3_DEVPACK_API_CONF_TEMPL_FILE}" ]; then
	if ! cp -p "${K2HR3_DEVPACK_TEMPL_DIR}/${K2HR3_DEVPACK_API_CONF_TEMPL_FILE}" "${K2HR3_DEVPACK_CONF_DIR}/${K2HR3_DEVPACK_API_CONF_TEMPL_FILE}" >/dev/null 2>&1; then
		PRNERR "Could not copy ${K2HR3_DEVPACK_TEMPL_DIR}/${K2HR3_DEVPACK_API_CONF_TEMPL_FILE} to ${K2HR3_DEVPACK_CONF_DIR}/${K2HR3_DEVPACK_API_CONF_TEMPL_FILE}."
		exit 1
	else
		PRNINFO "Copied ${K2HR3_DEVPACK_TEMPL_DIR}/${K2HR3_DEVPACK_API_CONF_TEMPL_FILE} to ${K2HR3_DEVPACK_CONF_DIR}/${K2HR3_DEVPACK_API_CONF_TEMPL_FILE}."
	fi
fi
if [ -f "${K2HR3_DEVPACK_TEMPL_DIR}/${K2HR3_DEVPACK_APP_CONF_TEMPL_FILE}" ]; then
	if ! cp -p "${K2HR3_DEVPACK_TEMPL_DIR}/${K2HR3_DEVPACK_APP_CONF_TEMPL_FILE}" "${K2HR3_DEVPACK_CONF_DIR}/${K2HR3_DEVPACK_APP_CONF_TEMPL_FILE}" >/dev/null 2>&1; then
		PRNERR "Could not copy ${K2HR3_DEVPACK_TEMPL_DIR}/${K2HR3_DEVPACK_APP_CONF_TEMPL_FILE} tp ${K2HR3_DEVPACK_CONF_DIR}/${K2HR3_DEVPACK_APP_CONF_TEMPL_FILE}."
		exit 1
	else
		PRNINFO "Copied ${K2HR3_DEVPACK_TEMPL_DIR}/${K2HR3_DEVPACK_APP_CONF_TEMPL_FILE} to ${K2HR3_DEVPACK_CONF_DIR}/${K2HR3_DEVPACK_APP_CONF_TEMPL_FILE}."
	fi
fi

#
# Make devpack archive file
#
PRNINFO "Make devpack archive file"

K2HR3_PACK_TGZ="${K2HR3_DEVPACK_NAME}.tgz"
{
	tar cvf - -C "${K2HR3_UTILS_DIR}" "${K2HR3_DEVPACK_NAME}" | gzip - > "/tmp/${K2HR3_PACK_TGZ}"
} 2>&1 | sed -e 's|^|    |g'

#
# Copy file
#
if ! scp -o "${SSH_OPTION}" -i "${PRIVATE_KEY_FILE}" "/tmp/${K2HR3_PACK_TGZ}" "${USER_AND_HOST}:/home/ubuntu" >/dev/null 2>&1; then
	PRNERR "Could not copy k2hr3 pack to \"${K2HR3_HOSTNAME}\"."
	rm -f "/tmp/${K2HR3_PACK_TGZ}"
	exit 1
fi
rm -f "/tmp/${K2HR3_PACK_TGZ}"

#
# Expand file
#
if ({ ssh -o "${SSH_OPTION}" -i "${PRIVATE_KEY_FILE}" "${USER_AND_HOST}" "tar xvfz ${K2HR3_PACK_TGZ}" 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
	PRNERR "Could not expand \"${K2HR3_PACK_TGZ}\" file on \"${K2HR3_HOSTNAME}\"."
	exit 1
fi

#
# Run k2hr3_utils/devpack/bin/devpack.sh
#
echo ""
PRNINFO "Start to run all K2HR3 system on \"${K2HR3_HOSTNAME}\" by subprocess."

if [ -n "${K2HR3_FLOATING_IP_ADDRESS}" ]; then
	DEVPACK_HOSTIP="${K2HR3_FLOATING_IP_ADDRESS}"
elif [ -n "${K2HR3_PRIVATE_IP_ADDRESS}" ]; then
	DEVPACK_HOSTIP="${K2HR3_PRIVATE_IP_ADDRESS}"
else
	DEVPACK_HOSTIP="${K2HR3_EXTERNAL_HOSTIP}"
fi
if [ -n "${K2HR3_EXTERNAL_HOSTIP}" ]; then
	DEVPACK_EXTERNAL_HOSTIP="${K2HR3_EXTERNAL_HOSTIP}"
elif [ -n "${K2HR3_FLOATING_IP_ADDRESS}" ]; then
	DEVPACK_EXTERNAL_HOSTIP="${K2HR3_FLOATING_IP_ADDRESS}"
else
	DEVPACK_EXTERNAL_HOSTIP="${K2HR3_PRIVATE_IP_ADDRESS}"
fi
if [ -n "${K2HR3_PRIVATE_IP_ADDRESS}" ]; then
	DEVPACK_PRIVATE_HOSTIP="${K2HR3_PRIVATE_IP_ADDRESS}"
elif [ -n "${K2HR3_FLOATING_IP_ADDRESS}" ]; then
	DEVPACK_PRIVATE_HOSTIP="${K2HR3_FLOATING_IP_ADDRESS}"
else
	DEVPACK_PRIVATE_HOSTIP="${K2HR3_EXTERNAL_HOSTIP}"
fi

if ({ ssh -o "${SSH_OPTION}" -i "${PRIVATE_KEY_FILE}" "${USER_AND_HOST}" "HTTP_PROXY=${HTTP_PROXY} HTTPS_PROXY=${HTTPS_PROXY} NO_PROXY=${NO_PROXY_VAL} ${K2HR3_DEVPACK_NAME}/bin/devpack.sh -ni -nc --run_user nobody --openstack_region ${OS_REGION_NAME} --keystone_url http://${IDENTIRY_HOST}/identity --app_port ${OPT_APP_PORT} --app_port_external ${OPT_APP_PORT_EXT} --app_port_private ${OPT_API_PORT} --app_host ${DEVPACK_HOSTIP} --app_host_external ${DEVPACK_EXTERNAL_HOSTIP} --app_host_private ${DEVPACK_PRIVATE_HOSTIP} --api_port ${OPT_API_PORT} --api_port_external ${OPT_API_PORT_EXT} --api_port_private ${OPT_API_PORT} --api_host ${DEVPACK_HOSTIP} --api_host_external ${DEVPACK_EXTERNAL_HOSTIP} --api_host_private ${DEVPACK_PRIVATE_HOSTIP}" 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|        |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
	PRNERR "Failed to run k2hr3 system on \"${K2HR3_HOSTNAME}\"."
	exit 1
fi
PRNINFO "Succeed to run all K2HR3 system on \"${K2HR3_HOSTNAME}\"."

#
# Get haproxy example configuration
#
PRNINFO "Setup haproxy to access K2HR3 system from parent host."

if [ -f "${HAPROXY_CFG_FILE}" ]; then
	rm -f "${HAPROXY_CFG_FILE}"
fi
if [ -f "${HAPROXY_LOG_FILE}" ]; then
	rm -f "${HAPROXY_LOG_FILE}"
fi

if ! scp -o "${SSH_OPTION}" -i "${PRIVATE_KEY_FILE}" "${USER_AND_HOST}:/home/ubuntu/${K2HR3_DEVPACK_NAME}/conf/haproxy_example.cfg" "${HAPROXY_CFG_FILE}" >/dev/null 2>&1; then
	PRNERR "Could not get haproxy configuration file from \"${K2HR3_HOSTNAME}\"."
	exit 1
fi
if [ ! -f "${HAPROXY_CFG_FILE}" ]; then
	PRNERR "Could not get haproxy configuration file from \"${K2HR3_HOSTNAME}\"."
	exit 1
fi

PRNINFO "Succeed to setup programs on instance(k2hdkc-dbaas-k2hr3) for K2HR3 system."

#----------------------------------------------------------
# Run Haproxy
#----------------------------------------------------------
PRNMSG "Start to run haproxy process on \"${TYPE_NAME_PARENT_HOSTNAME}\"."

haproxy -f "${HAPROXY_CFG_FILE}" > "${HAPROXY_LOG_FILE}" 2>&1 &
sleep 1

HAPROXY_PID=$!
if ! ps ax | awk '{print $1}' | grep "${HAPROXY_PID}" >/dev/null 2>&1; then
	PRNERR "Could not run haproxy on \"${TYPE_NAME_PARENT_HOSTNAME}\"."
	exit 1
fi
PRNINFO "Succeed to run haproxy on \"${TYPE_NAME_PARENT_HOSTNAME}\"."

#----------------------------------------------------------
# Change private IP address to K2HR3
#----------------------------------------------------------
PRNMSG "Restart horizon httpd for changing k2hr3 private IP address."

HORIZON_BASE_DIR="${CURRENT_DIR}/../../horizon"
LOCAL_SETTINGS_PY_FILE="${HORIZON_BASE_DIR}/openstack_dashboard/local/local_settings.py"

#
# Add horizon config to local_settings.py
#
if grep -q '^[[:space:]]*HORIZON_CONFIG\["k2hr3"\]' "${LOCAL_SETTINGS_PY_FILE}"; then
	if ! perl -pi -e "BEGIN{undef $/;} s|\[\"k2hr3\"\].*\n\s+\"http_scheme\": \"(\S+)\",\n\s+\"host\": \"(\S+)\",|\[\"k2hr3\"\] = {\n    \"http_scheme\": \"\$1\",\n    \"host\": \"${K2HR3_FLOATING_IP_ADDRESS}\",|smg" "${LOCAL_SETTINGS_PY_FILE}"; then
		PRNERR "Substring k2hr3 host is failed."
		exit 1
	fi
else
	{
		echo ''
		echo 'HORIZON_CONFIG["k2hr3"] = {'
		echo '    "http_scheme": "http",'
		echo "    \"host\": \"${K2HR3_FLOATING_IP_ADDRESS}\","
		echo '    "port": 18080,'
		echo '}'
	} >> "${LOCAL_SETTINGS_PY_FILE}"
fi
if grep -q '^[[:space:]]*HORIZON_CONFIG\["k2hr3_from_private_network"\]' "${LOCAL_SETTINGS_PY_FILE}"; then
	if ! perl -pi -e "BEGIN{undef $/;} s|\[\"k2hr3_from_private_network\"\].*\n\s+\"http_scheme\": \"(\S+)\",\n\s+\"host\": \"(\S+)\",|\[\"k2hr3_from_private_network\"\] = {\n    \"http_scheme\": \"\$1\",\n    \"host\": \"${K2HR3_PRIVATE_IP_ADDRESS}\",|smg" "${LOCAL_SETTINGS_PY_FILE}"; then
		PRNERR "Substring k2hr3_from_private_network host is failed."
		exit 1
	fi
else
	{
		echo ''
		echo 'HORIZON_CONFIG["k2hr3_from_private_network"] = {'
		echo '    "http_scheme": "http",'
		echo "    \"host\": \"${K2HR3_PRIVATE_IP_ADDRESS}\","
		echo '    "port": 18080,'
		echo '}'
	} >> "${LOCAL_SETTINGS_PY_FILE}"
fi
if grep -q '^[[:space:]]*HORIZON_CONFIG\["k2hr3api"\]' "${LOCAL_SETTINGS_PY_FILE}"; then
	if ! perl -pi -e "BEGIN{undef $/;} s|\[\"k2hr3api\"\].*\n\s+\"http_scheme\": \"(\S+)\",\n\s+\"host\": \"(\S+)\",|\[\"k2hr3api\"\] = {\n    \"http_scheme\": \"\$1\",\n    \"host\": \"${K2HR3_FLOATING_IP_ADDRESS}\",|smg" "${LOCAL_SETTINGS_PY_FILE}"; then
		PRNERR "Substring k2hr3api host is failed."
		exit 1
	fi
else
	{
		echo ''
		echo 'HORIZON_CONFIG["k2hr3api"] = {'
		echo '    "http_scheme": "http",'
		echo "    \"host\": \"${K2HR3_FLOATING_IP_ADDRESS}\","
		echo '    "port": 18080,'
		echo '}'
	} >> "${LOCAL_SETTINGS_PY_FILE}"
fi
if grep -q '^[[:space:]]*HORIZON_CONFIG\["k2hr3api_from_private_network"\]' "${LOCAL_SETTINGS_PY_FILE}"; then
	if ! perl -pi -e "BEGIN{undef $/;} s|\[\"k2hr3api_from_private_network\"\].*\n\s+\"http_scheme\": \"(\S+)\",\n\s+\"host\": \"(\S+)\",|\[\"k2hr3api_from_private_network\"\] = {\n    \"http_scheme\": \"\$1\",\n    \"host\": \"${K2HR3_PRIVATE_IP_ADDRESS}\",|smg" "${LOCAL_SETTINGS_PY_FILE}"; then
		PRNERR "Substring k2hr3api_from_private_network host is failed."
		exit 1
	fi
else
	{
		echo ''
		echo 'HORIZON_CONFIG["k2hr3api_from_private_network"] = {'
		echo '    "http_scheme": "http",'
		echo "    \"host\": \"${K2HR3_PRIVATE_IP_ADDRESS}\","
		echo '    "port": 18080,'
		echo '}'
	} >> "${LOCAL_SETTINGS_PY_FILE}"
fi

#
# Restart
#
(
	cd "${HORIZON_BASE_DIR}" || exit 1
	"${PYBIN}" manage.py compress
	"${PYBIN}" manage.py collectstatic --noinput
) 2>&1 | sed -e 's|^|    |g'

if ({ sudo systemctl restart httpd 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
	PRNERR "Could not restart httpd for horizon."
	exit 1
fi

PRNINFO "Succeed to restart httpd for horizon."

#----------------------------------------------------------
# Additional settings for test K2HDKC slave node
#----------------------------------------------------------
# [NOTE] Be careful!
# After this processes, the user and project are switched to demo:demo.
# The passphrase for demo user is as same as trove user's one.
#
PRNMSG "Set security group(k2hdkc-slave-sec) on demo user for K2HDKC slave node."

if ! SetOpenStackAuthEnv "demo" "demo"; then
	exit 1
fi

#
# Check and remove existed security group for K2HDKC Slave node
#
# [NOTE]
# This should be checked in the same place as the K2HR3 security
# group check, but since the user and project ID etc are different,
# thus we will do it here.
#
SLAVE_SECURITY_GROUP_NAME="k2hdkc-slave-sec"

if [ "${OPT_DO_CLEAR}" -eq 1 ]; then
	#
	# Check K2HDKC Slave security group in OpenStack
	#
	SECURITY_GROUP_TMP=$(openstack security group list | grep "${SLAVE_SECURITY_GROUP_NAME}")
	if [ -n "${SECURITY_GROUP_TMP}" ]; then
		PRNINFO "Already has \"${SLAVE_SECURITY_GROUP_NAME}\" security group, then remove it."
		#
		# Check security group ids for k2hdkc-slave-sec
		#
		SECURITY_GROUP_IDS=$(openstack security group list | grep "${SLAVE_SECURITY_GROUP_NAME}" | tr -d '|' | awk '{print $1}')
		for _one_group_id in ${SECURITY_GROUP_IDS}; do
			#
			# Remove all rules in security group
			#
			SECURITY_RULES_IN_GROUP_ID=$(openstack security group rule list -f value -c ID "${_one_group_id}")
			for _one_rule_id in ${SECURITY_RULES_IN_GROUP_ID}; do
				PRNINFO "Remove rule(${_one_rule_id}) in \"${SLAVE_SECURITY_GROUP_NAME}\" security group."
				openstack security group rule delete "${_one_rule_id}"
			done

			PRNINFO "Remove security group is(${_one_group_id}) in \"${SLAVE_SECURITY_GROUP_NAME}\"."
			openstack security group delete "${_one_group_id}"
		done
	fi
fi

#
# Create Security Group for test K2HDKC slave node
#
SECURITY_GROUP_TMP=$(openstack security group list | grep "${SLAVE_SECURITY_GROUP_NAME}")
if [ -n "${SECURITY_GROUP_TMP}" ]; then
	PRNERR "Already has \"${SLAVE_SECURITY_GROUP_NAME}\" security group for ${OS_USERNAME}."
	exit 1
fi

if ({ openstack security group create --description 'security group for k2hr3 slave node' "${SLAVE_SECURITY_GROUP_NAME}" 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
	PRNERR "Could not create \"${SLAVE_SECURITY_GROUP_NAME}\" security group."
	exit 1
fi

if ({ openstack security group rule create --ingress --ethertype IPv4 --project "${OS_PROJECT_ID}" --dst-port 8031:8031 --protocol tcp --description 'k2hdkc/chmpx slave node control port' "${SLAVE_SECURITY_GROUP_NAME}" 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
	PRNERR "Could not add control port(8031) for k2hdkc/chmpx slave node to \"${SLAVE_SECURITY_GROUP_NAME}\" security group."
	exit 1
fi

if ({ openstack security group rule create --ingress --ethertype IPv4 --project "${OS_PROJECT_ID}" --dst-port 22:22 --protocol tcp --description 'ssh port' "${SLAVE_SECURITY_GROUP_NAME}" 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
	PRNERR "Could not add ssh port(22) for k2hdkc slave node to \"${SLAVE_SECURITY_GROUP_NAME}\" security group."
	exit 1
fi

PRNINFO "Succeed to set security group(k2hdkc-slave-sec) on demo user for K2HDKC slave node."

#----------------------------------------------------------
# Messages
#----------------------------------------------------------
#
# Summary log file
#
K2HDKCSTACK_SUMMARY_LOG="${STACK_USER_HOME}/logs/${SCRIPTNAME}.log"

echo ""
{
	PRNSUCCESS "Finished ${SCRIPTNAME} process without error."
	echo " Base host(openstack trove)  : ${PARENT_HOSTNAME}"
	echo " K2HR3 System(instance name) : ${K2HR3_HOSTNAME}"
	echo "       APP local port        : ${OPT_APP_PORT}"
	echo "       API local port        : ${OPT_API_PORT}"
	echo " K2HR3 Web appliction        : http://${K2HR3_EXTERNAL_HOSTNAME}:${OPT_APP_PORT_EXT}/"
	echo " K2HR3 REST API              : http://${K2HR3_EXTERNAL_HOSTNAME}:${OPT_API_PORT_EXT}/"
	echo ""
} | tee -a "${K2HDKCSTACK_SUMMARY_LOG}"
echo ""

exit 0

#
# Local variables:
# tab-width: 4
# c-basic-offset: 4
# End:
# vim600: noexpandtab sw=4 ts=4 fdm=marker
# vim<600: noexpandtab sw=4 ts=4
#
