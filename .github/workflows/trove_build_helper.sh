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
# CREATE:   Fri Dec 13 2024
# REVISION:
#

#==============================================================
# Build helper for K2HDKC DBaaS Trove on Github Actions
#==============================================================
#
# Instead of pipefail(for shells not support "set -o pipefail")
#
PIPEFAILURE_FILE="/tmp/.pipefailure.$(od -An -tu4 -N4 /dev/random | tr -d ' \n')"

#
# For shellcheck
#
if command -v locale >/dev/null 2>&1; then
	if locale -a | grep -q -i '^[[:space:]]*C.utf8[[:space:]]*$'; then
		LANG=$(locale -a | grep -i '^[[:space:]]*C.utf8[[:space:]]*$' | sed -e 's/^[[:space:]]*//g' -e 's/[[:space:]]*$//g' | tr -d '\n')
		LC_ALL="${LANG}"
		export LANG
		export LC_ALL
	elif locale -a | grep -q -i '^[[:space:]]*en_US.utf8[[:space:]]*$'; then
		LANG=$(locale -a | grep -i '^[[:space:]]*en_US.utf8[[:space:]]*$' | sed -e 's/^[[:space:]]*//g' -e 's/[[:space:]]*$//g' | tr -d '\n')
		LC_ALL="${LANG}"
		export LANG
		export LC_ALL
	fi
fi

#==============================================================
# Common variables
#==============================================================
PRGNAME=$(basename "$0")
SCRIPTDIR=$(dirname "$0")
SCRIPTDIR=$(cd "${SCRIPTDIR}" || exit 1; pwd)
SRCTOP=$(cd "${SCRIPTDIR}"/../.. || exit 1; pwd)
BUILDUTILDIR=$(cd "${SRCTOP}"/buildutils || exit 1; pwd)

#
# Configuration variables
#
RELEASE_VERSION_FILE="${SRCTOP}/RELEASE_VERSION"
K2HDKC_IMAGE_VERSION_FILE="/tmp/.K2HDKC_IMAGE_VERSION.$$"

#
# Message variables
#
IN_GHAGROUP_AREA=0

#
# Variables with default values
#
CI_OSTYPE_VARS_FILE="${SCRIPTDIR}/trove_ostypevars.sh"
CI_FORCE_PUBLISH=""
CI_IN_SCHEDULE_PROCESS=0
CI_DO_PUSH=0

#==============================================================
# Utility functions and variables for messaging
#==============================================================
#
# Utilities for message
#
if [ -t 1 ] || { [ -n "${CI}" ] && [ "${CI}" = "true" ]; }; then
	CBLD=$(printf '\033[1m')
	CREV=$(printf '\033[7m')
	CRED=$(printf '\033[31m')
	CYEL=$(printf '\033[33m')
	CGRN=$(printf '\033[32m')
	CDEF=$(printf '\033[0m')
else
	CBLD=""
	CREV=""
	CRED=""
	CYEL=""
	CGRN=""
	CDEF=""
fi
if [ -n "${CI}" ] && [ "${CI}" = "true" ]; then
	GHAGRP_START="::group::"
	GHAGRP_END="::endgroup::"
else
	GHAGRP_START=""
	GHAGRP_END=""
fi

PRNGROUPEND()
{
	if [ -n "${IN_GHAGROUP_AREA}" ] && [ "${IN_GHAGROUP_AREA}" -eq 1 ]; then
		if [ -n "${GHAGRP_END}" ]; then
			echo "${GHAGRP_END}"
		fi
	fi
	IN_GHAGROUP_AREA=0
}
PRNTITLE()
{
	PRNGROUPEND
	echo "${GHAGRP_START}${CBLD}${CGRN}${CREV}[TITLE]${CDEF} ${CGRN}$*${CDEF}"
	IN_GHAGROUP_AREA=1
}
PRNINFO()
{
	echo "${CBLD}${CREV}[INFO]${CDEF} $*"
}
PRNWARN()
{
	echo "${CBLD}${CYEL}${CREV}[WARNING]${CDEF} ${CYEL}$*${CDEF}"
}
PRNERR()
{
	echo "${CBLD}${CRED}${CREV}[ERROR]${CDEF} ${CRED}$*${CDEF}"
	PRNGROUPEND
}
PRNSUCCESS()
{
	echo "${CBLD}${CGRN}${CREV}[SUCCEED]${CDEF} ${CGRN}$*${CDEF}"
	PRNGROUPEND
}
PRNFAILURE()
{
	echo "${CBLD}${CRED}${CREV}[FAILURE]${CDEF} ${CRED}$*${CDEF}"
	PRNGROUPEND
}
RUNCMD()
{
	PRNINFO "Run \"$*\""
	if ! /bin/sh -c "$*"; then
		PRNERR "Failed to run \"$*\""
		return 1
	fi
	return 0
}

#==============================================================
# Execution functions
#==============================================================
#
# Configure
#
# [NOTE]
# This process sets the K2HDKC_DOCKER_IMAGE_VERSION variable into
# K2HDKC_IMAGE_VERSION_FILE file and creates the RELEASE_VERSION file.
#
run_configure()
{
	#
	# Set K2HDKC_DOCKER_IMAGE_VERSION variables
	#
	if ! K2HDKC_DOCKER_IMAGE_VERSION=$(curl https://hub.docker.com/v2/repositories/antpickax/k2hdkc/tags 2>/dev/null | python -m json.tool | grep '\"name\"' | sed -e 's#^[[:space:]]*"name"[[:space:]]*[:][[:space:]]*##gi' -e 's#"##g' -e 's#,##g' -e 's#[-].*$##g' -e 's#[[space:]]*$##g' | grep -v 'latest' | sort -r | uniq | head -1 | tr -d '\n'); then
		PRNWARN "Could not get the latest version number of K2HDKC docker image from DockerHub(antpickax/k2hdkc), but use 1.0.15 for fault tolerant."
		K2HDKC_DOCKER_IMAGE_VERSION="1.0.15"
	fi
	printf '%s' "${K2HDKC_DOCKER_IMAGE_VERSION}" > "${K2HDKC_IMAGE_VERSION_FILE}"

	#
	# Create/Update RELEASE_VERSION
	#
	# [NOTE]
	# When generating a Docker image, the release version is required.
	# Therefore, create and update the RELEASE_VERSION file as the current user.
	#
	if [ ! -f "${BUILDUTILDIR}/make_release_version_file.sh" ]; then
		PRNERR "Not found ${BUILDUTILDIR}/make_release_version_file.sh file."
		exit 1
	fi
	if ({ /bin/sh -c "${BUILDUTILDIR}/make_release_version_file.sh" 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
		PRNERR "Failed to create(update) ${RELEASE_VERSION_FILE} file by ${BUILDUTILDIR}/make_release_version_file.sh."
		exit 1
	fi
	if [ ! -f "${RELEASE_VERSION_FILE}" ]; then
		PRNERR "Not found ${RELEASE_VERSION_FILE} file."
		exit 1
	fi

	return 0
}

#
# ShellCheck
#
run_shellcheck()
{
	SHELLCHECK_IGN_OPT="SC1117,SC1090,SC1091,SC2034"

	if ! shellcheck --shell=sh --exclude="${SHELLCHECK_IGN_OPT}" "${BUILDUTILDIR}"/*.sh; then
		PRNERR "Failed to run shellcheck"
		return 1
	fi
	if ! shellcheck --shell=sh --exclude="${SHELLCHECK_IGN_OPT}" "${SRCTOP}"/.github/workflows/*.sh; then
		PRNERR "Failed to run shellcheck"
		return 1
	fi
	return 0
}

#
# Test for patches
#
run_test()
{
	if ! "${BUILDUTILDIR}/k2hdkcstack.sh" patch_test; then
		PRNERR "Failed to test patch files"
		return 1
	fi
	return 0
}

#
# Build/Push docker image
#
run_dockerimage()
{
	#
	# Docker Image Type string
	#
	if echo "${CI_DOCKER_IMAGE_TYPE}" | grep -q -i "ubuntu"; then
		DOCKER_IMAGE_TYPE_STRING="ubuntu"
	elif echo "${CI_DOCKER_IMAGE_TYPE}" | grep -q -i "rocky"; then
		DOCKER_IMAGE_TYPE_STRING="rocky"
	elif echo "${CI_DOCKER_IMAGE_TYPE}" | grep -q -i "alpine"; then
		DOCKER_IMAGE_TYPE_STRING="alpine"
	else
		PRNERR "Unknown Docker Image Type."
		return 1
	fi

	#
	# Versions
	#
	TROVE_RELEASE_VERSION=$(tr -d '\n' < "${RELEASE_VERSION_FILE}")
	K2HDKC_DOCKER_IMAGE_VERSION=$(tr -d '\n' < "${K2HDKC_IMAGE_VERSION_FILE}")
	if [ -z "${TROVE_RELEASE_VERSION}" ] || [ -z "${K2HDKC_DOCKER_IMAGE_VERSION}" ]; then
		PRNERR "Not set Trove release version(${TROVE_RELEASE_VERSION}) or K2HDKC lastest version(${K2HDKC_DOCKER_IMAGE_VERSION})."
		return 1
	fi

	#
	# Configuration file
	#
	if echo "${CI_USE_PRIVATE_DH_ORG}" | grep -q -i "true"; then
		IMAGETOOL_CONF_OPT="--conf dockerhub-private"
	else
		IMAGETOOL_CONF_OPT=""
	fi
	if [ "${CI_DO_PUSH}" -eq 1 ]; then
		IMAGETOOL_MODE="upload_image"
	else
		IMAGETOOL_MODE="build_image"
	fi

	#
	# Build/Push Docker image
	#
	if ! /bin/sh -c "${BUILDUTILDIR}/k2hdkcdockerimage.sh ${IMAGETOOL_MODE} -o ${DOCKER_IMAGE_TYPE_STRING} -b ${K2HDKC_DOCKER_IMAGE_VERSION} --image-version ${TROVE_RELEASE_VERSION} --trove-repository-clone ${IMAGETOOL_CONF_OPT}"; then
		PRNERR "Failed to build/push Docker image(command: \"k2hdkcdockerimage.sh ${IMAGETOOL_MODE} -o ${DOCKER_IMAGE_TYPE_STRING} -b ${K2HDKC_DOCKER_IMAGE_VERSION} --image-version ${TROVE_RELEASE_VERSION} --trove-repository-clone ${IMAGETOOL_CONF_OPT}\")."
		return 1
	fi

	return 0
}

#----------------------------------------------------------
# Helper for container on Github Actions
#----------------------------------------------------------
func_usage()
{
	echo ""
	echo "Usage: $1 [options...]"
	echo ""
	echo "  Option:"
	echo "    --help(-h)                          print help"
	echo "    --imagetype(-i) <image info>        [Required option] specify the docker image type(ex. \"alpine\")"
	echo "    --ostype-vars-file(-f) <file path>  specify the file that describes the package list to be installed before build(default is trove_ostypevars.sh)"
	echo "    --force-publish(-p)                 force the docker image to be uploaded. normally the image is uploaded only when it is tagged(determined from GITHUB_REF/GITHUB_EVENT_NAME)."
	echo "    --not-publish(-np)                  do not force publish the docker image."
	echo "    --push-private-dh-org(-org)         use private organization on DockerHub.(default: use \"antpickax\")"
	echo ""
	echo "  Environments:"
	echo "    ENV_DOCKER_IMAGE_TYPE               the docker image type                                ( same as option '--imagetype(-i)' )"
	echo "    ENV_OSTYPE_VARS_FILE                the file that describes the package list             ( same as option '--ostype-vars-file(-f)' )"
	echo "    ENV_FORCE_PUBLISH                   force the release package to be uploaded: true/false ( same as option '--force-publish(-p)' and '--not-publish(-np)' )"
	echo "    ENV_USE_PRIVATE_DH_ORG              use private organization on DockerHub: true/false    ( same as option '--push-private-dh-org(-org)' )"
	echo "    GITHUB_REF                          use internally for release tag"
	echo "    GITHUB_EVENT_NAME                   use internally for checking schedule processing"
	echo ""
	echo "  Note:"
	echo "    Environment variables and options have the same parameter items."
	echo "    If both are specified, the option takes precedence."
	echo "    Environment variables are set from Github Actions Secrets, etc."
	echo "    GITHUB_REF and GITHUB_EVENT_NAME environments are used internally."
	echo ""
}

#==============================================================
# Check options and environments
#==============================================================
PRNTITLE "Start to check options and environments"

#
# Parse options
#
OPT_DOCKER_IMAGE_TYPE=""
OPT_OSTYPE_VARS_FILE=""
OPT_FORCE_PUBLISH=""
OPT_USE_PRIVATE_DH_ORG=""

while [ $# -ne 0 ]; do
	if [ -z "$1" ]; then
		break

	elif echo "$1" | grep -q -i -e "-h" -e "--help"; then
		func_usage "${PRGNAME}"
		exit 0

	elif echo "$1" | grep -q -i -e "-i" -e "--imagetype"; then
		if [ -n "${OPT_DOCKER_IMAGE_TYPE}" ]; then
			PRNERR "already set \"--imagetype(-i)\" option."
			exit 1
		fi
		shift
		if [ $# -eq 0 ]; then
			PRNERR "\"--imagetype(-i)\" option is specified without parameter."
			exit 1
		fi
		OPT_DOCKER_IMAGE_TYPE="$1"

	elif echo "$1" | grep -q -i -e "-f" -e "--ostype-vars-file"; then
		if [ -n "${OPT_OSTYPE_VARS_FILE}" ]; then
			PRNERR "already set \"--ostype-vars-file(-f)\" option."
			exit 1
		fi
		shift
		if [ $# -eq 0 ]; then
			PRNERR "\"--ostype-vars-file(-f)\" option is specified without parameter."
			exit 1
		fi
		if [ ! -f "$1" ]; then
			PRNERR "$1 file is not existed, it is specified \"--ostype-vars-file(-f)\" option."
			exit 1
		fi
		OPT_OSTYPE_VARS_FILE="$1"

	elif echo "$1" | grep -q -i -e "-p" -e "--force-publish"; then
		if [ -n "${OPT_FORCE_PUBLISH}" ]; then
			PRNERR "already set \"--force-publish(-p)\" or \"--not-publish(-np)\" option."
			exit 1
		fi
		OPT_FORCE_PUBLISH="true"

	elif echo "$1" | grep -q -i -e "-np" -e "--not-publish"; then
		if [ -n "${OPT_FORCE_PUBLISH}" ]; then
			PRNERR "already set \"--force-publish(-p)\" or \"--not-publish(-np)\" option."
			exit 1
		fi
		OPT_FORCE_PUBLISH="false"

	elif echo "$1" | grep -q -i -e "-org" -e "--push-private-dh-org"; then
		if [ -n "${OPT_USE_PRIVATE_DH_ORG}" ]; then
			PRNERR "already set \"--push-private-dh-org(-org)\" option."
			exit 1
		fi
		OPT_USE_PRIVATE_DH_ORG="true"

	else
		PRNERR "Unknown option: $1."
		exit 1
	fi
	shift
done

#
# [Required option] check OS and version
#
if [ -z "${OPT_DOCKER_IMAGE_TYPE}" ]; then
	PRNERR "\"--imagetype(-i)\" option is not specified."
	exit 1
else
	CI_DOCKER_IMAGE_TYPE="${OPT_DOCKER_IMAGE_TYPE}"
fi

#
# Check other options and enviroments
#
if [ -n "${OPT_OSTYPE_VARS_FILE}" ]; then
	CI_OSTYPE_VARS_FILE="${OPT_OSTYPE_VARS_FILE}"
elif [ -n "${ENV_OSTYPE_VARS_FILE}" ]; then
	CI_OSTYPE_VARS_FILE="${ENV_OSTYPE_VARS_FILE}"
fi

if [ -n "${OPT_FORCE_PUBLISH}" ]; then
	if echo "${OPT_FORCE_PUBLISH}" | grep -q -i '^true$'; then
		CI_FORCE_PUBLISH="true"
	elif echo "${OPT_FORCE_PUBLISH}" | grep -q -i '^false$'; then
		CI_FORCE_PUBLISH="false"
	else
		PRNERR "\"OPT_FORCE_PUBLISH\" value is wrong."
		exit 1
	fi
elif [ -n "${ENV_FORCE_PUBLISH}" ]; then
	if echo "${ENV_FORCE_PUBLISH}" | grep -q -i '^true$'; then
		CI_FORCE_PUBLISH="true"
	elif echo "${ENV_FORCE_PUBLISH}" | grep -q -i '^false$'; then
		CI_FORCE_PUBLISH="false"
	else
		PRNERR "\"ENV_FORCE_PUBLISH\" value is wrong."
		exit 1
	fi
fi

if [ -n "${OPT_USE_PRIVATE_DH_ORG}" ]; then
	if echo "${OPT_USE_PRIVATE_DH_ORG}" | grep -q -i '^true$'; then
		CI_USE_PRIVATE_DH_ORG="true"
	else
		PRNERR "\"OPT_USE_PRIVATE_DH_ORG\" value is wrong."
		exit 1
	fi
elif [ -n "${ENV_USE_PRIVATE_DH_ORG}" ]; then
	if echo "${ENV_USE_PRIVATE_DH_ORG}" | grep -q -i '^true$'; then
		CI_USE_PRIVATE_DH_ORG="true"
	elif echo "${ENV_USE_PRIVATE_DH_ORG}" | grep -q -i '^false$'; then
		CI_USE_PRIVATE_DH_ORG="false"
	else
		PRNERR "\"ENV_USE_PRIVATE_DH_ORG\" value is wrong."
		exit 1
	fi
else
	CI_USE_PRIVATE_DH_ORG="false"
fi

# [NOTE] for ubuntu/debian
# When start to update, it may come across an unexpected interactive interface.
# (May occur with time zone updates)
# Set environment variables to avoid this.
#
export DEBIAN_FRONTEND=noninteractive

PRNSUCCESS "Start to check options and environments"

#==============================================================
# Set Variables
#==============================================================
#
# Load variables from file
#
PRNTITLE "Load local variables with an external file"

#
# Load external variable file
#
if [ -f "${CI_OSTYPE_VARS_FILE}" ]; then
	PRNINFO "Load ${CI_OSTYPE_VARS_FILE} file for local variables by OS"
	. "${CI_OSTYPE_VARS_FILE}"
else
	PRNWARN "${CI_OSTYPE_VARS_FILE} file is not existed."
fi

PRNSUCCESS "Load local variables with an external file"

#----------------------------------------------------------
# Check github actions environments
#----------------------------------------------------------
PRNTITLE "Check github actions environments"

#
# GITHUB_EVENT_NAME Environment
#
if [ -n "${GITHUB_EVENT_NAME}" ] && [ "${GITHUB_EVENT_NAME}" = "schedule" ]; then
	CI_IN_SCHEDULE_PROCESS=1
else
	CI_IN_SCHEDULE_PROCESS=0
fi

#
# GITHUB_REF Environments
#
if [ -n "${GITHUB_REF}" ] && echo "${GITHUB_REF}" | grep -q 'refs/tags/'; then
	CI_PUBLISH_TAG_NAME=$(echo "${GITHUB_REF}" | sed -e 's#refs/tags/##g' | tr -d '\n')
fi

PRNSUCCESS "Check github actions environments"

#----------------------------------------------------------
# Check whether to publish
#----------------------------------------------------------
PRNTITLE "Check whether to publish"

#
# Check whether to publish
#
if [ -z "${CI_FORCE_PUBLISH}" ]; then
	if [ -n "${CI_PUBLISH_TAG_NAME}" ] && [ "${CI_IN_SCHEDULE_PROCESS}" -ne 1 ]; then
		CI_DO_PUSH=1
	else
		CI_DO_PUSH=0
	fi
elif [ "${CI_FORCE_PUBLISH}" = "true" ]; then
	#
	# Force publishing
	#
	if [ -n "${CI_PUBLISH_TAG_NAME}" ] && [ "${CI_IN_SCHEDULE_PROCESS}" -ne 1 ]; then
		PRNINFO "specified \"--force-publish(-p)\" option or set \"ENV_FORCE_PUBLISH=true\" environment, then forcibly publish"
		CI_DO_PUSH=1
	else
		PRNWARN "specified \"--force-publish(-p)\" option or set \"ENV_FORCE_PUBLISH=true\" environment, but Ci was launched by schedule or did not have tag name. Thus it do not run publishing."
		CI_DO_PUSH=0
	fi
else
	#
	# FORCE NOT PUBLISH
	#
	PRNINFO "specified \"--not-publish(-np)\" option or set \"ENV_FORCE_PUBLISH=false\" environment, then it do not run publishing."
	CI_DO_PUSH=0
fi

PRNSUCCESS "Check whether to publish"

#----------------------------------------------------------
# Show execution environment variables
#----------------------------------------------------------
PRNTITLE "Show execution environment variables"

#
# Information
#
echo "  PRGNAME                = ${PRGNAME}"
echo "  SCRIPTDIR              = ${SCRIPTDIR}"
echo "  SRCTOP                 = ${SRCTOP}"
echo ""
echo "  CI_IN_SCHEDULE_PROCESS = ${CI_IN_SCHEDULE_PROCESS}"
echo "  CI_OSTYPE_VARS_FILE    = ${CI_OSTYPE_VARS_FILE}"
echo "  CI_DOCKER_IMAGE_TYPE   = ${CI_DOCKER_IMAGE_TYPE}"
echo "  CI_DO_PUSH             = ${CI_DO_PUSH}"
echo "  CI_PUBLISH_TAG_NAME    = ${CI_PUBLISH_TAG_NAME}"
echo "  CI_USE_PRIVATE_DH_ORG  = ${CI_USE_PRIVATE_DH_ORG}"
echo ""
echo "  BASE_OS_UBUNTU         = ${BASE_OS_UBUNTU}"
echo "  BASE_OS_ROCKY          = ${BASE_OS_ROCKY}"
echo "  BASE_OS_ALPINE         = ${BASE_OS_ALPINE}"
echo "  INSTALL_PKG_LIST       = ${INSTALL_PKG_LIST}"
echo "  INSTALLER_BIN          = ${INSTALLER_BIN}"
echo "  UPDATE_CMD             = ${UPDATE_CMD}"
echo "  UPDATE_CMD_ARG         = ${UPDATE_CMD_ARG}"
echo "  INSTALL_CMD            = ${INSTALL_CMD}"
echo "  INSTALL_CMD_ARG        = ${INSTALL_CMD_ARG}"
echo "  INSTALL_AUTO_ARG       = ${INSTALL_AUTO_ARG}"
echo "  INSTALL_QUIET_ARG      = ${INSTALL_QUIET_ARG}"
echo ""

PRNSUCCESS "Show execution environment variables"

#==============================================================
# Install all packages
#==============================================================
PRNTITLE "Update repository and Install curl"

#
# Update local packages
#
PRNINFO "Update local packages"
if ({ RUNCMD sudo "${INSTALLER_BIN}" "${UPDATE_CMD}" "${UPDATE_CMD_ARG}" "${INSTALL_AUTO_ARG}" "${INSTALL_QUIET_ARG}" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
	PRNERR "Failed to update local packages"
	exit 1
fi

#
# Check and install curl
#
if ! CURLCMD=$(command -v curl); then
	PRNINFO "Install curl command"
	if ({ RUNCMD sudo "${INSTALLER_BIN}" "${INSTALL_CMD}" "${INSTALL_CMD_ARG}" "${INSTALL_AUTO_ARG}" "${INSTALL_QUIET_ARG}" curl || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
		PRNERR "Failed to install curl command"
		exit 1
	fi
	if ! CURLCMD=$(command -v curl); then
		PRNERR "Not found curl command"
		exit 1
	fi
else
	PRNINFO "Already curl is insatlled."
fi
PRNSUCCESS "Update repository and Install curl"

#--------------------------------------------------------------
# Install packages
#--------------------------------------------------------------
PRNTITLE "Install packages for building/packaging"

if [ -n "${INSTALL_PKG_LIST}" ]; then
	PRNINFO "Install packages"
	if ({ RUNCMD sudo "${INSTALLER_BIN}" "${INSTALL_CMD}" "${INSTALL_CMD_ARG}" "${INSTALL_AUTO_ARG}" "${INSTALL_QUIET_ARG}" "${INSTALL_PKG_LIST}" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
		PRNERR "Failed to install packages"
		exit 1
	fi
else
	PRNINFO "Specified no packages for installing. "
fi

PRNSUCCESS "Install packages for building/packaging"

#--------------------------------------------------------------
# Install shellcheck
#--------------------------------------------------------------
PRNTITLE "Install shellcheck"

if [ "${BASE_OS_ROCKY}" -eq 1 ]; then
	#
	# Rocky
	#
	PRNINFO "Install shellcheck package for RockyLinux."

	if ! LATEST_SHELLCHECK_DOWNLOAD_URL=$("${CURLCMD}" -s -S https://api.github.com/repos/koalaman/shellcheck/releases/latest | tr '{' '\n' | tr '}' '\n' | tr '[' '\n' | tr ']' '\n' | tr ',' '\n' | grep '"browser_download_url"' | grep 'linux.x86_64' | sed -e 's|"||g' -e 's|^.*browser_download_url:[[:space:]]*||g' -e 's|^[[:space:]]*||g' -e 's|[[:space:]]*$||g' | tr -d '\n'); then
		PRNERR "Failed to get shellcheck download url path"
		exit 1
	fi
	if ({ RUNCMD "${CURLCMD}" -s -S -L -o /tmp/shellcheck.tar.xz "${LATEST_SHELLCHECK_DOWNLOAD_URL}" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
		PRNERR "Failed to download latest shellcheck tar.xz"
		exit 1
	fi
	if ({ RUNCMD sudo tar -C /usr/bin/ -xf /tmp/shellcheck.tar.xz --no-anchored 'shellcheck' --strip=1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
		PRNERR "Failed to extract latest shellcheck binary"
		exit 1
	fi
	rm -f /tmp/shellcheck.tar.xz

elif [ "${BASE_OS_UBUNTU}" -eq 1 ]; then
	#
	# Ubuntu
	#
	PRNINFO "Install shellcheck package for Ubuntu."

	if ({ RUNCMD sudo "${INSTALLER_BIN}" "${INSTALL_CMD}" "${INSTALL_CMD_ARG}" "${INSTALL_AUTO_ARG}" shellcheck || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
		PRNERR "Failed to install shellcheck"
		exit 1
	fi

elif [ "${BASE_OS_ALPINE}" -eq 1 ]; then
	#
	# Alpine
	#
	PRNINFO "Install shellcheck package for ALPINE."

	if ({ RUNCMD sudo "${INSTALLER_BIN}" "${INSTALL_CMD}" "${INSTALL_CMD_ARG}" "${INSTALL_AUTO_ARG}" shellcheck || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
		PRNERR "Failed to install shellcheck"
		exit 1
	fi

else
	PRNINFO "Skip to install shellcheck package, because unknown to install it."
fi
PRNSUCCESS "Install shellcheck"

#==============================================================
# Processing
#==============================================================
#
# Change current directory
#
PRNTITLE "Change current directory"

if ! RUNCMD cd "${SRCTOP}"; then
	PRNERR "Failed to chnage current directory to ${SRCTOP}"
	exit 1
fi
PRNSUCCESS "Changed current directory"

#--------------------------------------------------------------
# Configure
#--------------------------------------------------------------
PRNTITLE "Configure"
if ({ run_configure 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
	PRNFAILURE "Failed \"Configure\"."
	exit 1
fi
PRNSUCCESS "Configure."

#--------------------------------------------------------------
# ShellCheck
#--------------------------------------------------------------
PRNTITLE "Check by ShellCheck"
if ({ run_shellcheck 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
	PRNFAILURE "Failed \"Check before building : ShellCheck\"."
	exit 1
fi
PRNSUCCESS "Check before building : ShellCheck."

#--------------------------------------------------------------
# Test
#--------------------------------------------------------------
PRNTITLE "Test Patches"
if ({ run_test 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
	PRNFAILURE "Failed \"Test Patches\"."
	exit 1
fi
PRNSUCCESS "Test Patches."

#--------------------------------------------------------------
# Build/Push Docker image
#--------------------------------------------------------------
PRNTITLE "Build/Push Docker image"
if ({ run_dockerimage 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
	PRNFAILURE "Failed \"Build/Push Docker image\"."
	exit 1
fi
PRNSUCCESS "Build/Push Docker image."

#----------------------------------------------------------
# Finish
#----------------------------------------------------------
PRNSUCCESS "Finished all processing without error."

exit 0

#
# Local variables:
# tab-width: 4
# c-basic-offset: 4
# End:
# vim600: noexpandtab sw=4 ts=4 fdm=marker
# vim<600: noexpandtab sw=4 ts=4
#
