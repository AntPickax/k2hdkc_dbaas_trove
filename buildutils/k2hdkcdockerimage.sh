#!/bin/sh
#
# K2HDKC DBaaS based on Trove
#
# Copyright 2024 Yahoo Japan Corporation
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
# CREATE:   Tue May 28 2024
# REVISION:
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
SRCTOPDIR=$(cd "${SCRIPTDIR}"/.. || exit 1; pwd)

#
# Directories
#
SCRIPT_CONFIG_DIR="${SCRIPTDIR}/conf"

#
# Image names
#
IMAGENAME_K2HDKC_TROVE='k2hdkc-trove'
IMAGENAME_K2HDKC_BACKUP='k2hdkc-trove-backup'

#
# Files
#
DOCKER_DAEMON_JSON_FILE="/etc/docker/daemon.json"

K2HDKC_TROVE_DOCKERFILE_NAME="Dockerfile.trove"
K2HDKC_TROVE_DOCKERFILE="${SCRIPTDIR}/${K2HDKC_TROVE_DOCKERFILE_NAME}"
K2HDKC_TROVE_DOCKERFILE_TEMPL="${K2HDKC_TROVE_DOCKERFILE}.templ"

K2HDKC_BACKUP_DOCKERFILE_NAME="Dockerfile.backup"
K2HDKC_BACKUP_DOCKERFILE="${SCRIPTDIR}/${K2HDKC_BACKUP_DOCKERFILE_NAME}"
K2HDKC_BACKUP_DOCKERFILE_TEMPL="${K2HDKC_BACKUP_DOCKERFILE}.templ"

UBUNTU_APT_PROXY_CONFFILE="${SCRIPTDIR}/00-aptproxy.conf"
ALPINE_PIP_CONFFILE="${SCRIPTDIR}/pip.conf"

SUB_PROC_ERROR_LOGFILE="/tmp/.${SCRIPTNAME}.$$.log"

#
# Utility file for Functions and Variables
#
COMMON_UTILS_FUNC_FILE="k2hdkcutilfunc.sh"
DEFAULT_DEVSTACK_BRANCH_FILE="DEFAULT_DEVSTACK_BRANCH"

#
# Default value
#
DEFAULT_REGISTRY=""
DEFAULT_REPOSITORY="antpickax"

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
	echo ""
	echo "${CGRN}[SUCCESS]${CDEF} $*"
}

#--------------------------------------------------------------
# Load common utility functions
#--------------------------------------------------------------
#
# Common functions
#
if [ ! -f "${SCRIPTDIR}/${COMMON_UTILS_FUNC_FILE}" ]; then
	PRNERR "Not found ${SCRIPTDIR}/${COMMON_UTILS_FUNC_FILE} file is not found."
	exit 1
fi
. "${SCRIPTDIR}/${COMMON_UTILS_FUNC_FILE}"

#
# DEVSTACK_BRANCH Variable
#
if [ -z "${DEVSTACK_BRANCH}" ]; then
	if [ ! -f "${SRCTOPDIR}/${DEFAULT_DEVSTACK_BRANCH_FILE}" ]; then
		PRNERR "Not found ${SRCTOPDIR}/${DEFAULT_DEVSTACK_BRANCH_FILE} file is not found."
		exit 1
	fi
	. "${SRCTOPDIR}/${DEFAULT_DEVSTACK_BRANCH_FILE}"
fi

#==============================================================
# Function placeholders for customization
#==============================================================
#
# Control pushing images ( override function )
#
# Output:	ENABLE_PUSH_IMAGE	enable(1)/disable(0: default) push images
#
SetupControlPushImages()
{
	if [ -z "${CI}" ]; then
		ENABLE_PUSH_IMAGE=0
	else
		if echo "${CI}" | grep -q -i "true"; then
			ENABLE_PUSH_IMAGE=1
		else
			ENABLE_PUSH_IMAGE=0
		fi
	fi
	return 0
}

#
# Setup Variables override function
#
# [NOTE]
# You can override following functions for customizing variables
# by configuration file.
#
# Within the overridden function, you can also override variables
# such as "DEFAULT_" and "SETUP_".
#
SetupCustomImageVersionString()
{
	return 0
}

SetupCustomInstallPackagesValueUbuntu()
{
	return 0
}

SetupCustomInstallPackagesValueRocky()
{
	return 0
}

SetupCustomInstallPackagesValueAlpine()
{
	return 0
}

#==============================================================
# Utility : Setup Variables
#==============================================================
#
# Load/Read PROXY Environments
#
# Output:	HTTP_PROXY_VAL				HTTP Proxy with schema
#			HTTPS_PROXY_VAL				HTTPS Proxy with schema
#			HTTP_PROXY_NOSCHIMA_VAL		HTTP Proxy without schema
#			HTTPS_PROXY_NOSCHIMA_VAL	HTTPS Proxy without schema
#			NO_PROXY_VAL				NO Proxy string value
#
LoadEnvironmentValue()
{
	HTTP_PROXY_VAL=""
	HTTPS_PROXY_VAL=""
	HTTP_PROXY_NOSCHIMA_VAL=""
	HTTPS_PROXY_NOSCHIMA_VAL=""
	NO_PROXY_VAL=""

	#
	# Read current PROXY environments
	#
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

	return 0
}

#
# Get PROXY Arguments for building
#
# Input:	OPT_OS_TYPE					OS type
#			HTTP_PROXY_VAL				HTTP Proxy with schema
#			HTTPS_PROXY_VAL				HTTPS Proxy with schema
#			HTTP_PROXY_NOSCHIMA_VAL		HTTP Proxy without schema
#			HTTPS_PROXY_NOSCHIMA_VAL	HTTPS Proxy without schema
#			NO_PROXY_VAL				NO Proxy string value
#
# Output:	BUILD_ARG_HTTP_PROXY		HTTP_PROXY arguments for building
#			BUILD_ARG_HTTPS_PROXY		HTTPS_PROXY arguments for building
#			BUILD_ARG_NO_PROXY			NO_PROXY arguments for building
#
GetProxyArgValue()
{
	if [ "${OPT_OS_TYPE}" = "alpine" ]; then
		if [ -n "${HTTP_PROXY_VAL}" ]; then
			BUILD_ARG_HTTP_PROXY="http_proxy=${HTTP_PROXY_VAL}"
		else
			BUILD_ARG_HTTP_PROXY="http_proxy="
		fi
		if [ -n "${HTTPS_PROXY_VAL}" ]; then
			BUILD_ARG_HTTPS_PROXY="https_proxy=${HTTPS_PROXY_VAL}"
		else
			BUILD_ARG_HTTPS_PROXY="https_proxy="
		fi
	else
		if [ -n "${HTTP_PROXY_NOSCHIMA_VAL}" ]; then
			BUILD_ARG_HTTP_PROXY="http_proxy=${HTTP_PROXY_NOSCHIMA_VAL}"
		else
			BUILD_ARG_HTTP_PROXY="http_proxy="
		fi
		if [ -n "${HTTPS_PROXY_NOSCHIMA_VAL}" ]; then
			BUILD_ARG_HTTPS_PROXY="https_proxy=${HTTPS_PROXY_NOSCHIMA_VAL}"
		else
			BUILD_ARG_HTTPS_PROXY="https_proxy="
		fi
	fi

	if [ -n "${NO_PROXY_VAL}" ]; then
		BUILD_ARG_NO_PROXY="no_proxy=${NO_PROXY_VAL}"
	else
		BUILD_ARG_NO_PROXY="no_proxy="
	fi

	return 0
}

#
# Setup Environments Variables(Other than PROXY)
#
# Input:	OPT_OS_TYPE	OS type
#
# Output:	SETUP_ENV	Sets the string for substitution in
#						the Dockerfile template.
#						This string contains newline characters
#						that can be replaced with the sed command.
#
SetupEnvironmentValue()
{
	#
	# Setup variables
	#
	if [ "${OPT_OS_TYPE}" = "ubuntu" ]; then
		#
		# Example:
		#	ENV DEBIAN_FRONTEND     "noninteractive"
		#
		SETUP_ENV=$(
			printf "ENV DEBIAN_FRONTEND=noninteractive\\\\n"
		)

	elif [ "${OPT_OS_TYPE}" = "rocky9" ]; then
		#
		# Nothing to setup
		#
		SETUP_ENV=""

	elif [ "${OPT_OS_TYPE}" = "alpine" ]; then
		#
		# Nothing to setup
		#
		SETUP_ENV=""
	fi

	return 0
}

#
# Setup PROXY Environments Variables
#
# Input:	OPT_OS_TYPE					OS type
#			OPT_SET_PROXY_ENV			Whether or not the PROXY environment variable can be set
#			HTTP_PROXY_VAL				HTTP Proxy with schema
#			HTTPS_PROXY_VAL				HTTPS Proxy with schema
#			HTTP_PROXY_NOSCHIMA_VAL		HTTP Proxy without schema
#			HTTPS_PROXY_NOSCHIMA_VAL	HTTPS Proxy without schema
#			NO_PROXY_VAL				NO Proxy string value
#
# Output:	SETUP_PROXY_ENV				Sets the string for substitution in
#										the Dockerfile template.
#										This string contains newline characters
#										that can be replaced with the sed command.
#
SetupProxyEnvironmentValue()
{
	SETUP_PROXY_ENV=""

	#
	# Setup variables
	#
	if [ "${OPT_SET_PROXY_ENV}" -ne 0 ]; then
		if [ "${OPT_OS_TYPE}" = "ubuntu" ]; then
			#
			# Set varibales
			#
			# Example:
			#	ENV http_proxy          "<PROXY HOST URL>"
			#	ENV https_proxy         "<PROXY HOST URL>"
			#	ENV HTTP_PROXY          "<PROXY HOST URL>"
			#	ENV HTTPS_PROXY         "<PROXY HOST URL>"
			#	ENV no_proxy            "<FQDN,...>"
			#	ENV NO_PROXY            "<FQDN,...>"
			#
			SETUP_PROXY_ENV=$(
				if [ -n "${HTTP_PROXY_VAL}" ] || [ -n "${HTTPS_PROXY_VAL}" ]; then
					printf "ENV http_proxy=%s\\\\n"		"${HTTP_PROXY_NOSCHIMA_VAL}"
					printf "ENV https_proxy=%s\\\\n"	"${HTTPS_PROXY_NOSCHIMA_VAL}"
					printf "ENV HTTP_PROXY=%s\\\\n"		"${HTTP_PROXY_NOSCHIMA_VAL}"
					printf "ENV HTTPS_PROXY=%s\\\\n"	"${HTTPS_PROXY_NOSCHIMA_VAL}"
				fi
				if [ -n "${NO_PROXY_VAL}" ]; then
					printf "ENV no_proxy=%s\\\\n"		"${NO_PROXY_VAL}"
					printf "ENV NO_PROXY=%s\\\\n"		"${NO_PROXY_VAL}"
				fi
			)

		elif [ "${OPT_OS_TYPE}" = "rocky9" ]; then
			#
			# Set varibales
			#
			# Example:
			#	ENV http_proxy  "<PROXY HOST URL>"
			#	ENV https_proxy "<PROXY HOST URL>"
			#	ENV HTTP_PROXY  "<PROXY HOST URL>"
			#	ENV HTTPS_PROXY "<PROXY HOST URL>"
			#	ENV no_proxy    "<FQDN,...>"
			#	ENV NO_PROXY    "<FQDN,...>"
			#
			SETUP_PROXY_ENV=$(
				if [ -n "${HTTP_PROXY_VAL}" ] || [ -n "${HTTPS_PROXY_VAL}" ]; then
					printf "ENV http_proxy=%s\\\\n"		"${HTTP_PROXY_NOSCHIMA_VAL}"
					printf "ENV https_proxy=%s\\\\n"	"${HTTPS_PROXY_NOSCHIMA_VAL}"
					printf "ENV HTTP_PROXY=%s\\\\n"		"${HTTP_PROXY_NOSCHIMA_VAL}"
					printf "ENV HTTPS_PROXY=%s\\\\n"	"${HTTPS_PROXY_NOSCHIMA_VAL}"
				fi
				if [ -n "${NO_PROXY_VAL}" ]; then
					printf "ENV no_proxy=%s\\\\n"		"${NO_PROXY_VAL}"
					printf "ENV NO_PROXY=%s\\\\n"		"${NO_PROXY_VAL}"
				fi
			)

		elif [ "${OPT_OS_TYPE}" = "alpine" ]; then
			#
			# Set varibales
			#
			# Example:
			#	ENV http_proxy  "http(s)://<PROXY HOST URL>"
			#	ENV https_proxy "http(s)://<PROXY HOST URL>"
			#	ENV HTTP_PROXY  "http(s)://<PROXY HOST URL>"
			#	ENV HTTPS_PROXY "http(s)://<PROXY HOST URL>"
			#	ENV no_proxy    "<FQDN,...>"
			#	ENV NO_PROXY    "<FQDN,...>"
			#
			SETUP_PROXY_ENV=$(
				if [ -n "${HTTP_PROXY_VAL}" ] || [ -n "${HTTPS_PROXY_VAL}" ]; then
					printf "ENV http_proxy=%s\\\\n"		"${HTTP_PROXY_VAL}"
					printf "ENV https_proxy=%s\\\\n"	"${HTTPS_PROXY_VAL}"
					printf "ENV HTTP_PROXY=%s\\\\n"		"${HTTP_PROXY_VAL}"
					printf "ENV HTTPS_PROXY=%s\\\\n"	"${HTTPS_PROXY_VAL}"
				fi
				if [ -n "${NO_PROXY_VAL}" ]; then
					printf "ENV no_proxy=%s\\\\n"		"${NO_PROXY_VAL}"
					printf "ENV NO_PROXY=%s\\\\n"		"${NO_PROXY_VAL}"
				fi
			)
		fi
	fi

	return 0
}

#
# Setup Pre/Pos-process before/after installing packages
#
# Input:	OPT_OS_TYPE					OS type
#			OPT_SET_PROXY_ENV			Whether or not the PROXY environment variable can be set
# 			HTTP_PROXY_VAL				HTTP Proxy with schema
#			HTTPS_PROXY_VAL				HTTPS Proxy with schema
#
# Output:	PRE_PROCESS_BEFORE_INSTALL	Sets pre-process command before installing package.
#			POST_PROCESS_AFTER_INSTALL	Sets post-process command after installing package.
#
SetupPreprocessBeforeInstallValue()
{
	#
	# Setup variables
	#
	PRE_PROCESS_BEFORE_INSTALL=''
	POST_PROCESS_AFTER_INSTALL=':'

	if [ "${OPT_OS_TYPE}" = "ubuntu" ]; then
		if [ -n "${HTTP_PROXY_VAL}" ] || [ -n "${HTTPS_PROXY_VAL}" ]; then
			#
			# Create 00-aptproxy.conf file
			#
			rm -f "${UBUNTU_APT_PROXY_CONFFILE}"
			{
				echo "Acquire::http::Proxy \"${HTTP_PROXY_VAL}\";"
				echo "Acquire::https::Proxy \"${HTTPS_PROXY_VAL}\";"
			} > "${UBUNTU_APT_PROXY_CONFFILE}"

			#
			# Set varibales
			#
			# 	PRE_PROCESS_BEFORE_INSTALL	"COPY ./00-aptproxy.conf /etc/apt/apt.conf.d/00-aptproxy.conf"
			#	POST_PROCESS_AFTER_INSTALL	"rm -f /etc/apt/apt.conf.d/00-aptproxy.conf"
			#
			PRE_PROCESS_BEFORE_INSTALL=$(
				printf "COPY ./00-aptproxy.conf /etc/apt/apt.conf.d/00-aptproxy.conf\\\\n"
			)

			if [ "${OPT_SET_PROXY_ENV}" -eq 0 ]; then
				POST_PROCESS_AFTER_INSTALL=$(
					printf "rm -f /etc/apt/apt.conf.d/00-aptproxy.conf"
				)
			fi
		fi

	elif [ "${OPT_OS_TYPE}" = "rocky9" ]; then
		#
		# Set varibales
		#
		# 	PRE_PROCESS_BEFORE_INSTALL	":"
		#	POST_PROCESS_AFTER_INSTALL	":"
		#
		:

	elif [ "${OPT_OS_TYPE}" = "alpine" ]; then
		#
		# For against error "externally-managed-environment"
		#
		rm -f "${ALPINE_PIP_CONFFILE}"
		{
			echo '[global]'
			echo 'break-system-packages = true'
		} > "${ALPINE_PIP_CONFFILE}"

		#
		# Set varibales
		#
		# 	PRE_PROCESS_BEFORE_INSTALL	"COPY ./pip.conf /root/.config/pip/pip.conf"
		#	POST_PROCESS_AFTER_INSTALL	"rm -f /root/.config/pip/pip.conf"
		#
		PRE_PROCESS_BEFORE_INSTALL=$(
			printf "COPY ./pip.conf /root/.config/pip/pip.conf\\\\n"
		)

		if [ "${OPT_SET_PROXY_ENV}" -eq 0 ]; then
			POST_PROCESS_AFTER_INSTALL=$(
				printf "rm -f /root/.config/pip/pip.conf"
			)
		fi
	fi

	return 0
}

#--------------------------------------------------------------
# Setup Iamage Version String
#--------------------------------------------------------------
# Output Variables:
#	SETUP_K2HDKC_VERSTR					: K2HDKC Base image version string(ex. "1.0.14-ubuntu")
#	SETUP_IMAGE_VERSTR					: Version string(ex. "1.0.0-ubuntu")
#	SETUP_IMAGE_LATEST_VERSTR			: Latest version string(ex. "latest-ubuntu")
#	SETUP_IMAGE_STANDARD_VERSTR			: Standard version string(ex. "1.0.0")
#	SETUP_IMAGE_STANDARD_LATEST_VERSTR	: Standard version string(ex. "latest")
#
SetupImageVersionString()
{
	SETUP_K2HDKC_VERSTR="${SETUP_K2HDKC_VER}-${SETUP_OS_TYPE}"

	SETUP_IMAGE_VERSTR="${SETUP_IMAGE_VER}-${SETUP_OS_TYPE}"
	SETUP_IMAGE_LATEST_VERSTR="latest-${SETUP_OS_TYPE}"

	if [ -n "${SETUP_OS_TYPE}" ] && [ "${SETUP_OS_TYPE}" = "alpine" ]; then
		SETUP_IMAGE_STANDARD_VERSTR="${SETUP_IMAGE_VER}"
		SETUP_IMAGE_STANDARD_LATEST_VERSTR="latest"
	else
		SETUP_IMAGE_STANDARD_VERSTR=""
		SETUP_IMAGE_STANDARD_LATEST_VERSTR=""
	fi

	if ! SetupCustomImageVersionString; then
		return 1
	fi
	return 0
}

#--------------------------------------------------------------
# Setup install packages variables for Ubuntu
#--------------------------------------------------------------
# Output Variables(example):
#	PRE_PKG_UPDATE			';'
#	PKG_UPDATE				'apt-get update -y -qq --no-install-recommends --allow-unauthenticated'
#	PRE_COMMON_PKG_INSTALL	':'
#	COMMON_PKG_INSTALL		'apt-get install -y -qq --no-install-recommends --allow-unauthenticated curl sudo'
#	POST_COMMON_PKG_INSTALL	':'
#	PRE_PKG_INSTALL			'curl -s https://packagecloud.io/install/repositories/antpickax/stable/script.deb.sh \| bash'
#	PKG_INSTALL				'apt-get install -y -qq --no-install-recommends --allow-unauthenticated k2hr3-get-resource k2hdkc-dbaas-override-conf'
#	POST_PKG_INSTALL		'sed -i -e 's#k2hdkc-service-helper.conf:WAIT_DEPENDPROC_PIDFILE[[:space:]]*.*#k2hdkc-service-helper.conf:WAIT_DEPENDPROC_PIDFILE = #g' /etc/antpickax/override.conf && echo "k2hr3-get-resource-helper.conf:USE_DAEMON = false" >> /etc/antpickax/override.conf && sed -i -e "s#SUBPROCESS_USER[[:space:]]*=[[:space:]]*k2hdkc#SUBPROCESS_USER = database#g" /etc/antpickax/override.conf &&'
#	PRE_SETUP_USER			':'
#	SETUP_USER				'groupadd -g "${ADD_GID}" -o "${ADD_UNAME}" &&
#							 useradd --no-log-init -r -M --shell /usr/sbin/nologin -d /nonexistent -u "${ADD_UID}" -g "${ADD_GID}" "${ADD_UNAME}" 2>/dev/null'
#	POST_SETUP_USER			'echo "database ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/50-database &&
#							 echo "Defaults:database env_keep += \"http_proxy https_proxy no_proxy HTTP_PROXY HTTPS_PROXY NO_PROXY\"" >> /etc/sudoers.d/50-database'
#	PRE_BACKUP_PKG_INSTALL	':'
#	BACKUP_PKG_INSTALL		'apt-get install -y -qq --no-install-recommends --allow-unauthenticated lsb-release'
#	POST_BACKUP_PKG_INSTALL	':'
#	PIP_PKG_INSTALL			'apt-get install -y -qq --no-install-recommends --allow-unauthenticated build-essential python3-pip python3-dev && python3 -m pip config set global.break-system-packages true'
#	PIP_INSTALL				'pip3 --no-cache-dir (--proxy=....) install -U -r /opt/trove/backup/requirements.txt'
#	POST_PIP_INSTALL		'curl -sSL https://github.com/Yelp/dumb-init/releases/download/v1.2.2/dumb-init_1.2.2_amd64 -o /usr/local/bin/dumb-init && chmod +x /usr/local/bin/dumb-init'
#
SetupInstallPackagesValueUbuntu()
{
	#
	# For package manager
	#
	PKGMAN_BIN="apt-get"
	PKGMAN_UPDATE_COMMAND="update"
	PKGMAN_INSTALL_COMMAND="install"
	PKGMAN_UPDATE_ARGS="-y -qq --no-install-recommends --allow-unauthenticated"
	PKGMAN_INSTALL_ARGS="-y -qq --no-install-recommends --allow-unauthenticated"

	#
	# Install packages
	#
	INSTALL_COMMON_PKGS="curl sudo"
	INSTALL_FOR_K2HDKC_PKGS="k2hr3-get-resource k2hdkc-dbaas-override-conf"
	INSTALL_FOR_BACKUP_PKGS="lsb-release"
	INSTALL_FOR_PIP3="build-essential python3-pip python3-dev"

	#
	# For common packages
	#
	# Example:
	#	apt-get update -y -qq --no-install-recommends --allow-unauthenticated
	#	apt-get install -y -qq --no-install-recommends --allow-unauthenticated curl sudo
	#
	PRE_PKG_UPDATE=":"
	PKG_UPDATE="${PKGMAN_BIN} ${PKGMAN_UPDATE_COMMAND} ${PKGMAN_UPDATE_ARGS}"
	PRE_COMMON_PKG_INSTALL=":"
	COMMON_PKG_INSTALL="${PKGMAN_BIN} ${PKGMAN_INSTALL_COMMAND} ${PKGMAN_INSTALL_ARGS} ${INSTALL_COMMON_PKGS}"
	POST_COMMON_PKG_INSTALL=":"

	#
	# For packages related to K2HDKC
	#
	PRE_PKG_INSTALL="curl -s https://packagecloud.io/install/repositories/antpickax/stable/script.deb.sh \\| bash"
	PKG_INSTALL="${PKGMAN_BIN} ${PKGMAN_INSTALL_COMMAND} ${PKGMAN_INSTALL_ARGS} ${INSTALL_FOR_K2HDKC_PKGS}"
	POST_PKG_INSTALL="sed -i -e 's#k2hdkc-service-helper.conf:WAIT_DEPENDPROC_PIDFILE[[:space:]]*.*#k2hdkc-service-helper.conf:WAIT_DEPENDPROC_PIDFILE = #g' /etc/antpickax/override.conf \\&\\& echo \"k2hr3-get-resource-helper.conf:USE_DAEMON = false\" >> /etc/antpickax/override.conf \\&\\& echo \"chmpx-service-helper.conf:LOGDIR = /var/log/antpickax\" >> /etc/antpickax/override.conf \\&\\& echo \"chmpx-service-helper.conf:SERVICE_LOGFILE = chmpx-service-helper.log\" >> /etc/antpickax/override.conf \\&\\& echo \"chmpx-service-helper.conf:SUBPROCESS_LOGFILE = chmpx.log\" >> /etc/antpickax/override.conf \\&\\& sed -i -e \"s#SUBPROCESS_USER[[:space:]]*=[[:space:]]*k2hdkc#SUBPROCESS_USER = database#g\" /etc/antpickax/override.conf \\&\\& ${POST_PROCESS_AFTER_INSTALL}"

	#
	# For adding user
	#
	PRE_SETUP_USER=":"
	SETUP_USER=$(
		printf "groupadd -g \"\${ADD_GID}\" -o \"\${ADD_UNAME}\" \\&\\& "
		printf "useradd --no-log-init -r -M --shell /usr/sbin/nologin -d /nonexistent -u \"\${ADD_UID}\" -g \"\${ADD_GID}\" \"\${ADD_UNAME}\" 2>/dev/null"
	)
	POST_SETUP_USER=$(
		printf "echo \"database ALL=(ALL) NOPASSWD:ALL\" >> /etc/sudoers.d/50-database \\&\\& "
		printf "echo 'Defaults:database env_keep += \"http_proxy https_proxy no_proxy HTTP_PROXY HTTPS_PROXY NO_PROXY\"' >> /etc/sudoers.d/50-database"
	)

	#
	# For backup image's packages
	#
	PRE_BACKUP_PKG_INSTALL=':'
	BACKUP_PKG_INSTALL="${PKGMAN_BIN} ${PKGMAN_INSTALL_COMMAND} ${PKGMAN_INSTALL_ARGS} ${INSTALL_FOR_BACKUP_PKGS}"
	POST_BACKUP_PKG_INSTALL=':'
	POST_PIP_INSTALL="curl -sSL https://github.com/Yelp/dumb-init/releases/download/v1.2.2/dumb-init_1.2.2_amd64 -o /usr/local/bin/dumb-init \\&\\& chmod +x /usr/local/bin/dumb-init \\&\\& ${POST_PROCESS_AFTER_INSTALL}"

	#
	# pip3 packages
	#
	# [NOTE]
	# In Ubuntu:24.04 and later images, you need to use venv when installing packages with pip3.
	# However, we are concerned about setting the container entrypoint to venv, and want to
	# simplify things, so we will make the following settings to avoid this warning(error).
	#
	PIP_GLOBAL_BREAK_SYSTEM_PKG_COMMAND='python3 -m pip config set global.break-system-packages true'
	PIP_PKG_INSTALL="${PKGMAN_BIN} ${PKGMAN_INSTALL_COMMAND} ${PKGMAN_INSTALL_ARGS} ${INSTALL_FOR_PIP3} \\&\\& ${PIP_GLOBAL_BREAK_SYSTEM_PKG_COMMAND}"

	#
	# install pip packages
	#
	# [NOTE] Specifying HTTP(S)_PROXY
	# The HTTP(S)_PROXY environment variable does not have a Schema.
	# The pip command requires a Schema. It can also be specified with the
	# --proxy option, but the environment variable seems to take precedence.
	# So, we will run the pip command with the --proxy option specified,
	# but we will clear the HTTP(S)_PROXY environment variable before
	# running it.
	#
	if [ -n "${HTTP_PROXY_VAL}" ] || [ -n "${HTTPS_PROXY_VAL}" ]; then
		if [ -n "${HTTP_PROXY_VAL}" ]; then
			_EXIST_PROXY="${HTTP_PROXY_VAL}"
		else
			_EXIST_PROXY="${HTTPS_PROXY_VAL}"
		fi
		PIP_INSTALL="/bin/sh -c \"unset HTTP_PROXY; unset HTTPS_PROXY; unset http_proxy; unset https_proxy; pip3 --no-cache-dir --proxy=${_EXIST_PROXY} install -U -r /opt/trove/backup/requirements.txt\""
	else
		PIP_INSTALL='pip3 --no-cache-dir install -U -r /opt/trove/backup/requirements.txt'
	fi

	#
	# Customize varibales
	#
	if ! SetupCustomInstallPackagesValueUbuntu; then
		PRNERR "Failed to customizing variables for install packages on Ubuntu."
		return 1
	fi
	return 0
}

#--------------------------------------------------------------
# Setup install packages variables for Rocky
#--------------------------------------------------------------
# Output Variables(example):
#	PRE_PKG_UPDATE			';'
#	PKG_UPDATE				'dnf update -y -q'
#	PRE_COMMON_PKG_INSTALL	':'
#	COMMON_PKG_INSTALL		'dnf install -y -q curl sudo'
#	POST_COMMON_PKG_INSTALL	':'
#	PRE_PKG_INSTALL			'curl -s https://packagecloud.io/install/repositories/antpickax/stable/script.rpm.sh \| sudo bash'
#	PKG_INSTALL				'dnf -y -q k2hr3-get-resource k2hdkc-dbaas-override-conf'
#	POST_PKG_INSTALL		'sed -i -e 's#k2hdkc-service-helper.conf:WAIT_DEPENDPROC_PIDFILE[[:space:]]*.*#k2hdkc-service-helper.conf:WAIT_DEPENDPROC_PIDFILE = #g' /etc/antpickax/override.conf && echo "k2hr3-get-resource-helper.conf:USE_DAEMON = false" >> /etc/antpickax/override.conf && sed -i -e "s#SUBPROCESS_USER[[:space:]]*=[[:space:]]*k2hdkc#SUBPROCESS_USER = database#g" /etc/antpickax/override.conf &&'
#	PRE_SETUP_USER			':'
#	SETUP_USER				'groupadd -g "${ADD_GID}" -o "${ADD_UNAME}" &&
#							 useradd --no-log-init -r -M --shell /usr/sbin/nologin -d /nonexistent -u "${ADD_UID}" -g "${ADD_GID}" "${ADD_UNAME}" 2>/dev/null'
#	POST_SETUP_USER			'echo "database ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/50-database &&
#							 echo "Defaults:database env_keep += \"http_proxy https_proxy no_proxy HTTP_PROXY HTTPS_PROXY NO_PROXY\"" >> /etc/sudoers.d/50-database'
#	PRE_BACKUP_PKG_INSTALL	'dnf -y -q epel-release && dnf clean all'
#	BACKUP_PKG_INSTALL		'dnf -y -q lsb-release'
#	POST_BACKUP_PKG_INSTALL	':'
#	PIP_PKG_INSTALL			'dnf -y -q python3-pip'
#	PIP_INSTALL				'pip3 --no-cache-dir (--proxy=....) install -U -r /opt/trove/backup/requirements.txt'
#	POST_PIP_INSTALL		'curl -sSL https://github.com/Yelp/dumb-init/releases/download/v1.2.2/dumb-init_1.2.2_amd64 -o /usr/local/bin/dumb-init && chmod +x /usr/local/bin/dumb-init'
#
SetupInstallPackagesValueRocky()
{
	#
	# For package manager
	#
	PKGMAN_BIN="dnf"
	PKGMAN_UPDATE_COMMAND="update"
	PKGMAN_INSTALL_COMMAND="install"
	PKGMAN_UPDATE_ARGS="-y --nobest --skip-broken -q"
	PKGMAN_INSTALL_ARGS="-y -q"

	#
	# Install packages
	#
	INSTALL_COMMON_PKGS="curl-minimal sudo"
	INSTALL_FOR_K2HDKC_PKGS="k2hr3-get-resource k2hdkc-dbaas-override-conf"
	INSTALL_FOR_BACKUP_PKGS="lsb-release"
	INSTALL_FOR_PIP3="python3-pip"

	#
	# For common packages
	#
	# Example:
	#	dnf update -y -q
	#	dnf install -y -q curl sudo
	#
	PRE_PKG_UPDATE=":"
	PKG_UPDATE="${PKGMAN_BIN} ${PKGMAN_UPDATE_COMMAND} ${PKGMAN_UPDATE_ARGS}"
	PRE_COMMON_PKG_INSTALL=":"
	COMMON_PKG_INSTALL="${PKGMAN_BIN} ${PKGMAN_INSTALL_COMMAND} ${PKGMAN_INSTALL_ARGS} ${INSTALL_COMMON_PKGS}"
	POST_COMMON_PKG_INSTALL=":"

	#
	# For packages related to K2HDKC
	#
	PRE_PKG_INSTALL="curl -s https://packagecloud.io/install/repositories/antpickax/stable/script.rpm.sh \\| sudo bash"
	PKG_INSTALL="${PKGMAN_BIN} ${PKGMAN_INSTALL_COMMAND} ${PKGMAN_INSTALL_ARGS} ${INSTALL_FOR_K2HDKC_PKGS}"
	POST_PKG_INSTALL="sed -i -e 's#k2hdkc-service-helper.conf:WAIT_DEPENDPROC_PIDFILE[[:space:]]*.*#k2hdkc-service-helper.conf:WAIT_DEPENDPROC_PIDFILE = #g' /etc/antpickax/override.conf \\&\\& echo \"k2hr3-get-resource-helper.conf:USE_DAEMON = false\" >> /etc/antpickax/override.conf \\&\\& sed -i -e \"s#SUBPROCESS_USER[[:space:]]*=[[:space:]]*k2hdkc#SUBPROCESS_USER = database#g\" /etc/antpickax/override.conf \\&\\& ${POST_PROCESS_AFTER_INSTALL}"

	#
	# For adding user
	#
	PRE_SETUP_USER=":"
	SETUP_USER=$(
		printf "groupadd -g \"\${ADD_GID}\" -o \"\${ADD_UNAME}\" \\&\\& "
		printf "useradd --no-log-init -r -M --shell /usr/sbin/nologin -d /nonexistent -u \"\${ADD_UID}\" -g \"\${ADD_GID}\" \"\${ADD_UNAME}\" 2>/dev/null"
	)
	POST_SETUP_USER=$(
		printf "echo \"database ALL=(ALL) NOPASSWD:ALL\" >> /etc/sudoers.d/50-database \\&\\& "
		printf "echo 'Defaults:database env_keep += \"http_proxy https_proxy no_proxy HTTP_PROXY HTTPS_PROXY NO_PROXY\"' >> /etc/sudoers.d/50-database"
	)

	#
	# For backup image's packages
	#
	# [NOTE]
	# Need to add epel repository for installing lsb-release
	#
	PRE_BACKUP_PKG_INSTALL="${PKGMAN_BIN} ${PKGMAN_INSTALL_COMMAND} ${PKGMAN_INSTALL_ARGS} epel-release \&\& ${PKGMAN_BIN} clean all"
	BACKUP_PKG_INSTALL="${PKGMAN_BIN} ${PKGMAN_INSTALL_COMMAND} ${PKGMAN_INSTALL_ARGS} ${INSTALL_FOR_BACKUP_PKGS}"
	POST_BACKUP_PKG_INSTALL=':'
	POST_PIP_INSTALL="curl -sSL https://github.com/Yelp/dumb-init/releases/download/v1.2.2/dumb-init_1.2.2_amd64 -o /usr/local/bin/dumb-init \\&\\& chmod +x /usr/local/bin/dumb-init \\&\\& ${POST_PROCESS_AFTER_INSTALL}"

	#
	# pip3 packages
	#
	PIP_PKG_INSTALL="${PKGMAN_BIN} ${PKGMAN_INSTALL_COMMAND} ${PKGMAN_INSTALL_ARGS} ${INSTALL_FOR_PIP3}"

	#
	# install pip packages
	#
	# [NOTE] Specifying HTTP(S)_PROXY
	# The HTTP(S)_PROXY environment variable does not have a Schema.
	# The pip command requires a Schema. It can also be specified with the
	# --proxy option, but the environment variable seems to take precedence.
	# So, we will run the pip command with the --proxy option specified,
	# but we will clear the HTTP(S)_PROXY environment variable before
	# running it.
	#
	if [ -n "${HTTP_PROXY_VAL}" ] || [ -n "${HTTPS_PROXY_VAL}" ]; then
		if [ -n "${HTTP_PROXY_VAL}" ]; then
			_EXIST_PROXY="${HTTP_PROXY_VAL}"
		else
			_EXIST_PROXY="${HTTPS_PROXY_VAL}"
		fi
		PIP_INSTALL="/bin/sh -c \"unset HTTP_PROXY; unset HTTPS_PROXY; unset http_proxy; unset https_proxy; pip3 --no-cache-dir --proxy=${_EXIST_PROXY} install -U -r /opt/trove/backup/requirements.txt\""
	else
		PIP_INSTALL='pip3 --no-cache-dir install -U -r /opt/trove/backup/requirements.txt'
	fi

	#
	# Customize varibales
	#
	if ! SetupCustomInstallPackagesValueRocky; then
		PRNERR "Failed to customizing variables for install packages on Rocky."
		return 1
	fi
	return 0
}

#--------------------------------------------------------------
# Setup install packages variables for Alpine
#--------------------------------------------------------------
# Output Variables(example):
#	PRE_PKG_UPDATE			';'
#	PKG_UPDATE				'apk update -q --no-progress'
#	PRE_COMMON_PKG_INSTALL	':'
#	COMMON_PKG_INSTALL		'apk add --no-progress --no-cache curl sudo'
#	POST_COMMON_PKG_INSTALL	':'
#	PRE_PKG_INSTALL			'curl -s https://packagecloud.io/install/repositories/antpickax/stable/script.alpine.sh \| sh'
#	PKG_INSTALL				'apk add --no-progress --no-cache k2hr3-get-resource k2hdkc-dbaas-override-conf'
#	POST_PKG_INSTALL		'sed -i -e 's#k2hdkc-service-helper.conf:WAIT_DEPENDPROC_PIDFILE[[:space:]]*.*#k2hdkc-service-helper.conf:WAIT_DEPENDPROC_PIDFILE = #g' /etc/antpickax/override.conf && echo "k2hr3-get-resource-helper.conf:USE_DAEMON = false" >> /etc/antpickax/override.conf && sed -i -e "s#SUBPROCESS_USER[[:space:]]*=[[:space:]]*k2hdkc#SUBPROCESS_USER = database#g" /etc/antpickax/override.conf &&'
#	PRE_SETUP_USER			':'
#	SETUP_USER				'addgroup -g "${ADD_GID}" "${ADD_UNAME}" &&
#							 adduser -s /usr/sbin/nologin -h /nonexistent -S -H -u "${ADD_UID}" -G "${ADD_UNAME}" "${ADD_UNAME}" 2>/dev/null'
#	POST_SETUP_USER			'echo "database ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/50-database &&
#							 echo "Defaults:database env_keep += \"http_proxy https_proxy no_proxy HTTP_PROXY HTTPS_PROXY NO_PROXY\"" >> /etc/sudoers.d/50-database'
#	PRE_BACKUP_PKG_INSTALL	':'
#	BACKUP_PKG_INSTALL		'apk add --no-progress --no-cache bash lsb-release-minimal'
#	POST_BACKUP_PKG_INSTALL	':'
#	PIP_PKG_INSTALL			'apk add --no-progress --no-cache build-base py3-pip python3-dev linux-headers'
#	PIP_INSTALL				'pip3 --no-cache-dir install -U -r /opt/trove/backup/requirements.txt'
#	POST_PIP_INSTALL		'curl -sSL https://github.com/Yelp/dumb-init/releases/download/v1.2.2/dumb-init_1.2.2_amd64 -o /usr/local/bin/dumb-init && chmod +x /usr/local/bin/dumb-init'
#
SetupInstallPackagesValueAlpine()
{
	#
	# For package manager
	#
	PKGMAN_BIN="apk"
	PKGMAN_UPDATE_COMMAND="update"
	PKGMAN_INSTALL_COMMAND="add"
	PKGMAN_UPDATE_ARGS="-q --no-progress"
	PKGMAN_INSTALL_ARGS="--no-progress --no-cache"

	#
	# Install packages
	#
	# [NOTE]
	# Need to install the gcc and related headers packages because
	# some python pip packages require building during installation.
	# (build-base, python3-dev, linux-headers)
	#
	# When debugging, list the packages here: "vim iputils-ping bind-tools traceroute"
	#
	INSTALL_COMMON_PKGS="curl sudo procps coreutils"
	INSTALL_FOR_K2HDKC_PKGS="k2hr3-get-resource k2hdkc-dbaas-override-conf"
	INSTALL_FOR_BACKUP_PKGS="bash lsb-release-minimal"
	INSTALL_FOR_PIP3="build-base py3-pip python3-dev linux-headers"

	#
	# For common packages
	#
	# Example:
	#	dnf update -y -q
	#	dnf install -y -q curl sudo
	#
	PRE_PKG_UPDATE=":"
	PKG_UPDATE="${PKGMAN_BIN} ${PKGMAN_UPDATE_COMMAND} ${PKGMAN_UPDATE_ARGS}"
	PRE_COMMON_PKG_INSTALL=":"
	COMMON_PKG_INSTALL="${PKGMAN_BIN} ${PKGMAN_INSTALL_COMMAND} ${PKGMAN_INSTALL_ARGS} ${INSTALL_COMMON_PKGS}"
	POST_COMMON_PKG_INSTALL=":"

	#
	# For packages related to K2HDKC
	#
	PRE_PKG_INSTALL="curl -s https://packagecloud.io/install/repositories/antpickax/stable/script.alpine.sh \\| sh"
	PKG_INSTALL="${PKGMAN_BIN} ${PKGMAN_INSTALL_COMMAND} ${PKGMAN_INSTALL_ARGS} ${INSTALL_FOR_K2HDKC_PKGS}"
	POST_PKG_INSTALL="sed -i -e 's#k2hdkc-service-helper.conf:WAIT_DEPENDPROC_PIDFILE[[:space:]]*.*#k2hdkc-service-helper.conf:WAIT_DEPENDPROC_PIDFILE = #g' /etc/antpickax/override.conf \\&\\& echo \"k2hr3-get-resource-helper.conf:USE_DAEMON = false\" >> /etc/antpickax/override.conf \\&\\& sed -i -e \"s#SUBPROCESS_USER[[:space:]]*=[[:space:]]*k2hdkc#SUBPROCESS_USER = database#g\" /etc/antpickax/override.conf \\&\\& ${POST_PROCESS_AFTER_INSTALL}"

	#
	# For adding user
	#
	# [NOTE]
	# adduser's "-G" option needs group name(not gid), so we specify group name(=ADD_UNAME)
	#
	PRE_SETUP_USER=":"
	SETUP_USER=$(
		printf "addgroup -g \"\${ADD_GID}\" \"\${ADD_UNAME}\" \\&\\& "
		printf "adduser -s /usr/sbin/nologin -h /nonexistent -S -H -u \"\${ADD_UID}\" -G \"\${ADD_UNAME}\" \"\${ADD_UNAME}\" 2>/dev/null"
	)
	POST_SETUP_USER=$(
		printf "echo \"database ALL=(ALL) NOPASSWD:ALL\" >> /etc/sudoers.d/50-database \\&\\& "
		printf "echo 'Defaults:database env_keep += \"http_proxy https_proxy no_proxy HTTP_PROXY HTTPS_PROXY NO_PROXY\"' >> /etc/sudoers.d/50-database"
	)

	#
	# For backup image's packages
	#
	PRE_BACKUP_PKG_INSTALL=':'
	BACKUP_PKG_INSTALL="${PKGMAN_BIN} ${PKGMAN_INSTALL_COMMAND} ${PKGMAN_INSTALL_ARGS} ${INSTALL_FOR_BACKUP_PKGS}"
	POST_BACKUP_PKG_INSTALL=':'
	POST_PIP_INSTALL="curl -sSL https://github.com/Yelp/dumb-init/releases/download/v1.2.2/dumb-init_1.2.2_amd64 -o /usr/local/bin/dumb-init \\&\\& chmod +x /usr/local/bin/dumb-init \\&\\& ${POST_PROCESS_AFTER_INSTALL}"

	#
	# pip3 packages
	#
	PIP_PKG_INSTALL="${PKGMAN_BIN} ${PKGMAN_INSTALL_COMMAND} ${PKGMAN_INSTALL_ARGS} ${INSTALL_FOR_PIP3}"

	#
	# install pip packages
	#
	# [NOTE] Specifying HTTP(S)_PROXY
	# The PROXY environment variable set in ALPINE has a schema assigned to it.
	# Therefore, there is no need to unset the PROXY environment variable as
	# you would with other OS.
	# Doing so may cause the installation of the PIP package to fail.
	#
	PIP_INSTALL='pip3 --no-cache-dir install -U -r /opt/trove/backup/requirements.txt'

	#
	# Customize varibales
	#
	if ! SetupCustomInstallPackagesValueAlpine; then
		PRNERR "Failed to customizing variables for install packages on Alpine."
		return 1
	fi
	return 0
}

#--------------------------------------------------------------
# Setup install packages variables
#--------------------------------------------------------------
# Argument Variables:
#	BUILD_ARG_HTTP_PROXY
#	BUILD_ARG_HTTPS_PROXY
#	BUILD_ARG_NO_PROXY
#
# Output Variables:
#	SETUP_ENV
#	SETUP_PROXY_ENV
#	PRE_PROCESS_BEFORE_INSTALL
#	POST_PROCESS_AFTER_INSTALL
#	PRE_PKG_UPDATE
#	PKG_UPDATE
#	PRE_COMMON_PKG_INSTALL
#	COMMON_PKG_INSTALL
#	POST_COMMON_PKG_INSTALL
#	PRE_PKG_INSTALL
#	PKG_INSTALL
#	POST_PKG_INSTALL
#	PRE_SETUP_USER
#	SETUP_USER
#	POST_SETUP_USER
#	PRE_BACKUP_PKG_INSTALL
#	BACKUP_PKG_INSTALL
#	POST_BACKUP_PKG_INSTALL
#	PIP_PKG_INSTALL
#	PIP_INSTALL
#	POST_PIP_INSTALL
#
SetupVariables()
{
	#
	# For Build arguments
	#
	if ! LoadEnvironmentValue; then
		return 1
	fi
	if ! GetProxyArgValue; then
		return 1
	fi

	#
	# For environments (%%SETUP_ENV%%)
	#
	if ! SetupEnvironmentValue; then
		return 1
	fi

	#
	# For environments (%%SETUP_PROXY_ENV%%)
	#
	if ! SetupProxyEnvironmentValue; then
		return 1
	fi

	#
	# Pre/Post-process before/after installing packages
	#
	#	Set Variables:	PRE_PROCESS_BEFORE_INSTALL
	#					POST_PROCESS_AFTER_INSTALL
	#
	if ! SetupPreprocessBeforeInstallValue; then
		return 1
	fi

	#
	# Setup variables for install packages
	#
	if [ "${OPT_OS_TYPE}" = "ubuntu" ]; then
		if ! SetupInstallPackagesValueUbuntu; then
			return 1
		fi
	elif [ "${OPT_OS_TYPE}" = "rocky9" ]; then
		if ! SetupInstallPackagesValueRocky; then
			return 1
		fi
	elif [ "${OPT_OS_TYPE}" = "alpine" ]; then
		if ! SetupInstallPackagesValueAlpine; then
			return 1
		fi
	fi

	return 0
}

#==============================================================
# Utility : Setup and Remove Images
#==============================================================
#
# Setup daemon.json file
#
SetupDockerDaemonJsonFile()
{
	_TMP_SETUP_BASE_REGISTRY=$(echo "${SETUP_BASE_REGISTRY}" | sed -e 's#[[:space:]]*/[[:space:]]*$##g')
	_TMP_SETUP_PUSH_REGISTRY=$(echo "${SETUP_PUSH_REGISTRY}" | sed -e 's#[[:space:]]*/[[:space:]]*$##g')

	if [ -z "${_TMP_SETUP_BASE_REGISTRY}" ] && [ -z "${_TMP_SETUP_PUSH_REGISTRY}" ]; then
		PRNINFO "Do not need to add inscure registry to ${DOCKER_DAEMON_JSON_FILE} file."
		return 0
	fi

	#----------------------------------------------------------
	# For base docker registry
	#----------------------------------------------------------
	#
	# Check existed daemon.json file
	#
	if [ -f "${DOCKER_DAEMON_JSON_FILE}" ]; then
		#
		# Get all 'insecure-registries' values in daemon.json
		#
		# ex.)
		#	{
		#		"insecure-registries" : ["myregistry1:8080", "myregistry2"]
		#	}
		#
		if grep -q -i 'insecure-registries' "${DOCKER_DAEMON_JSON_FILE}"; then
			#
			# daemon.json has insecure-registries field.
			#
			_TMP_REGISTRY_SERVERS=$(tr '\t\n' ' ' < "${DOCKER_DAEMON_JSON_FILE}" | sed -e 's|^.*insecure-registries["]*[[:space:]]*\:[[:space:]]*\[||gi' -e 's|\].*$||g' -e 's|,| |g')

			#
			# Check server in insecure-registries list
			#
			if [ -z "${_TMP_SETUP_BASE_REGISTRY}" ]; then
				FOUND_BASE_REGISTRY=1
			else
				FOUND_BASE_REGISTRY=0
			fi
			if [ -z "${_TMP_SETUP_PUSH_REGISTRY}" ]; then
				FOUND_PUSH_REGISTRY=1
			else
				FOUND_PUSH_REGISTRY=0
			fi

			LASTEST_SERVER=""
			for _registries in ${_TMP_REGISTRY_SERVERS}; do
				_tmp_registries=$(echo "${_registries}" | sed -e 's#"##g')
				_tmp_found=0
				if [ -n "${_TMP_SETUP_BASE_REGISTRY}" ] && [ "${_tmp_registries}" = "${_TMP_SETUP_BASE_REGISTRY}" ]; then
					PRNINFO "Found ${_TMP_SETUP_BASE_REGISTRY} in insecure-registries field in ${DOCKER_DAEMON_JSON_FILE} file, so nothing to add."
					FOUND_BASE_REGISTRY=1
					_tmp_found=1
				fi
				if [ -n "${_TMP_SETUP_PUSH_REGISTRY}" ] && [ "${_tmp_registries}" = "${_TMP_SETUP_PUSH_REGISTRY}" ]; then
					PRNINFO "Found ${_TMP_SETUP_PUSH_REGISTRY} in insecure-registries field in ${DOCKER_DAEMON_JSON_FILE} file, so nothing to add."
					FOUND_PUSH_REGISTRY=1
					_tmp_found=1
				fi
				if [ "${_tmp_found}" -eq 0 ]; then
					LASTEST_SERVER="${_tmp_registries}"
				fi
			done

			#
			# Add registry server
			#
			if [ "${FOUND_BASE_REGISTRY}" -eq 1 ] && [ "${FOUND_PUSH_REGISTRY}" -eq 1 ]; then
				#
				# Already both registry, so nothing to do
				#
				return 0
			elif [ "${FOUND_BASE_REGISTRY}" -eq 0 ] && [ "${FOUND_PUSH_REGISTRY}" -eq 1 ]; then
				_ADD_REGISTRY="\"${_TMP_SETUP_BASE_REGISTRY}"
			elif [ "${FOUND_BASE_REGISTRY}" -eq 1 ] && [ "${FOUND_PUSH_REGISTRY}" -eq 0 ]; then
				_ADD_REGISTRY="\"${_TMP_SETUP_PUSH_REGISTRY}"
			else
				if [ "${_TMP_SETUP_BASE_REGISTRY}" = "${_TMP_SETUP_PUSH_REGISTRY}" ]; then
					_ADD_REGISTRY="\"${_TMP_SETUP_BASE_REGISTRY}"
				else
					_ADD_REGISTRY="\"${_TMP_SETUP_BASE_REGISTRY}\", \"${_TMP_SETUP_PUSH_REGISTRY}"
				fi
			fi
			if [ -n "${LASTEST_SERVER}" ]; then
				if ! /bin/sh -c "${SUDO_CMD} sed -i -e 's|${LASTEST_SERVER}|${LASTEST_SERVER}\", ${_ADD_REGISTRY}|g' ${DOCKER_DAEMON_JSON_FILE} 2> ${SUB_PROC_ERROR_LOGFILE}"; then
					PRNERR "Failed to add \"${_ADD_REGISTRY}\" as insecure registry to ${DOCKER_DAEMON_JSON_FILE} file :"
					sed -e 's|^|        |g' "${SUB_PROC_ERROR_LOGFILE}"
					rm -f "${SUB_PROC_ERROR_LOGFILE}"
					return 1
				fi
				rm -f "${SUB_PROC_ERROR_LOGFILE}"

			else
				_FLAT_DAEMON_JSON=$(tr '\t\n' ' ' < "${DOCKER_DAEMON_JSON_FILE}" | sed -e "s|[\"]*insecure-registries[\"]*[[:space:]]*\:[[:space:]]*\[|\"insecure-registries\" : [${_ADD_REGISTRY}\"|gi")

				if ! /bin/sh -c "${SUDO_CMD} cp /dev/null ${DOCKER_DAEMON_JSON_FILE}" || ! echo "${_FLAT_DAEMON_JSON}" | /bin/sh -c "${SUDO_CMD} tee -a ${DOCKER_DAEMON_JSON_FILE} >/dev/null"; then
					PRNERR "Failed to add ${_TMP_SETUP_BASE_REGISTRY} as insecure registry to ${DOCKER_DAEMON_JSON_FILE} file."
					return 1
				fi
			fi

		else
			#
			# daemon.json does not have insecure-registries field.
			#
			_ADD_REGISTRY="${_TMP_SETUP_BASE_REGISTRY}"
			if [ -z "${_ADD_REGISTRY}" ]; then
				_ADD_REGISTRY="${_TMP_SETUP_PUSH_REGISTRY}"
			elif [ -n "${_TMP_SETUP_PUSH_REGISTRY}" ]; then
				_ADD_REGISTRY="${_ADD_REGISTRY}\", \"${_TMP_SETUP_PUSH_REGISTRY}"
			fi

			_TMP_DAEMON_JSON_CONTENTS=$(tr '\t\n' ' ' < "${DOCKER_DAEMON_JSON_FILE}" | sed -e 's|[[:space:]]*||g' -e 's|^{||g' -e 's|}$||g')
			if [ -n "${_TMP_DAEMON_JSON_CONTENTS}" ]; then
				_FLAT_DAEMON_JSON=$(tr -d '\n' < "${DOCKER_DAEMON_JSON_FILE}" | sed -e "s|}[[:space:]]*$|, \"insecure-registries\" : [\"${_ADD_REGISTRY}\"] }|g")
			else
				_FLAT_DAEMON_JSON=$(tr -d '\n' < "${DOCKER_DAEMON_JSON_FILE}" | sed -e "s|}[[:space:]]*$|\"insecure-registries\" : [\"${_ADD_REGISTRY}\"] }|g")
			fi

			if ! /bin/sh -c "${SUDO_CMD} cp /dev/null ${DOCKER_DAEMON_JSON_FILE}" || ! echo "${_FLAT_DAEMON_JSON}" | /bin/sh -c "${SUDO_CMD} tee -a ${DOCKER_DAEMON_JSON_FILE} >/dev/null"; then
				PRNERR "Failed to add \"${_ADD_REGISTRY}\" as insecure registry to ${DOCKER_DAEMON_JSON_FILE} file."
				return 1
			fi
		fi
	else
		#
		# Create daemon.json file
		#
		if [ -n "${_TMP_SETUP_BASE_REGISTRY}" ] && [ -n "${_TMP_SETUP_PUSH_REGISTRY}" ]; then
			_ADD_REGISTRY="\"${_TMP_SETUP_BASE_REGISTRY}\", \"${_TMP_SETUP_PUSH_REGISTRY}\""
		elif [ -n "${_TMP_SETUP_BASE_REGISTRY}" ] && [ -z "${_TMP_SETUP_PUSH_REGISTRY}" ]; then
			_ADD_REGISTRY="\"${_TMP_SETUP_BASE_REGISTRY}\""
		elif [ -z "${_TMP_SETUP_BASE_REGISTRY}" ] && [ -n "${_TMP_SETUP_PUSH_REGISTRY}" ]; then
			_ADD_REGISTRY="\"${_TMP_SETUP_PUSH_REGISTRY}\""
		else
			_ADD_REGISTRY=""
		fi

		{
			echo '{'
			echo "	\"insecure-registries\" : [${_ADD_REGISTRY}]"
			echo '}'
		} | /bin/sh -c "${SUDO_CMD} tee -a ${DOCKER_DAEMON_JSON_FILE} >/dev/null"

		if [ ! -f "${DOCKER_DAEMON_JSON_FILE}" ]; then
			PRNERR "Could not create ${DOCKER_DAEMON_JSON_FILE} file."
			return 1
		fi
	fi

	return 0
}

#--------------------------------------------------------------
# Remove local One image
#--------------------------------------------------------------
# Input:	$1	Image name
#			$2	Image version(tag)
#
RemoveLocalOneImage()
{
	if [ $# -ne 2 ]; then
		PRNERR "Internal Error: Parameters are wrong."
		return 1
	fi
	_TMP_IMAGE_NAME="$1"
	_TMP_IMAGE_VERSTR="$2"

	if docker image ls | awk '{print $1":"$2}' | grep -q -i "${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${_TMP_IMAGE_NAME}:${_TMP_IMAGE_VERSTR}"; then
		PRNINFO "Found ${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${_TMP_IMAGE_NAME}:${_TMP_IMAGE_VERSTR} image in local, so remove it."
		if ({ docker image rm --force "${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${_TMP_IMAGE_NAME}:${_TMP_IMAGE_VERSTR}" 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to remove ${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${_TMP_IMAGE_NAME}:${_TMP_IMAGE_VERSTR} image."
			return 1
		fi
	fi

	return 0
}

#--------------------------------------------------------------
# Remove local images
#--------------------------------------------------------------
RemoveLocalImages()
{
	#----------------------------------------------------------
	# Remove k2hdkc-trove-backup image
	#----------------------------------------------------------
	#
	# Check and remove k2hdkc-trove-backup:latest-<os> image
	#
	if ! RemoveLocalOneImage "${IMAGENAME_K2HDKC_BACKUP}" "${SETUP_IMAGE_LATEST_VERSTR}"; then
		return 1
	fi

	#
	# Check and remove k2hdkc-trove-backup:<version>-<os> image
	#
	if ! RemoveLocalOneImage "${IMAGENAME_K2HDKC_BACKUP}" "${SETUP_IMAGE_VERSTR}"; then
		return 1
	fi

	#
	# Check and remove k2hdkc-trove-backup:latest image
	#
	if [ -n "${SETUP_IMAGE_STANDARD_LATEST_VERSTR}" ]; then
		if ! RemoveLocalOneImage "${IMAGENAME_K2HDKC_BACKUP}" "${SETUP_IMAGE_STANDARD_LATEST_VERSTR}"; then
			return 1
		fi
	fi

	#
	# Check and remove k2hdkc-trove-backup:<version>-<os> image
	#
	if [ -n "${SETUP_IMAGE_STANDARD_VERSTR}" ]; then
		if ! RemoveLocalOneImage "${IMAGENAME_K2HDKC_BACKUP}" "${SETUP_IMAGE_STANDARD_VERSTR}"; then
			return 1
		fi
	fi

	#----------------------------------------------------------
	# Remove k2hdkc-trove image
	#----------------------------------------------------------
	#
	# Check and remove k2hdkc-trove:latest-<os> image
	#
	if ! RemoveLocalOneImage "${IMAGENAME_K2HDKC_TROVE}" "${SETUP_IMAGE_LATEST_VERSTR}"; then
		return 1
	fi

	#
	# Check and remove k2hdkc-trove:<version>-<os> image
	#
	if ! RemoveLocalOneImage "${IMAGENAME_K2HDKC_TROVE}" "${SETUP_IMAGE_VERSTR}"; then
		return 1
	fi

	#
	# Check and remove k2hdkc-trove:latest image
	#
	if [ -n "${SETUP_IMAGE_STANDARD_LATEST_VERSTR}" ]; then
		if ! RemoveLocalOneImage "${IMAGENAME_K2HDKC_TROVE}" "${SETUP_IMAGE_STANDARD_LATEST_VERSTR}"; then
			return 1
		fi
	fi

	#
	# Check and remove k2hdkc-trove:<version> image
	#
	if [ -n "${SETUP_IMAGE_STANDARD_VERSTR}" ]; then
		if ! RemoveLocalOneImage "${IMAGENAME_K2HDKC_TROVE}" "${SETUP_IMAGE_STANDARD_VERSTR}"; then
			return 1
		fi
	fi

	return 0
}

#--------------------------------------------------------------
# Remove one image from private registry
#--------------------------------------------------------------
# Input:	$1	Image name
#			$2	Image version(tag)
#
RemovePrivateRegistryOneImage()
{
	if [ $# -ne 2 ]; then
		PRNERR "Internal Error: Parameters are wrong."
		return 1
	fi
	_TMP_IMAGE_NAME="$1"
	_TMP_IMAGE_VERSTR="$2"
	_TMP_RESPONSE_FILE="/tmp/.${SCRIPTNAME}.$$.tmp"

	rm -f "${_TMP_RESPONSE_FILE}"

	#
	# Get Docker-Content-Digest
	#
	# [NOTE]
	#	Must spesify Header!
	#	"Accept: application/vnd.docker.distribution.manifest.v2+json"
	#
	_TMP_RESULT_CODE=$(curl -s -S --insecure -H "Accept: application/vnd.docker.distribution.manifest.v2+json" -sI "https://${SETUP_PUSH_REGISTRY}v2/${SETUP_PUSH_REPOSITORY}/${_TMP_IMAGE_NAME}/manifests/${_TMP_IMAGE_VERSTR}" -o "${_TMP_RESPONSE_FILE}" -w '%{http_code}')
	if [ -z "${_TMP_RESULT_CODE}" ] || [ "${_TMP_RESULT_CODE}" -ne 200 ] || [ ! -f "${_TMP_RESPONSE_FILE}" ]; then
		PRNINFO "Not found image(${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${_TMP_IMAGE_NAME}:${_TMP_IMAGE_VERSTR}) digest from private registry(result code=${_TMP_RESULT_CODE})."
	else
		#
		# Parse Digest code
		#
		_TMP_DIGEST=$(grep -i '^Docker-Content-Digest' "${_TMP_RESPONSE_FILE}" | tr '\r\n' ' ' | tr '\n' ' ' | awk '{print $NF}')
		if [ -z "${_TMP_DIGEST}" ]; then
			PRNINFO "Could not parse image(${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${_TMP_IMAGE_NAME}:${_TMP_IMAGE_VERSTR}) digest from private registry(result code=${_TMP_RESULT_CODE})."
		else
			#
			# Remove image by Digest
			#
			rm -f "${_TMP_RESPONSE_FILE}"

			_TMP_RESULT_CODE=$(curl -s -S --insecure -X DELETE "https://${SETUP_PUSH_REGISTRY}v2/${SETUP_PUSH_REPOSITORY}/${_TMP_IMAGE_NAME}/manifests/${_TMP_DIGEST}" -o "${_TMP_RESPONSE_FILE}" -w '%{http_code}')
			if [ -z "${_TMP_RESULT_CODE}" ] || [ "${_TMP_RESULT_CODE}" -ne 202 ]; then
				PRNERR "Failed to remove image(${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${_TMP_IMAGE_NAME}:${_TMP_IMAGE_VERSTR} = Digest:${_TMP_DIGEST}) from private registry(result code=${_TMP_RESULT_CODE})."
				rm -f "${_TMP_RESPONSE_FILE}"
				return 1
			fi

			PRNINFO "Removed image(${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${_TMP_IMAGE_NAME}:${_TMP_IMAGE_VERSTR} = Digest:${_TMP_DIGEST}) from private registry."
		fi
	fi
	rm -f "${_TMP_RESPONSE_FILE}"

	return 0
}

#--------------------------------------------------------------
# Remove images from private registry
#--------------------------------------------------------------
RemovePrivateRegistryImages()
{
	if [ "${OPT_OVERUPLOAD}" -eq 0 ]; then
		return 0
	fi
	if [ -z "${SETUP_PUSH_REGISTRY}" ]; then
		#
		# Not private registry
		#
		return 0
	fi

	#
	# Try to remove k2hdkc-trove-backup:latest-<os> image
	#
	if ! RemovePrivateRegistryOneImage "${IMAGENAME_K2HDKC_BACKUP}" "${SETUP_IMAGE_LATEST_VERSTR}"; then
		PRNERR "Failed to remove ${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_BACKUP}:${SETUP_IMAGE_LATEST_VERSTR} image."
		return 1
	fi

	#
	# Try to remove k2hdkc-trove-backup:<version>-<os> image
	#
	if ! RemovePrivateRegistryOneImage "${IMAGENAME_K2HDKC_BACKUP}" "${SETUP_IMAGE_VERSTR}"; then
		PRNERR "Failed to remove ${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_BACKUP}:${SETUP_IMAGE_VERSTR} image."
		return 1
	fi

	#
	# Try to remove k2hdkc-trove-backup:latest image
	#
	if [ -n "${SETUP_IMAGE_STANDARD_LATEST_VERSTR}" ]; then
		if ! RemovePrivateRegistryOneImage "${IMAGENAME_K2HDKC_BACKUP}" "${SETUP_IMAGE_STANDARD_LATEST_VERSTR}"; then
			PRNERR "Failed to remove ${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_BACKUP}:${SETUP_IMAGE_STANDARD_LATEST_VERSTR} image."
			return 1
		fi
	fi

	#
	# Try to remove k2hdkc-trove-backup:<version> image
	#
	if [ -n "${SETUP_IMAGE_STANDARD_VERSTR}" ]; then
		if ! RemovePrivateRegistryOneImage "${IMAGENAME_K2HDKC_BACKUP}" "${SETUP_IMAGE_STANDARD_VERSTR}"; then
			PRNERR "Failed to remove ${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_BACKUP}:${SETUP_IMAGE_STANDARD_VERSTR} image."
			return 1
		fi
	fi

	#
	# Try to remove k2hdkc-trove:latest-<os> image
	#
	if ! RemovePrivateRegistryOneImage "${IMAGENAME_K2HDKC_TROVE}" "${SETUP_IMAGE_LATEST_VERSTR}"; then
		PRNERR "Failed to remove ${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_TROVE}:${SETUP_IMAGE_LATEST_VERSTR} image."
		return 1
	fi

	#
	# Try to remove k2hdkc-trove:<version>-<os> image
	#
	if ! RemovePrivateRegistryOneImage "${IMAGENAME_K2HDKC_TROVE}" "${SETUP_IMAGE_VERSTR}"; then
		PRNERR "Failed to remove ${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_TROVE}:${SETUP_IMAGE_VERSTR} image."
		return 1
	fi

	#
	# Try to remove k2hdkc-trove:latest image
	#
	if [ -n "${SETUP_IMAGE_STANDARD_LATEST_VERSTR}" ]; then
		if ! RemovePrivateRegistryOneImage "${IMAGENAME_K2HDKC_TROVE}" "${SETUP_IMAGE_STANDARD_LATEST_VERSTR}"; then
			PRNERR "Failed to remove ${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_TROVE}:${SETUP_IMAGE_STANDARD_LATEST_VERSTR} image."
			return 1
		fi
	fi

	#
	# Try to remove k2hdkc-trove:<version> image
	#
	if [ -n "${SETUP_IMAGE_STANDARD_VERSTR}" ]; then
		if ! RemovePrivateRegistryOneImage "${IMAGENAME_K2HDKC_TROVE}" "${SETUP_IMAGE_STANDARD_VERSTR}"; then
			PRNERR "Failed to remove ${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_TROVE}:${SETUP_IMAGE_STANDARD_VERSTR} image."
			return 1
		fi
	fi

	return 0
}

#==============================================================
# Other utility functions
#==============================================================
#
# Check and set sudo command prefix
#
# Output:	SUDO_CMD	"sudo" or empty string
#
CheckUserAndSudoPrefix()
{
	_USER_ID=$(id -u)
	_USER_NAME=$(id -u -n)

	if [ -n "${_USER_ID}" ] && [ "${_USER_ID}" -eq 0 ]; then
		SUDO_CMD=""
	elif [ -n "${_USER_NAME}" ] && [ "${_USER_NAME}" = "root" ]; then
		SUDO_CMD=""
	else
		SUDO_CMD="sudo"
	fi
	return 0
}

#
# Usage function
#
Usage()
{
	echo ""
	echo "Usage: ${SCRIPTNAME} --help(-h)"
	echo "       ${SCRIPTNAME} [cleanup(clean)/cleanup-all | generate_dockerfile(gen) | build_image(build) | upload_image(upload)] <options>"
	echo ""
	echo " [Command]"
	echo "   cleanup(clean), cleanup-all             : Cleanup the working files etc. \"cleanup-all\" clean all docker images with docker build cache."
	echo "   generate_dockerfile(gen)                : Generate Dockerfiles for K2HDKC Trove Container images"
	echo "   build_image(build)                      : Generate Dockerfiles and Build K2HDKC Trove Container images"
	echo "   upload_image(upload)                    : Generate Dockerfiles and Build/Upload K2HDKC Trove Container images"
	echo ""
	echo " [Options]"
	echo "   --help(-h)                              : Print usage"
	echo ""
	echo "   --conf(-c) <confg file prefix>          : Specifies the prefix name for customized configuration files."
	echo "                                             The configuration file is \"conf/xxxxx.conf\" pattern, and specifies"
	echo "                                             the file name without the \".conf\"."
	echo "                                             The default is null(it means unspecified custom configuration file)."
	echo ""
	echo "   --base-registry(-br) <domain:port>      : Base K2HDKC Image Docker Registry Server and Port"
	echo "   --base-repository(-bp) <path>           : Base K2HDKC Image Docker Repository name"
	echo "   --registry(-r) <domain:port>            : Docker Registry Server and Port for upload(push)ing image"
	echo "   --repository(-p) <path>                 : Docker Repository name for upload(push)ing image"
	echo ""
	echo "   --os(-o) <type>                         : Target OS type(Ubunutu, Rocky, Alpine)"
	echo "   --base-image-version(-b) <version>      : Base image(K2HDKC) version"
	echo ""
	echo "   --image-version(-i) <version>           : Create image version"
	echo "   --over-upload(-u)                       : Allow to over upload image(allow to remove same version in repository)"
	echo "   --set-proxy-env(-e)                     : Set the PROXY environment variable in the Docker image(default: not set)"
	echo ""
	echo "   --trove-repository-clone(-t)            : Clone the Trove base repository and apply the patch before building."
	echo "   --trove-repository-branch(-tb) <branch> : If you need to specify the branch name to clone, specify it."
	echo "                                             If omitted this option, \"${DEVSTACK_BRANCH}\" will be used as default."
	echo ""
	echo " [Enviroments]"
	echo "   HTTP_PROXY(http_proxy)                  : Using HTTP Proxy as this value"
	echo "   HTTPS_PROXY(https_proxy)                : Using HTTPS Proxy as this value"
	echo "   NO_PROXY(no_proxy)                      : Using No Proxy as this value"
	echo ""
}

#==============================================================
# Parse options(parameters)
#==============================================================
#
# Option value
#
# [NOTE]
# RUN_LEVEL		0 : Not specified any command(error)
#				1 : Cleanup working files/directories
#				2 : Run to generate dockerfile
#				3 : Run to generate dockerfile and build images
#				4 : Run to generate dockerfile and build images and upload them
#
RUN_LEVEL=0
CLEANUP_ALL=0
ENABLE_PUSH_IMAGE=0

OPT_CONFIG_FILE=""
OPT_BASE_REGISTRY=""
OPT_BASE_REPOSITORY=""
OPT_PUSH_REGISTRY=""
OPT_PUSH_REPOSITORY=""
OPT_OS_TYPE=""
OPT_K2HDKC_VER=""
OPT_IMAGE_VER=""
OPT_OVERUPLOAD=0
OPT_SET_PROXY_ENV=0
OPT_TROVE_REPO_CLONE=0
OPT_TROVE_REPO_BRANCH=""

while [ $# -ne 0 ]; do
	if [ -z "$1" ]; then
		break;

	elif echo "$1" | grep -q -i -e "^--help$" -e "^-h$"; then
		Usage
		exit 0

	elif echo "$1" | grep -q -i -e "^--conf$" -e "^-c$"; then
		if [ -n "${OPT_CONFIG_FILE}" ]; then
			PRNERR "Already specified --conf(-c) option : \"${OPT_CONFIG_FILE}\""
			exit 1
		fi
		shift
		if [ -z "$1" ]; then
			PRNERR "Option --conf(-c) needs parameter."
			exit 1
		fi
		if [ ! -f "${SCRIPT_CONFIG_DIR}/$1.conf" ]; then
			PRNERR "Not found ${SCRIPT_CONFIG_DIR}/$1.conf file."
			exit 1
		fi
		OPT_CONFIG_FILE="${SCRIPT_CONFIG_DIR}/$1.conf"

	elif echo "$1" | grep -q -i -e "^--base-registry$" -e "^-br$"; then
		if [ -n "${OPT_BASE_REGISTRY}" ]; then
			PRNERR "Already specified --base-registry(-br) option : \"${OPT_BASE_REGISTRY}\""
			exit 1
		fi
		shift
		if [ -z "$1" ]; then
			PRNERR "Option --base-registry(-br) needs parameter."
			exit 1
		fi
		OPT_BASE_REGISTRY="$1"

	elif echo "$1" | grep -q -i -e "^--base-repository$" -e "^-bp$"; then
		if [ -n "${OPT_BASE_REPOSITORY}" ]; then
			PRNERR "Already specified --base-repository(-bp) option : \"${OPT_BASE_REPOSITORY}\""
			exit 1
		fi
		shift
		if [ -z "$1" ]; then
			PRNERR "Option --base-repository(-bp) needs parameter."
			exit 1
		fi
		OPT_BASE_REPOSITORY="$1"

	elif echo "$1" | grep -q -i -e "^--registry$" -e "^-r$"; then
		if [ -n "${OPT_PUSH_REGISTRY}" ]; then
			PRNERR "Already specified --registry(-r) option : \"${OPT_PUSH_REGISTRY}\""
			exit 1
		fi
		shift
		if [ -z "$1" ]; then
			PRNERR "Option --registry(-r) needs parameter."
			exit 1
		fi
		OPT_PUSH_REGISTRY="$1"

	elif echo "$1" | grep -q -i -e "^--repository$" -e "^-p$"; then
		if [ -n "${OPT_PUSH_REPOSITORY}" ]; then
			PRNERR "Already specified --repository(-p) option : \"${OPT_PUSH_REPOSITORY}\""
			exit 1
		fi
		shift
		if [ -z "$1" ]; then
			PRNERR "Option --repository(-p) needs parameter."
			exit 1
		fi
		OPT_PUSH_REPOSITORY="$1"

	elif echo "$1" | grep -q -i -e "^--os" -e "^-o"; then
		if [ -n "${OPT_OS_TYPE}" ]; then
			PRNERR "Already specified --os(-o) option : \"${OPT_OS_TYPE}\""
			exit 1
		fi
		shift
		if [ -z "$1" ]; then
			PRNERR "Option --os(-o) needs parameter."
			exit 1
		fi
		if echo "$1" | grep -q -i "^ubuntu$"; then
			OPT_OS_TYPE="ubuntu"
		elif echo "$1" | grep -q -i -e "^rocky9$" -e "^rocky$"; then
			OPT_OS_TYPE="rocky9"
		elif echo "$1" | grep -q -i "^alpine$"; then
			OPT_OS_TYPE="alpine"
		else
			PRNERR "Option --os(-o) parameter must be \"ubuntu\" or \"rocky9\" or \"alpine\"."
			exit 1
		fi

	elif echo "$1" | grep -q -i -e "^--base-image-version$" -e "^-b$"; then
		if [ -n "${OPT_K2HDKC_VER}" ]; then
			PRNERR "Already specified --base-image-version(-b) option : \"${OPT_K2HDKC_VER}\""
			exit 1
		fi
		shift
		if [ -z "$1" ]; then
			PRNERR "Option --base-image-version(-b) needs parameter."
			exit 1
		fi
		OPT_K2HDKC_VER="$1"

	elif echo "$1" | grep -q -i -e "^--image-version$" -e "^-i$"; then
		if [ -n "${OPT_IMAGE_VER}" ]; then
			PRNERR "Already specified --image-version(-i) option : \"${OPT_IMAGE_VER}\""
			exit 1
		fi
		shift
		if [ -z "$1" ]; then
			PRNERR "Option --image-version(-i) needs parameter."
			exit 1
		fi
		OPT_IMAGE_VER="$1"

	elif echo "$1" | grep -q -i -e "^--over-upload$" -e "^-u$"; then
		if [ "${OPT_OVERUPLOAD}" -ne 0 ]; then
			PRNERR "Already specified --over-upload(-u) option"
			exit 1
		fi
		OPT_OVERUPLOAD=1

	elif echo "$1" | grep -q -i -e "^--set-proxy-env$" -e "^-e$"; then
		if [ "${OPT_SET_PROXY_ENV}" -ne 0 ]; then
			PRNERR "Already specified --set-proxy-env(-e) option"
			exit 1
		fi
		OPT_SET_PROXY_ENV=1

	elif echo "$1" | grep -q -i -e "^--trove-repository-clone$" -e "^-t$"; then
		if [ "${OPT_TROVE_REPO_CLONE}" -ne 0 ]; then
			PRNERR "Already specified --trove-repository-clone(-t) option"
			exit 1
		fi
		OPT_TROVE_REPO_CLONE=1

	elif echo "$1" | grep -q -i -e "^--trove-repository-branch$" -e "^-tb$"; then
		if [ -n "${OPT_TROVE_REPO_BRANCH}" ]; then
			PRNERR "Already specified --trove-repository-branch(-tb) option(${OPT_TROVE_REPO_BRANCH})"
			exit 1
		fi
		shift
		if [ -z "$1" ]; then
			PRNERR "Option --trove-repository-branch(-tb) needs parameter."
			exit 1
		fi
		OPT_TROVE_REPO_BRANCH="$1"

	else
		if echo "$1" | grep -q -i "^cleanup-all$"; then
			if [ "${RUN_LEVEL}" -ne 0 ]; then
				PRNERR "Already specified command(run level) : \"${RUN_LEVEL}\""
				exit 1
			fi
			RUN_LEVEL=1
			CLEANUP_ALL=1

		elif echo "$1" | grep -q -i -e "^cleanup$" -e "^clean$"; then
			if [ "${RUN_LEVEL}" -ne 0 ]; then
				PRNERR "Already specified command(run level) : \"${RUN_LEVEL}\""
				exit 1
			fi
			RUN_LEVEL=1

		elif echo "$1" | grep -q -i -e "^generate_dockerfile$" -e "^generate$" -e "^gen$"; then
			if [ "${RUN_LEVEL}" -ne 0 ]; then
				PRNERR "Already specified command(run level) : \"${RUN_LEVEL}\""
				exit 1
			fi
			RUN_LEVEL=2

		elif echo "$1" | grep -q -i -e "^build_image$" -e "^build$"; then
			if [ "${RUN_LEVEL}" -ne 0 ]; then
				PRNERR "Already specified command(run level) : \"${RUN_LEVEL}\""
				exit 1
			fi
			RUN_LEVEL=3

		elif echo "$1" | grep -q -i -e "^upload_image$" -e "^upload$"; then
			if [ "${RUN_LEVEL}" -ne 0 ]; then
				PRNERR "Already specified command(run level) : \"${RUN_LEVEL}\""
				exit 1
			fi
			RUN_LEVEL=4

		else
			PRNERR "Unknown option : \"$1\""
			exit 1
		fi
	fi
	shift
done

#
# Check options
#
if [ "${RUN_LEVEL}" -le 0 ] || [ "${RUN_LEVEL}" -gt 4 ]; then
	PRNERR "Not specified command(run level) : \"cleanup(clean)\" or \"generate_dockerfile(gen)\" or \"build_image(build)\" or \"upload_image(upload)\""
	exit 1
fi

if [ -z "${OPT_BASE_REGISTRY}" ]; then
	SETUP_BASE_REGISTRY="${DEFAULT_REGISTRY}"
else
	_TMP_CHARACTOR=$(echo "${OPT_BASE_REGISTRY}" | rev | cut -c 1)
	if [ -n "${_TMP_CHARACTOR}" ] && [ "${_TMP_CHARACTOR}" = "/" ]; then
		SETUP_BASE_REGISTRY="${OPT_BASE_REGISTRY}"
	else
		SETUP_BASE_REGISTRY="${OPT_BASE_REGISTRY}/"
	fi
fi

if [ -z "${OPT_BASE_REPOSITORY}" ]; then
	SETUP_BASE_REPOSITORY="${DEFAULT_REPOSITORY}"
else
	SETUP_BASE_REPOSITORY="${OPT_BASE_REPOSITORY}"
fi

if [ -z "${OPT_PUSH_REGISTRY}" ]; then
	SETUP_PUSH_REGISTRY="${DEFAULT_REGISTRY}"
else
	_TMP_CHARACTOR=$(echo "${OPT_PUSH_REGISTRY}" | rev | cut -c 1)
	if [ -n "${_TMP_CHARACTOR}" ] && [ "${_TMP_CHARACTOR}" = "/" ]; then
		SETUP_PUSH_REGISTRY="${OPT_PUSH_REGISTRY}"
	else
		SETUP_PUSH_REGISTRY="${OPT_PUSH_REGISTRY}/"
	fi
fi

if [ -z "${OPT_PUSH_REPOSITORY}" ]; then
	SETUP_PUSH_REPOSITORY="${DEFAULT_REPOSITORY}"
else
	SETUP_PUSH_REPOSITORY="${OPT_PUSH_REPOSITORY}"
fi

if [ -z "${OPT_OS_TYPE}" ]; then
	if [ "${RUN_LEVEL}" -gt 1 ]; then
		PRNERR "Not specified --os(-o) option."
		exit 1
	fi
else
	SETUP_OS_TYPE="${OPT_OS_TYPE}"
fi

if [ -z "${OPT_K2HDKC_VER}" ]; then
	if [ "${RUN_LEVEL}" -gt 1 ]; then
		PRNERR "Not specified --base-image-version(-b) option."
		exit 1
	fi
else
	SETUP_K2HDKC_VER="${OPT_K2HDKC_VER}"
fi

if [ -z "${OPT_IMAGE_VER}" ]; then
	if [ "${RUN_LEVEL}" -gt 1 ]; then
		PRNERR "Not specified --image-version(-i) option."
		exit 1
	fi
else
	SETUP_IMAGE_VER="${OPT_IMAGE_VER}"
fi

if [ -n "${OPT_TROVE_REPO_BRANCH}" ]; then
	DEVSTACK_BRANCH="${OPT_TROVE_REPO_BRANCH}"
fi

#==============================================================
# Load custom configuration and setup other variables
#==============================================================
# OPT_CONFIG_FILE allows you to override configuration values.
# This file will only be loaded if it exists.
#
if [ -n "${OPT_CONFIG_FILE}" ]; then
	# shellcheck disable=SC1090
	CONFIG_FILE_DIR="${SCRIPT_CONFIG_DIR}" . "${OPT_CONFIG_FILE}"
fi

if [ "${RUN_LEVEL}" -gt 1 ]; then
	#
	# Make version string
	#
	#	SETUP_K2HDKC_VERSTR					: K2HDKC base image version and os-type string(ex. "1.0.14-ubuntu")
	#	SETUP_IMAGE_VERSTR					: The main suffix(a composite string of version and OS name: "1.0.0-ubuntu")
	#	SETUP_IMAGE_LATEST_VERSTR			: The latest suffix(a composite string of "latest" and OS name: "latest-ubuntu")
	#	SETUP_IMAGE_STANDARD_VERSTR			: The suffix of only the version number(ex. "1.0.0"). Set in the case where it
	#										  should be created, and empty if not.
	#	SETUP_IMAGE_STANDARD_LATEST_VERSTR	: The suffix of only "latest". Set in the case where it should be created,
	#										  and empty if not.
	#
	if ! SetupImageVersionString; then
		PRNERR "Failed to make version string for docker image suffix."
		exit 1
	fi
fi

#
# Setup ENABLE_PUSH_IMAGE variables
#
SetupControlPushImages

#==============================================================
# Sudo command prefix
#==============================================================
CheckUserAndSudoPrefix

#==============================================================
# Generate Dockerfiles
#==============================================================
if [ "${RUN_LEVEL}" -ge 1 ]; then

	PRNTITLE "Cleanup working files"

	#
	# Check files
	#
	PRNMSG "Cleanup temporary files for working."
	rm -rf	"${SCRIPTDIR}/00-aptproxy.conf"					\
			"${SCRIPTDIR}/pip.conf"							\
			"${SCRIPTDIR}/Dockerfile.backup"				\
			"${SCRIPTDIR}/Dockerfile.trove"					\
			"${SCRIPTDIR}/backup"

	PRNINFO "Cleanup temporary files for working."

	if [ "${CLEANUP_ALL}" -ne 0 ]; then
		#
		# Cleanup all docker images
		#
		PRNMSG "Cleanup all docker images in local."

		_TMP_DOCKER_IMAGE_IDS=$(docker image ls | grep -v REPOSITORY | awk '{print $3}' | sort | uniq | tr '\n' ' ')
		if [ -n "${_TMP_DOCKER_IMAGE_IDS}" ]; then
			if ! /bin/sh -c "docker image rm -f ${_TMP_DOCKER_IMAGE_IDS} >/dev/null 2>&1"; then
				PRNERR "Could not remove some docker images."
				exit 1
			fi
		fi
		PRNINFO "Cleanup docker images in local."

		#
		# Cleanup docker build cache
		#
		PRNMSG "Cleanup docker build caches."
		if ! docker buildx prune --force >/dev/null 2>&1; then
			PRNERR "Could not remove docker build caches."
			exit 1
		fi
		PRNINFO "Cleanup docker build caches."

		#
		# Restart docker.service
		#
		PRNMSG "Restart docker.service"
		if ! /bin/sh -c "${SUDO_CMD} systemctl restart docker.service >/dev/null 2>&1"; then
			PRNERR "Failed to run systemctl restart docker.service"
			exit 1
		fi
		PRNINFO "Restarted docker.service"
	fi

	PRNSUCCESS "Cleanup working files"
fi

#==============================================================
# Generate Dockerfiles
#==============================================================
if [ "${RUN_LEVEL}" -ge 2 ]; then

	PRNTITLE "Generate Dockerfiles"

	#
	# Check files
	#
	PRNMSG "Check Dockerfiles and template files."
	if [ ! -f "${K2HDKC_TROVE_DOCKERFILE_TEMPL}" ]; then
		PRNERR "Not found ${K2HDKC_TROVE_DOCKERFILE_TEMPL} file."
		exit 1
	fi
	if [ -f "${K2HDKC_TROVE_DOCKERFILE}" ]; then
		PRNWARN "Found ${K2HDKC_TROVE_DOCKERFILE} file, so it will be removed."
		rm -f "${K2HDKC_TROVE_DOCKERFILE}"
	fi
	if [ ! -f "${K2HDKC_BACKUP_DOCKERFILE_TEMPL}" ]; then
		PRNERR "Not found ${K2HDKC_BACKUP_DOCKERFILE_TEMPL} file."
		exit 1
	fi
	if [ -f "${K2HDKC_BACKUP_DOCKERFILE}" ]; then
		PRNWARN "Found ${K2HDKC_BACKUP_DOCKERFILE} file, so it will be removed."
		rm -f "${K2HDKC_BACKUP_DOCKERFILE}"
	fi
	PRNINFO "Checked Dockerfile and template file."

	#
	# Setup variables
	#
	PRNMSG "Setup variables"
	if ! SetupVariables; then
		PRNERR "Something error occurred during setup variables."
		exit 1
	fi

	#
	# Copy backup directory in current directory for backup image
	#
	PRNMSG "Create(copy) backup directory from trove/backup directory."

	if [ -d "${SCRIPTDIR}/backup" ]; then
		rm -rf "${SCRIPTDIR}/backup"
	fi

	if [ "${OPT_TROVE_REPO_CLONE}" -ne 1 ]; then
		# [NOTE]
		# If this script is called from k2hdkcstack.sh or manual without the "-t"
		# option, it enters here.
		# In other words, it is assumed that the source code with the patch applied
		# is in /opt/stack (stack user) or below.
		#
		TMP_CLONED_TROVE_WORK_DIR=""
		TROVE_BACKUP_DIR="/opt/stack/trove/backup"

		if [ ! -d "${TROVE_BACKUP_DIR}" ]; then
			PRNERR "Not found ${TROVE_BACKUP_DIR} directory, it should be the directory of the appropriate branch of Trove, patched with k2hdkc_dbaas_trove."
			exit 1
		fi
	else
		#
		# Setup direcctories
		#
		TMP_CLONED_TROVE_WORK_DIR="/tmp/.${SCRIPTNAME}.$$"
		if ! mkdir -p "${TMP_CLONED_TROVE_WORK_DIR}" 2>/dev/null; then
			PRNERR "Could not create ${TMP_CLONED_TROVE_WORK_DIR}"
			return 1
		fi
		TMP_CLONED_TROVE_REPO_DIR="${TMP_CLONED_TROVE_WORK_DIR}/trove"
		if [ -d "${TMP_CLONED_TROVE_REPO_DIR}" ]; then
			rm -rf "${TMP_CLONED_TROVE_REPO_DIR}"
		fi

		#
		# Clone trove repository
		#
		if ! CloneRepositoryAndSetBranch "trove" "${TMP_CLONED_TROVE_WORK_DIR}" "${DEVSTACK_BRANCH}"; then
			rm -rf "${TMP_CLONED_TROVE_WORK_DIR}"
			return 1
		fi

		#
		# Extract patch file
		#
		if ! ExtractPatchFiles "${SRCTOPDIR}/trove" "${TMP_CLONED_TROVE_REPO_DIR}"; then
			rm -rf "${TMP_CLONED_TROVE_WORK_DIR}"
			return 1
		fi

		#
		# Set trove/backup directory
		#
		TROVE_BACKUP_DIR="${TMP_CLONED_TROVE_REPO_DIR}/backup"
	fi

	if ! cp -rp "${TROVE_BACKUP_DIR}" "${SCRIPTDIR}" >/dev/null 2>&1; then
		PRNERR "Failed to copy \"backup\" source directory(${TROVE_BACKUP_DIR}) in current directory."
		exit 1
	fi
	if [ -n "${TMP_CLONED_TROVE_WORK_DIR}" ]; then
		rm -rf "${TMP_CLONED_TROVE_WORK_DIR}"
	fi

	PRNINFO "Created(copied) backup directory from trove/backup directory."

	#
	# Print information
	#
	echo "    [Variables]"
	echo "    SETUP_BASE_REGISTRY                = ${SETUP_BASE_REGISTRY}"
	echo "    SETUP_BASE_REPOSITORY              = ${SETUP_BASE_REPOSITORY}"
	echo "    SETUP_PUSH_REGISTRY                = ${SETUP_PUSH_REGISTRY}"
	echo "    SETUP_PUSH_REPOSITORY              = ${SETUP_PUSH_REPOSITORY}"
	echo "    SETUP_K2HDKC_VER                   = ${SETUP_K2HDKC_VER}"
	echo "    SETUP_IMAGE_VER                    = ${SETUP_IMAGE_VER}"
	echo "    SETUP_OS_TYPE                      = ${SETUP_OS_TYPE}"
	echo "    SETUP_K2HDKC_VERSTR                = ${SETUP_K2HDKC_VERSTR}"
	echo "    SETUP_IMAGE_VERSTR                 = ${SETUP_IMAGE_VERSTR}"
	echo "    SETUP_IMAGE_LATEST_VERSTR          = ${SETUP_IMAGE_LATEST_VERSTR}"
	echo "    SETUP_IMAGE_STANDARD_VERSTR        = ${SETUP_IMAGE_STANDARD_VERSTR}"
	echo "    SETUP_IMAGE_STANDARD_LATEST_VERSTR = ${SETUP_IMAGE_STANDARD_LATEST_VERSTR}"
	echo ""
	echo "    SETUP_ENV                          = ${SETUP_ENV}"
	echo "    SETUP_PROXY_ENV                    = ${SETUP_PROXY_ENV}"
	echo "    PRE_PROCESS_BEFORE_INSTALL         = ${PRE_PROCESS_BEFORE_INSTALL}"
	echo "    POST_PROCESS_AFTER_INSTALL         = ${POST_PROCESS_AFTER_INSTALL}"
	echo ""
	echo "    PRE_PKG_UPDATE                     = ${PRE_PKG_UPDATE}"
	echo "    PKG_UPDATE                         = ${PKG_UPDATE}"
	echo "    PRE_COMMON_PKG_INSTALL             = ${PRE_COMMON_PKG_INSTALL}"
	echo "    COMMON_PKG_INSTALL                 = ${COMMON_PKG_INSTALL}"
	echo "    POST_COMMON_PKG_INSTALL            = ${POST_COMMON_PKG_INSTALL}"
	echo "    PRE_PKG_INSTALL                    = ${PRE_PKG_INSTALL}"
	echo "    PKG_INSTALL                        = ${PKG_INSTALL}"
	echo "    POST_PKG_INSTALL                   = ${POST_PKG_INSTALL}"
	echo "    PRE_SETUP_USER                     = ${PRE_SETUP_USER}"
	echo "    SETUP_USER                         = ${SETUP_USER}"
	echo "    POST_SETUP_USER                    = ${POST_SETUP_USER}"
	echo "    PRE_BACKUP_PKG_INSTALL             = ${PRE_BACKUP_PKG_INSTALL}"
	echo "    BACKUP_PKG_INSTALL                 = ${BACKUP_PKG_INSTALL}"
	echo "    POST_BACKUP_PKG_INSTALL            = ${POST_BACKUP_PKG_INSTALL}"
	echo "    PIP_PKG_INSTALL                    = ${PIP_PKG_INSTALL}"
	echo "    PIP_INSTALL                        = ${PIP_INSTALL}"
	echo "    POST_PIP_INSTALL                   = ${POST_PIP_INSTALL}"
	echo ""

	#
	# Generate Dockerfile for trove(main)
	#
	PRNMSG "Generate ${K2HDKC_TROVE_DOCKERFILE_NAME}"

	if ! sed -e "s|%%SETUP_BASE_REGISTRY%%|${SETUP_BASE_REGISTRY}|g"				\
			 -e "s|%%SETUP_BASE_REPOSITORY%%|${SETUP_BASE_REPOSITORY}|g"			\
			 -e "s|%%SETUP_K2HDKC_VERSTR%%|${SETUP_K2HDKC_VERSTR}|g"				\
			 -e "s|%%SETUP_ENV%%|${SETUP_ENV}|g"									\
			 -e "s|%%SETUP_PROXY_ENV%%|${SETUP_PROXY_ENV}|g"						\
			 -e "s|%%PRE_PROCESS_BEFORE_INSTALL%%|${PRE_PROCESS_BEFORE_INSTALL}|g"	\
			 -e "s|%%PRE_PKG_UPDATE%%|${PRE_PKG_UPDATE}|g"							\
			 -e "s|%%PKG_UPDATE%%|${PKG_UPDATE}|g"									\
			 -e "s|%%PRE_COMMON_PKG_INSTALL%%|${PRE_COMMON_PKG_INSTALL}|g"			\
			 -e "s|%%COMMON_PKG_INSTALL%%|${COMMON_PKG_INSTALL}|g"					\
			 -e "s|%%POST_COMMON_PKG_INSTALL%%|${POST_COMMON_PKG_INSTALL}|g"		\
			 -e "s|%%PRE_PKG_INSTALL%%|${PRE_PKG_INSTALL}|g"						\
			 -e "s|%%PKG_INSTALL%%|${PKG_INSTALL}|g"								\
			 -e "s|%%POST_PKG_INSTALL%%|${POST_PKG_INSTALL}|g"						\
			 -e "s|%%PRE_SETUP_USER%%|${PRE_SETUP_USER}|g"							\
			 -e "s|%%SETUP_USER%%|${SETUP_USER}|g"									\
			 -e "s|%%POST_SETUP_USER%%|${POST_SETUP_USER}|g"						\
			 "${K2HDKC_TROVE_DOCKERFILE_TEMPL}" > "${K2HDKC_TROVE_DOCKERFILE}" 2> "${SUB_PROC_ERROR_LOGFILE}"; then

		PRNERR "Failed to generate ${K2HDKC_TROVE_DOCKERFILE} file :"
		sed -e 's|^|        |g' "${SUB_PROC_ERROR_LOGFILE}"
		rm -f "${SUB_PROC_ERROR_LOGFILE}"
		exit 1
	fi

	PRNINFO "Created ${K2HDKC_TROVE_DOCKERFILE_NAME}"

	#
	# Generate Dockerfile for backup
	#
	PRNMSG "Generate ${K2HDKC_BACKUP_DOCKERFILE_NAME}"
	if ! sed -e "s|%%SETUP_PUSH_REGISTRY%%|${SETUP_PUSH_REGISTRY}|g"				\
			 -e "s|%%SETUP_PUSH_REPOSITORY%%|${SETUP_PUSH_REPOSITORY}|g"			\
			 -e "s|%%SETUP_K2HDKC_VER%%|${SETUP_K2HDKC_VER}|g"						\
			 -e "s|%%SETUP_IMAGE_VERSTR%%|${SETUP_IMAGE_VERSTR}|g"					\
			 -e "s|%%SETUP_ENV%%|${SETUP_ENV}|g"									\
			 -e "s|%%SETUP_PROXY_ENV%%|${SETUP_PROXY_ENV}|g"						\
			 -e "s|%%PRE_PROCESS_BEFORE_INSTALL%%|${PRE_PROCESS_BEFORE_INSTALL}|g"	\
			 -e "s|%%PRE_PKG_UPDATE%%|${PRE_PKG_UPDATE}|g"							\
			 -e "s|%%PKG_UPDATE%%|${PKG_UPDATE}|g"									\
			 -e "s|%%PRE_BACKUP_PKG_INSTALL%%|${PRE_BACKUP_PKG_INSTALL}|g"			\
			 -e "s|%%BACKUP_PKG_INSTALL%%|${BACKUP_PKG_INSTALL}|g"					\
			 -e "s|%%POST_BACKUP_PKG_INSTALL%%|${POST_BACKUP_PKG_INSTALL}|g"		\
			 -e "s|%%PIP_PKG_INSTALL%%|${PIP_PKG_INSTALL}|g"						\
			 -e "s|%%PIP_INSTALL%%|${PIP_INSTALL}|g"								\
			 -e "s|%%POST_PIP_INSTALL%%|${POST_PIP_INSTALL}|g"						\
			 "${K2HDKC_BACKUP_DOCKERFILE_TEMPL}" > "${K2HDKC_BACKUP_DOCKERFILE}" 2> "${SUB_PROC_ERROR_LOGFILE}"; then

		PRNERR "Failed to generate ${K2HDKC_BACKUP_DOCKERFILE} file."
		sed -e 's|^|        |g' "${SUB_PROC_ERROR_LOGFILE}"
		rm -f "${SUB_PROC_ERROR_LOGFILE}"
		exit 1
	fi
	PRNINFO "Created ${K2HDKC_BACKUP_DOCKERFILE_NAME}"

	#
	# Print Dockerfile(trove)
	#
	rm -f "${SUB_PROC_ERROR_LOGFILE}"

	PRNMSG "Generated ${K2HDKC_TROVE_DOCKERFILE}"
	sed -e 's|^|    |g' "${K2HDKC_TROVE_DOCKERFILE}"

	PRNMSG "Generated ${K2HDKC_BACKUP_DOCKERFILE}"
	sed -e 's|^|    |g' "${K2HDKC_BACKUP_DOCKERFILE}"

	PRNSUCCESS "Generate Dockerfiles"
fi

#==============================================================
# Build Docker Image
#==============================================================
#
# After here, need to move current directory.
#
cd "${SCRIPTDIR}" || exit 1

if [ "${RUN_LEVEL}" -ge 3 ]; then

	PRNTITLE "Build Docker Images"

	#
	# Check files
	#
	PRNMSG "Check Dockerfiles."
	if [ ! -f "${K2HDKC_TROVE_DOCKERFILE}" ]; then
		PRNERR "Not found ${K2HDKC_TROVE_DOCKERFILE} file."
		exit 1
	fi
	if [ ! -f "${K2HDKC_BACKUP_DOCKERFILE}" ]; then
		PRNERR "Not found ${K2HDKC_BACKUP_DOCKERFILE} file."
		exit 1
	fi
	PRNINFO "Found ${K2HDKC_TROVE_DOCKERFILE} and ${K2HDKC_BACKUP_DOCKERFILE} files."

	#
	# Check docker process
	#
	PRNMSG "Check docker process."
	if ({ systemctl status docker 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
		PRNERR "Docker process is not running, could not continue this process."
		exit 1
	fi
	PRNINFO "Docker process running."

	#
	# Setup daemon.json
	#
	PRNMSG "Check and Setup daemon.json file."
	if ! SetupDockerDaemonJsonFile; then
		exit 1
	fi
	PRNINFO "Setup daemon.json file."

	#
	# Remove local images
	#
	PRNMSG "Check and Remove images in local."
	if ! RemoveLocalImages; then
		exit 1
	fi
	PRNINFO "Removed images in local."

	#---------------------------------------------------------
	# Create k2hdkc-trove image and set tags
	#---------------------------------------------------------
	#
	# Create k2hdkc-trove:<version>-<os> image
	#
	PRNMSG "Create ${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_TROVE}:${SETUP_IMAGE_VERSTR} image."
	if ({ docker image build --progress=plain --build-arg "${BUILD_ARG_HTTP_PROXY}" --build-arg "${BUILD_ARG_HTTPS_PROXY}" --build-arg "${BUILD_ARG_NO_PROXY}" -f "${K2HDKC_TROVE_DOCKERFILE_NAME}" -t "${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_TROVE}:${SETUP_IMAGE_VERSTR}" . 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
		PRNERR "Failed to create \"${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_TROVE}:${SETUP_IMAGE_VERSTR}\" image from ${K2HDKC_TROVE_DOCKERFILE}."
		exit 1
	fi
	PRNINFO "Created ${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_TROVE}:${SETUP_IMAGE_VERSTR} image."

	#
	# Set latest-<os> tag
	#
	PRNMSG "Set ${SETUP_IMAGE_LATEST_VERSTR} tag to ${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_TROVE} image."
	if ! _TMP_IMAGE_ID=$(docker image ls 2>/dev/null | awk '{print $1" "$2" "$3}' | grep "${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_TROVE} ${SETUP_IMAGE_VERSTR}" | awk '{print $3}'); then
		PRNERR "Not found ${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_TROVE}:${SETUP_IMAGE_VERSTR} image id."
		exit 1
	fi
	if [ -z "${_TMP_IMAGE_ID}" ]; then
		PRNERR "Not found ${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_TROVE}:${SETUP_IMAGE_VERSTR} image id."
		exit 1
	fi
	if ({ docker tag "${_TMP_IMAGE_ID}" "${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_TROVE}:${SETUP_IMAGE_LATEST_VERSTR}" 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
		PRNERR "Failed to set ${SETUP_IMAGE_LATEST_VERSTR} tag \"${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_TROVE}:${SETUP_IMAGE_LATEST_VERSTR}\" to \"${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_TROVE}:${SETUP_IMAGE_VERSTR}\" image."
		exit 1
	fi
	PRNINFO "Set ${SETUP_IMAGE_LATEST_VERSTR} tag to ${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_TROVE} image."

	#
	# Set <version> tag
	#
	if [ -n "${SETUP_IMAGE_STANDARD_VERSTR}" ]; then
		PRNMSG "Set ${SETUP_IMAGE_STANDARD_VERSTR} tag to ${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_TROVE} image."
		if ({ docker tag "${_TMP_IMAGE_ID}" "${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_TROVE}:${SETUP_IMAGE_STANDARD_VERSTR}" 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to set ${SETUP_IMAGE_STANDARD_VERSTR} tag \"${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_TROVE}:${SETUP_IMAGE_STANDARD_VERSTR}\" to \"${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_TROVE}:${SETUP_IMAGE_VERSTR}\" image."
			exit 1
		fi
		PRNINFO "Set ${SETUP_IMAGE_STANDARD_VERSTR} tag to ${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_TROVE} image."
	fi

	#
	# Set latest tag
	#
	if [ -n "${SETUP_IMAGE_STANDARD_LATEST_VERSTR}" ]; then
		PRNMSG "Set ${SETUP_IMAGE_STANDARD_LATEST_VERSTR} tag to ${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_TROVE} image."
		if ({ docker tag "${_TMP_IMAGE_ID}" "${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_TROVE}:${SETUP_IMAGE_STANDARD_LATEST_VERSTR}" 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to set ${SETUP_IMAGE_STANDARD_LATEST_VERSTR} tag \"${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_TROVE}:${SETUP_IMAGE_STANDARD_LATEST_VERSTR}\" to \"${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_TROVE}:${SETUP_IMAGE_VERSTR}\" image."
			exit 1
		fi
		PRNINFO "Set ${SETUP_IMAGE_STANDARD_LATEST_VERSTR} tag to ${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_TROVE} image."
	fi

	#
	# Create k2hdkc-trove-backup:<version>-<os> image
	#
	PRNMSG "Create ${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_BACKUP}:${SETUP_IMAGE_VERSTR} image."
	if ({ docker image build --progress=plain --build-arg "${BUILD_ARG_HTTP_PROXY}" --build-arg "${BUILD_ARG_HTTPS_PROXY}" --build-arg "${BUILD_ARG_NO_PROXY}" -f "${K2HDKC_BACKUP_DOCKERFILE_NAME}" -t "${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_BACKUP}:${SETUP_IMAGE_VERSTR}" . 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
		PRNERR "Failed to create \"${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_BACKUP}:${SETUP_IMAGE_VERSTR}\" image from ${K2HDKC_BACKUP_DOCKERFILE}."
		exit 1
	fi
	PRNINFO "Created ${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_BACKUP}:${SETUP_IMAGE_VERSTR} image."

	#
	# Set latest-<os> tag
	#
	PRNMSG "Set ${SETUP_IMAGE_LATEST_VERSTR} tag to ${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_BACKUP} image."
	if ! _TMP_IMAGE_ID=$(docker image ls 2>/dev/null | awk '{print $1" "$2" "$3}' | grep "${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_BACKUP} ${SETUP_IMAGE_VERSTR}" | awk '{print $3}'); then
		PRNERR "Not found ${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_BACKUP}:${SETUP_IMAGE_VER} image id."
		exit 1
	fi
	if [ -z "${_TMP_IMAGE_ID}" ]; then
		PRNERR "Not found ${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_BACKUP}:${SETUP_IMAGE_VERSTR} image id."
		exit 1
	fi
	if ({ docker tag "${_TMP_IMAGE_ID}" "${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_BACKUP}:${SETUP_IMAGE_LATEST_VERSTR}" 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
		PRNERR "Failed to set ${SETUP_IMAGE_LATEST_VERSTR} tag \"${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_BACKUP}:${SETUP_IMAGE_LATEST_VERSTR}\" to \"${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_BACKUP}:${SETUP_IMAGE_VERSTR}\" image."
		exit 1
	fi
	PRNINFO "Set ${SETUP_IMAGE_LATEST_VERSTR} tag to ${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_BACKUP} image."

	#
	# Set <version> tag
	#
	if [ -n "${SETUP_IMAGE_STANDARD_VERSTR}" ]; then
		PRNMSG "Set ${SETUP_IMAGE_STANDARD_VERSTR} tag to ${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_BACKUP} image."
		if ({ docker tag "${_TMP_IMAGE_ID}" "${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_BACKUP}:${SETUP_IMAGE_STANDARD_VERSTR}" 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to set ${SETUP_IMAGE_STANDARD_VERSTR} tag \"${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_BACKUP}:${SETUP_IMAGE_STANDARD_VERSTR}\" to \"${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_BACKUP}:${SETUP_IMAGE_VERSTR}\" image."
			exit 1
		fi
		PRNINFO "Set ${SETUP_IMAGE_STANDARD_VERSTR} tag to ${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_BACKUP} image."
	fi

	#
	# Set latest tag
	#
	if [ -n "${SETUP_IMAGE_STANDARD_LATEST_VERSTR}" ]; then
		PRNMSG "Set ${SETUP_IMAGE_STANDARD_LATEST_VERSTR} tag to ${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_BACKUP} image."
		if ({ docker tag "${_TMP_IMAGE_ID}" "${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_BACKUP}:${SETUP_IMAGE_STANDARD_LATEST_VERSTR}" 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to set ${SETUP_IMAGE_STANDARD_LATEST_VERSTR} tag \"${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_BACKUP}:${SETUP_IMAGE_STANDARD_LATEST_VERSTR}\" to \"${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_BACKUP}:${SETUP_IMAGE_VERSTR}\" image."
			exit 1
		fi
		PRNINFO "Set ${SETUP_IMAGE_STANDARD_LATEST_VERSTR} tag to ${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_BACKUP} image."
	fi

	#
	# Print information
	#
	PRNMSG "Image List"
	docker image ls | grep -e "${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_TROVE}" -e "${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_BACKUP}" 2>&1 | sed -e 's|^|    |g'

	PRNSUCCESS "Build Docker Images"
fi

#==============================================================
# Upload Docker Image
#==============================================================
if [ "${RUN_LEVEL}" -ge 4 ]; then

	PRNTITLE "Upload Docker Images"

	#
	# Check pushing images is allowed
	#
	if [ "${ENABLE_PUSH_IMAGE}" -eq 0 ]; then
		PRNERR "The pushing images is restricted by this script. Uploading images from this environment is not permitted. (ex, pushing from CI is allowed)"
		exit 1
	fi

	#
	# Remove local images
	#
	# [NOTE]
	# In the case of the official Docker Registry, it cannot be deleted.
	#
	PRNMSG "Check and Remove images in private registry."
	if ! RemovePrivateRegistryImages; then
		exit 1
	fi
	PRNINFO "Remove images in private registry."

	#---------------------------------------------------------
	# Upload k2hdkc-trove image
	#---------------------------------------------------------
	#
	# Upload k2hdkc-trove:<version>-<os> image
	#
	PRNMSG "Push image \"${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_TROVE}:${SETUP_IMAGE_VERSTR}\"."
	if ({ docker push "${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_TROVE}:${SETUP_IMAGE_VERSTR}" 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
		PRNERR "Failed to push image \"${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_TROVE}:${SETUP_IMAGE_VERSTR}\"."
		exit 1
	fi
	PRNINFO "Pushed image \"${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_TROVE}:${SETUP_IMAGE_VERSTR}\"."

	#
	# Upload k2hdkc-trove:latest-<os> image
	#
	PRNMSG "Push image \"${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_TROVE}:${SETUP_IMAGE_LATEST_VERSTR}\"."
	if ({ docker push "${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_TROVE}:${SETUP_IMAGE_LATEST_VERSTR}" 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
		PRNERR "Failed to push image \"${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_TROVE}:${SETUP_IMAGE_LATEST_VERSTR}\"."
		exit 1
	fi
	PRNINFO "Pushed image \"${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_TROVE}:${SETUP_IMAGE_LATEST_VERSTR}\"."

	#
	# Upload k2hdkc-trove:<version> image
	#
	if [ -n "${SETUP_IMAGE_STANDARD_VERSTR}" ]; then
		PRNMSG "Push image \"${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_TROVE}:${SETUP_IMAGE_STANDARD_VERSTR}\"."
		if ({ docker push "${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_TROVE}:${SETUP_IMAGE_STANDARD_VERSTR}" 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to push image \"${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_TROVE}:${SETUP_IMAGE_STANDARD_VERSTR}\"."
			exit 1
		fi
		PRNINFO "Pushed image \"${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_TROVE}:${SETUP_IMAGE_STANDARD_VERSTR}\"."
	fi

	#
	# Upload k2hdkc-trove:latest image
	#
	if [ -n "${SETUP_IMAGE_STANDARD_LATEST_VERSTR}" ]; then
		PRNMSG "Push image \"${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_TROVE}:${SETUP_IMAGE_STANDARD_LATEST_VERSTR}\"."
		if ({ docker push "${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_TROVE}:${SETUP_IMAGE_STANDARD_LATEST_VERSTR}" 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to push image \"${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_TROVE}:${SETUP_IMAGE_STANDARD_LATEST_VERSTR}\"."
			exit 1
		fi
		PRNINFO "Pushed image \"${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_TROVE}:${SETUP_IMAGE_STANDARD_LATEST_VERSTR}\"."
	fi

	#---------------------------------------------------------
	# Upload k2hdkc-trove-backup image
	#---------------------------------------------------------
	#
	# Upload k2hdkc-trove-backup:<version>-<os> image
	#
	PRNMSG "Push image \"${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_BACKUP}:${SETUP_IMAGE_VERSTR}\"."
	if ({ docker push "${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_BACKUP}:${SETUP_IMAGE_VERSTR}" 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
		PRNERR "Failed to push image \"${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_BACKUP}:${SETUP_IMAGE_VERSTR}\"."
		exit 1
	fi
	PRNINFO "Pushed image \"${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_BACKUP}:${SETUP_IMAGE_VERSTR}\"."


	#
	# Upload k2hdkc-trove-backup:latest-<os> image
	#
	PRNMSG "Push image \"${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_BACKUP}:${SETUP_IMAGE_LATEST_VERSTR}\"."
	if ({ docker push "${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_BACKUP}:${SETUP_IMAGE_LATEST_VERSTR}" 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
		PRNERR "Failed to push image \"${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_BACKUP}:${SETUP_IMAGE_LATEST_VERSTR}\"."
		exit 1
	fi
	PRNINFO "Pushed image \"${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_BACKUP}:${SETUP_IMAGE_LATEST_VERSTR}\"."

	#
	# Upload k2hdkc-trove-backup:<version> image
	#
	if [ -n "${SETUP_IMAGE_STANDARD_VERSTR}" ]; then
		PRNMSG "Push image \"${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_BACKUP}:${SETUP_IMAGE_STANDARD_VERSTR}\"."
		if ({ docker push "${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_BACKUP}:${SETUP_IMAGE_STANDARD_VERSTR}" 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to push image \"${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_BACKUP}:${SETUP_IMAGE_STANDARD_VERSTR}\"."
			exit 1
		fi
		PRNINFO "Pushed image \"${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_BACKUP}:${SETUP_IMAGE_STANDARD_VERSTR}\"."
	fi

	#
	# Upload k2hdkc-trove-backup:latest image
	#
	if [ -n "${SETUP_IMAGE_STANDARD_LATEST_VERSTR}" ]; then
		PRNMSG "Push image \"${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_BACKUP}:${SETUP_IMAGE_STANDARD_LATEST_VERSTR}\"."
		if ({ docker push "${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_BACKUP}:${SETUP_IMAGE_STANDARD_LATEST_VERSTR}" 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to push image \"${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_BACKUP}:${SETUP_IMAGE_STANDARD_LATEST_VERSTR}\"."
			exit 1
		fi
		PRNINFO "Pushed image \"${SETUP_PUSH_REGISTRY}${SETUP_PUSH_REPOSITORY}/${IMAGENAME_K2HDKC_BACKUP}:${SETUP_IMAGE_STANDARD_LATEST_VERSTR}\"."
	fi

	PRNSUCCESS "Upload Docker Images"
fi

#==============================================================
# Finish
#==============================================================
exit 0

#
# Local variables:
# tab-width: 4
# c-basic-offset: 4
# End:
# vim600: noexpandtab sw=4 ts=4 fdm=marker
# vim<600: noexpandtab sw=4 ts=4
#
