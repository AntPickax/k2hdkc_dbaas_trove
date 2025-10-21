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
# CREATE:   Thu Sep 26 2024
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
SRCTOPDIRNAME=$(basename "${SRCTOPDIR}")

#
# Variable about local host
#
MYHOSTNAME=$(hostname -f)

ROOT_USER_NAME="root"
STACK_USER_NAME="stack"
STACK_USER_HOME="/opt/${STACK_USER_NAME}"
STACK_USER_SHELL="/bin/bash"

#
# Variable about devstack
#
# [NOTE]
# The value of DEVSTACK_BRANCH is specified in the DEFAULT_DEVSTACK_BRANCH file or option.
#
DEVSTACK_NAME="devstack"
DEVSTACK_START_SH="stack.sh"
DEVSTACK_CLEAN_SH="unstack.sh"
DEVSTACK_IP_RANGE="172.24.0.0/13"
DEVSTACK_DEFAULT_PASSWORD="password"

#
# Variables about Repositories
#
DEVSTACK_GIT_NAME="${DEVSTACK_NAME}"
DEVSTACK_GIT_TOP_DIR="${STACK_USER_HOME}/${DEVSTACK_GIT_NAME}"

TROVE_GIT_NAME="trove"
TROVE_GIT_TOP_DIR="${STACK_USER_HOME}/${TROVE_GIT_NAME}"

TROVE_DASHBOARD_GIT_NAME="trove-dashboard"
TROVE_DASHBOARD_GIT_TOP_DIR="${STACK_USER_HOME}/${TROVE_DASHBOARD_GIT_NAME}"

REQUIREMENTS_GIT_NAME="requirements"
REQUIREMENTS_GIT_TOP_DIR="${STACK_USER_HOME}/${REQUIREMENTS_GIT_NAME}"

HORIZON_GIT_NAME="horizon"
HORIZON_GIT_TOP_DIR="${STACK_USER_HOME}/${HORIZON_GIT_NAME}"

NEUTRON_GIT_NAME="neutron"
NEUTRON_GIT_TOP_DIR="${STACK_USER_HOME}/${NEUTRON_GIT_NAME}"

IMAGES_DIR_NAME="images"
IMAGES_TOP_DIR="${STACK_USER_HOME}/${IMAGES_DIR_NAME}"

#
# Summary log file
#
K2HDKCSTACK_SUMMARY_LOG="${STACK_USER_HOME}/logs/${SCRIPTNAME}.log"
K2HR3SETUP_SUMMARY_LOG="${STACK_USER_HOME}/logs/k2hr3setup.sh.log"

#
# Variables about Guest Agnet
#
GUEST_INSTALL_DIR="integration/scripts/files/elements/ubuntu-guest/install.d"
GUEST_INSTALL_SSH_KEY_FILE="${GUEST_INSTALL_DIR}/12-ssh-key-dev"
GUEST_INSTALL_RESOLV_CONF_FILE="${GUEST_INSTALL_DIR}/13-resolv-conf"
GUEST_INSTALL_APT_CONF_FILE="${GUEST_INSTALL_DIR}/14-apt-conf"
GUEST_INSTALL_APT_CONF_FILE="${GUEST_INSTALL_DIR}/14-apt-conf"
GUEST_INSTALL_IPV6DISABLE_CONF_FILE="${GUEST_INSTALL_DIR}/15-ipv6disable-conf"

ETC_TROVE_DIR="/etc/trove"
ETC_TROVE_CONF_FILE="${ETC_TROVE_DIR}/trove.conf"
ETC_TROVE_GUEST_CONF_FILE="${ETC_TROVE_DIR}/trove-guestagent.conf"

#
# Variables about Pathes
#
TROVE_PATCH_DIR_NAME="${TROVE_GIT_NAME}"
TROVE_DASHBOARD_PATCH_DIR_NAME="${TROVE_DASHBOARD_GIT_NAME}"

TROVE_PATCH_TOP_DIR="${SRCTOPDIR}/${TROVE_PATCH_DIR_NAME}"
TROVE_DASHBOARD_PATCH_TOP_DIR="${SRCTOPDIR}/${TROVE_DASHBOARD_PATCH_DIR_NAME}"

PATCHFILE_LIST_FILENAME="patch_list"

#
# Utility file for Functions and Variables
#
COMMON_UTILS_FUNC_FILE="k2hdkcutilfunc.sh"
DEFAULT_DEVSTACK_BRANCH_FILE="DEFAULT_DEVSTACK_BRANCH"

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
	echo ""
	echo "${CBLD}${CRED}[ERROR]${CDEF} ${CRED}$*${CDEF}"
}

PRNWARN()
{
	echo "    ${CYEL}${CREV}[WARNING]${CDEF} $*"
}

PRNMSG()
{
	echo ""
	echo "    ${CYEL}${CREV}[MSG]${CDEF} $*"
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
# shellcheck disable=SC1090
. "${SCRIPTDIR}/${COMMON_UTILS_FUNC_FILE}"

#
# DEVSTACK_BRANCH Variable
#
if [ ! -f "${SRCTOPDIR}/${DEFAULT_DEVSTACK_BRANCH_FILE}" ]; then
	PRNERR "Not found ${SRCTOPDIR}/${DEFAULT_DEVSTACK_BRANCH_FILE} file is not found."
	exit 1
fi
# shellcheck disable=SC1090
. "${SRCTOPDIR}/${DEFAULT_DEVSTACK_BRANCH_FILE}"

#--------------------------------------------------------------
# Confirm function
#--------------------------------------------------------------
#
# $1				: prompt string
# $2				: hide input(1)
# $3				: default string
#
# $?				: result(always 0)
# CONFIRM_RESULT	: user input string
#
confirm_input()
{
	_prompt=" > "
	_hide_mode=0
	_input_default=""

	if [ $# -gt 0 ]; then
		if [ -n "$1" ]; then
			_prompt="$1 > "
		fi
	fi
	shift
	if [ $# -gt 0 ]; then
		if [ "$1" = "1" ]; then
			_hide_mode=1
		fi
	fi
	shift
	if [ $# -gt 0 ]; then
		if [ -n "$1" ]; then
			_input_default="$1"
		fi
	fi

	if [ -t 1 ]; then
		printf '\033[7m[INPUT]\033[0m %s' "${_prompt}"
	else
		printf '[INPUT] %s' "${_prompt}"
	fi

	if [ ${_hide_mode} -eq 1 ]; then
		stty -echo
	fi

	read -r CONFIRM_RESULT

	if [ ${_hide_mode} -eq 1 ]; then
		stty echo
		# shellcheck disable=SC2034
		for _word_cnt in $(seq 1 ${#CONFIRM_RESULT}); do
			printf '%s' "*"
		done
        printf '\n'
	fi

	if [ -z "${CONFIRM_RESULT}" ]; then
		CONFIRM_RESULT="${_input_default}"
	fi

	return 0
}

#--------------------------------------------------------------
# Check and Set PROXY environments
#--------------------------------------------------------------
# [NOTE]
# The PROXY environment variable of the RockyLinux package manager(dnf)
# does not require a schema("http(s)://"), but it is required for Python.
# If no schemas have been assigned, set them here.
# Also add 172.24.0.0/13(which are used by devstack virtual hosts) to
# NO_PROXY.
#
set_scheme_proxy_env()
{
	_BACKUP_HTTP_PROXY="${HTTP_PROXY}"
	_BACKUP_HTTP_PROXY_LOW="${http_proxy}"
	_BACKUP_HTTPS_PROXY="${HTTPS_PROXY}"
	_BACKUP_HTTPS_PROXY_LOW="${https_proxy}"
	_BACKUP_NO_PROXY="${NO_PROXY}"
	_BACKUP_NO_PROXY_LOW="${no_proxy}"

	if [ -n "${_BACKUP_HTTP_PROXY}" ] && echo "${_BACKUP_HTTP_PROXY}" | grep -q -v '://'; then
		HTTP_PROXY="http://${_BACKUP_HTTP_PROXY}"
		export HTTP_PROXY
	fi
	if [ -n "${_BACKUP_HTTP_PROXY_LOW}" ] && echo "${_BACKUP_HTTP_PROXY_LOW}" | grep -q -v '://'; then
		http_proxy="http://${_BACKUP_HTTP_PROXY_LOW}"
		export http_proxy
	fi
	if [ -n "${_BACKUP_HTTPS_PROXY}" ] && echo "${_BACKUP_HTTPS_PROXY}" | grep -q -v '://'; then
		HTTPS_PROXY="http://${_BACKUP_HTTPS_PROXY}"
		export HTTPS_PROXY
	fi
	if [ -n "${_BACKUP_HTTPS_PROXY_LOW}" ] && echo "${_BACKUP_HTTPS_PROXY_LOW}" | grep -q -v '://'; then
		https_proxy="http://${_BACKUP_HTTPS_PROXY_LOW}"
		export https_proxy
	fi
	if [ -n "${_BACKUP_NO_PROXY}" ] && echo "${_BACKUP_NO_PROXY}" | grep -q -v "${DEVSTACK_IP_RANGE}"; then
		NO_PROXY="${_BACKUP_NO_PROXY},${DEVSTACK_IP_RANGE}"
		export NO_PROXY
	fi
	if [ -n "${_BACKUP_NO_PROXY_LOW}" ] && echo "${_BACKUP_NO_PROXY_LOW}" | grep -q -v "${DEVSTACK_IP_RANGE}"; then
		no_proxy="${_BACKUP_NO_PROXY_LOW},${DEVSTACK_IP_RANGE}"
		export no_proxy
	fi

	return 0
}

revert_scheme_proxy_env()
{
	if [ -n "${_BACKUP_HTTP_PROXY}" ]; then
		HTTP_PROXY="${_BACKUP_HTTP_PROXY}"
		export HTTP_PROXY
	fi
	if [ -n "${_BACKUP_HTTP_PROXY_LOW}" ]; then
		http_proxy="${_BACKUP_HTTP_PROXY_LOW}"
		export http_proxy
	fi
	if [ -n "${_BACKUP_HTTPS_PROXY}" ]; then
		HTTPS_PROXY="${_BACKUP_HTTPS_PROXY}"
		export HTTPS_PROXY
	fi
	if [ -n "${_BACKUP_HTTPS_PROXY_LOW}" ]; then
		https_proxy="${_BACKUP_HTTPS_PROXY_LOW}"
		export https_proxy
	fi
	if [ -n "${_BACKUP_NO_PROXY}" ]; then
		NO_PROXY="${_BACKUP_NO_PROXY}"
		export NO_PROXY
	fi
	if [ -n "${_BACKUP_NO_PROXY_LOW}" ]; then
		no_proxy="${_BACKUP_NO_PROXY_LOW}"
		export no_proxy
	fi
	_BACKUP_HTTP_PROXY=""
	_BACKUP_HTTP_PROXY_LOW=""
	_BACKUP_HTTPS_PROXY=""
	_BACKUP_HTTPS_PROXY_LOW=""
	_BACKUP_NO_PROXY=""
	_BACKUP_NO_PROXY_LOW=""

	return 0
}

#--------------------------------------------------------------
# Measurement for Duration time
#--------------------------------------------------------------
SetStartTime()
{
	START_UNIX_TIME=$(date +%s)
}

GetDurationTime()
{
	CURRENT_UNIX_TIME=$(date +%s)

	DURATION_SEC=$((CURRENT_UNIX_TIME - START_UNIX_TIME))
	DURATION_MIN=$((DURATION_SEC / 60))
	DURATION_SEC=$((DURATION_SEC % 60))
	DURATION_HOUR=$((DURATION_MIN / 60))
	DURATION_MIN=$((DURATION_MIN % 60))
	DURATION_DAY=$((DURATION_HOUR / 60))
	DURATION_HOUR=$((DURATION_HOUR % 60))

	DURATION_RESULT=""
	if [ -n "${DURATION_DAY}" ] && [ "${DURATION_DAY}" -gt 0 ]; then
		DURATION_RESULT="${DURATION_DAY} day"
	fi

	if [ -n "${DURATION_RESULT}" ]; then
		if [ -z "${DURATION_HOUR}" ]; then
			DURATION_RESULT="${DURATION_RESULT} 0 hour"
		else
			DURATION_RESULT="${DURATION_RESULT} ${DURATION_HOUR} hour"
		fi
	elif [ -n "${DURATION_HOUR}" ] && [ "${DURATION_HOUR}" -gt 0 ]; then
		DURATION_RESULT="${DURATION_HOUR} hour"
	fi

	if [ -n "${DURATION_RESULT}" ]; then
		if [ -z "${DURATION_MIN}" ]; then
			DURATION_RESULT="${DURATION_RESULT} 0 min"
		else
			DURATION_RESULT="${DURATION_RESULT} ${DURATION_MIN} min"
		fi
	elif [ -n "${DURATION_MIN}" ] && [ "${DURATION_MIN}" -gt 0 ]; then
		DURATION_RESULT="${DURATION_MIN} min"
	fi

	if [ -n "${DURATION_RESULT}" ]; then
		if [ -z "${DURATION_SEC}" ]; then
			DURATION_RESULT="${DURATION_RESULT} 0 sec"
		else
			DURATION_RESULT="${DURATION_RESULT} ${DURATION_SEC} sec"
		fi
	elif [ -n "${DURATION_SEC}" ] && [ "${DURATION_SEC}" -gt 0 ]; then
		DURATION_RESULT="${DURATION_SEC} sec"
	else
		DURATION_RESULT="0 sec"
	fi

	echo "${DURATION_RESULT}"
}

#--------------------------------------------------------------
# Utility functions
#--------------------------------------------------------------
#
# Update patch files
#
# Input	$1	: Top directory to modification files		(ex. "/opt/stack/trove")
#		$2	: Directory in which to place patch files	(ex. "/home/user/k2hdkc_dbaas_trove/trove")
#
UpdatePatchFiles()
{
	if [ $# -lt 2 ]; then
		PRNERR "Parameters are wrong."
		return 1
	fi
	_MODIFICATION_TOP_DIR="$1"
	_PATCH_FILES_TOP_DIR="$2"

	#
	# Patch files list
	#
	_PATCH_FILES_LIST="${_PATCH_FILES_TOP_DIR}/${PATCHFILE_LIST_FILENAME}"
	if [ ! -f "${_PATCH_FILES_LIST}" ]; then
		PRNERR "Not found ${_PATCH_FILES_LIST} file."
		return 1
	fi

	#
	# Create/Update patch files
	#
	_TMP_DIFF_FILE="/tmp/.tmp_${SCRIPTNAME}.$$.diff"

	_PATCH_FILES=$(sed -n "/^[[:space:]]*\[PATCH\][[:space:]]*$/,/^[[:space:]]*\[.*\][[:space:]]*$/p" "${_PATCH_FILES_LIST}" 2>/dev/null | sed -e 's/^[[:space:]]*\[.*\].*$//g' -e 's/^[[:space:]]*//g' -e 's/[[:space:]]*$//g' -e '/^$/d' | grep -v '^[[:space:]]*#')
	for _one_patch_file in ${_PATCH_FILES}; do
		if [ ! -f "${_MODIFICATION_TOP_DIR}/${_one_patch_file}" ]; then
			PRNERR "Not found modification file: ${_MODIFICATION_TOP_DIR}/${_one_patch_file}"
			return 1
		fi

		#
		# Write Header lines
		#
		{
			echo '#'
			echo '# K2HDKC DBaaS based on Trove'
			echo '#'
			echo '# Copyright 2020 Yahoo Japan Corporation'
			echo '#'
			echo '# K2HDKC DBaaS is a Database as a Service compatible with Trove which'
			echo '# is DBaaS for OpenStack.'
			echo '# Using K2HR3 as backend and incorporating it into Trove to provide'
			echo '# DBaaS functionality. K2HDKC, K2HR3, CHMPX and K2HASH are components'
			echo '# provided as AntPickax.'
			echo '#'
			echo '# For the full copyright and license information, please view'
			echo '# the license file that was distributed with this source code.'
			echo '#'
			echo '# AUTHOR:'
			echo '# CREATE:'
			echo '# REVISION:'
			echo '#'
			echo ''
		} > "${_TMP_DIFF_FILE}"

		#
		# Create diff by git command
		#
		(
			cd "${_MODIFICATION_TOP_DIR}" || exit 1

			# [NOTE]
			# trove/devstack/setting requires special pre-processing.
			#
			if echo "${_one_patch_file}" | grep -q 'devstack/settings'; then
				#
				# Backup
				#
				if ! /bin/sh -c "${SUDO_PREFIX_CMD} cp -p ${_one_patch_file} ${_one_patch_file}.BACUP >/dev/null 2>&1"; then
					PRNERR "Failed to create backup file for ${_one_patch_file}"
					return 1
				fi

				#
				# Set static value
				#
				if  ! /bin/sh -c "${SUDO_PREFIX_CMD} sed -i -e '/^[[:space:]]*#K2HDKC-START/,/^[[:space:]]*#K2HDKC-END/ s|^\([[:space:]]*TROVE_DATABASE_IMAGE_K2HDKC=\).*$|\1\${TROVE_DATABASE_IMAGE_K2HDKC:-\"docker.io/antpickax/k2hdkc-trove:${CUR_REPO_VERSION}-alpine\"}|g' ${_one_patch_file} >/dev/null 2>&1" || \
					! /bin/sh -c "${SUDO_PREFIX_CMD} sed -i -e '/^[[:space:]]*#K2HDKC-START/,/^[[:space:]]*#K2HDKC-END/ s|^\([[:space:]]*TROVE_DATABASE_BACKUP_IMAGE_K2HDKC=\).*$|\1\${TROVE_DATABASE_BACKUP_IMAGE_K2HDKC:-\"docker.io/antpickax/k2hdkc-trove-backup:${CUR_REPO_VERSION}-alpine\"}|g' ${_one_patch_file} >/dev/null 2>&1" || \
					! /bin/sh -c "${SUDO_PREFIX_CMD} sed -i -e '/^[[:space:]]*#K2HDKC-START/,/^[[:space:]]*#K2HDKC-END/ s|^\([[:space:]]*TROVE_INSECURE_DOCKER_REGISTRIES=\).*$|\1\${TROVE_INSECURE_DOCKER_REGISTRIES:-\"\"}|g' ${_one_patch_file} >/dev/null 2>&1"; then

					PRNERR "Failed to modify ${_one_patch_file} before creating patch file"
					return 1
				fi

				if ({ git diff -u "${_one_patch_file}" >> "${_TMP_DIFF_FILE}" 2>/dev/null || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
					PRNERR "Could not create diff file for ${_one_patch_file}"
					return 1
				fi

				#
				# Restore
				#
				if ! /bin/sh -c "${SUDO_PREFIX_CMD} mv -f ${_one_patch_file}.BACUP ${_one_patch_file} >/dev/null 2>&1"; then
					PRNERR "Failed to create backup file for ${_one_patch_file}"
					return 1
				fi
			else
				if ({ git diff -u "${_one_patch_file}" >> "${_TMP_DIFF_FILE}" 2>/dev/null || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
					PRNERR "Could not create diff file for ${_one_patch_file}"
					return 1
				fi
			fi
		)

		#
		# Write Footer lines
		#
		{
			echo ''
			echo '#'
			echo '# Local variables:'
			echo '# tab-width: 4'
			echo '# c-basic-offset: 4'
			echo '# End:'
			echo '# vim600: noexpandtab sw=4 ts=4 fdm=marker'
			echo '# vim<600: noexpandtab sw=4 ts=4'
			echo '#'
		} >> "${_TMP_DIFF_FILE}"

		#
		# Check diff file
		#
		if [ -f "${_PATCH_FILES_TOP_DIR}/${_one_patch_file}.patch" ]; then
			if diff "${_TMP_DIFF_FILE}" "${_PATCH_FILES_TOP_DIR}/${_one_patch_file}.patch" >/dev/null 2>&1; then
				#
				# Same diff
				#
				continue
			fi
		fi

		#
		# Create/Update diff(patch) file
		#
		if ! cp "${_TMP_DIFF_FILE}" "${_PATCH_FILES_TOP_DIR}/${_one_patch_file}.patch" >/dev/null 2>&1; then
			PRNERR "Failed to create(update) ${_PATCH_FILES_TOP_DIR}/${_one_patch_file}"
			return 1
		fi

		rm -f "${_TMP_DIFF_FILE}"
	done

	#
	# Copy additional files
	#
	_COPY_FILES=$(sed -n "/^[[:space:]]*\[COPY\][[:space:]]*$/,/^[[:space:]]*\[.*\][[:space:]]*$/p" "${_PATCH_FILES_LIST}" | sed -e 's/^[[:space:]]*\[.*\].*$//g' -e 's/^[[:space:]]*//g' -e 's/[[:space:]]*$//g' -e '/^$/d' | grep -v '^[[:space:]]*#')

	for _one_copy_file in ${_COPY_FILES}; do
		if [ ! -f "${_MODIFICATION_TOP_DIR}/${_one_copy_file}" ]; then
			PRNERR "Not found additinal file: ${_MODIFICATION_TOP_DIR}/${_one_copy_file}"
			return 1
		fi

		#
		# Check file
		#
		if [ -f "${_PATCH_FILES_TOP_DIR}/${_one_copy_file}" ]; then
			if diff "${_MODIFICATION_TOP_DIR}/${_one_copy_file}" "${_PATCH_FILES_TOP_DIR}/${_one_copy_file}" >/dev/null 2>&1; then
				#
				# Same file
				#
				continue
			fi
		fi

		#
		# Copy/Update file
		#
		if ! cp "${_PATCH_FILES_TOP_DIR}/${_one_copy_file}" "${_PATCH_FILES_TOP_DIR}/${_one_copy_file}" >/dev/null 2>&1; then
			PRNERR "Failed to copy(update) ${_PATCH_FILES_TOP_DIR}/${_one_copy_file}"
			return 1
		fi
	done

	return 0
}

#
# Test patch files
#
# Input	$1	: Directory in which to place patch files	(ex. "/home/user/k2hdkc_dbaas_trove/trove")
#		$2	: branch name								(ex, "stable/2024.1")
#
TestPatchFiles()
{
	if [ $# -lt 2 ]; then
		PRNERR "Parameters are wrong."
		return 1
	fi
	_PATCH_FILES_TOP_DIR="$1"
	_REPO_BRANCH_NAME="$2"
	_PATCH_REPO_NAME=$(basename "${_PATCH_FILES_TOP_DIR}")

	#
	# Setup direcctories
	#
	_WORK_REPO_DIR="/tmp/.test_${SCRIPTNAME}.$$"
	if ! mkdir -p "${_WORK_REPO_DIR}" 2>/dev/null; then
		PRNERR "Could not create ${_WORK_REPO_DIR}"
		return 1
	fi
	_ORG_REPO_TOP_DIR="${_WORK_REPO_DIR}/${_PATCH_REPO_NAME}"
	if [ -d "${_ORG_REPO_TOP_DIR}" ]; then
		rm -rf "${_ORG_REPO_TOP_DIR}"
	fi

	#
	# Clone trove repository
	#
	if ! CloneRepositoryAndSetBranch "${_PATCH_REPO_NAME}" "${_WORK_REPO_DIR}" "${_REPO_BRANCH_NAME}"; then
		rm -rf "${_WORK_REPO_DIR}"
		return 1
	fi

	#
	# Test patch
	#
	if ! ExtractPatchFiles "${_PATCH_FILES_TOP_DIR}" "${_ORG_REPO_TOP_DIR}"; then
		rm -rf "${_WORK_REPO_DIR}"
		return 1
	fi
	rm -rf "${_WORK_REPO_DIR}"

	return 0
}

#
# Get Latest version of K2HDKC docker image
#
# Output:	K2HDKC_DOCKER_IMAGE_VERSION
#
# [NOTE]
# We always upload the latest K2HDKC docker image to DockerHub.
# This function gets that latest version number.
#
GetLatestK2hdkcImageVersion()
{
	if ! K2HDKC_DOCKER_IMAGE_VERSION=$(curl https://hub.docker.com/v2/repositories/antpickax/k2hdkc/tags 2>/dev/null | python -m json.tool | grep '\"name\"' | sed -e 's#^[[:space:]]*"name"[[:space:]]*[:][[:space:]]*##gi' -e 's#"##g' -e 's#,##g' -e 's#[-].*$##g' -e 's#[[space:]]*$##g' | grep -v 'latest' | sort -r | uniq | head -1 | tr -d '\n'); then
		PRNWARN "Could not get the latest version number of K2HDKC docker image from DockerHub(antpickax/k2hdkc), but use 1.0.16 for fault tolerant."
		K2HDKC_DOCKER_IMAGE_VERSION="1.0.16"
	fi
	return 0
}

#
# Get values about Docker Images from configuration file
#
# Input:	$1	Configuration file Prefix
# Output:	Variables:
#				PRELOAD_SETUP_PUSH_REGISTRY
#				PRELOAD_SETUP_PUSH_REPOSITORY
#				PRELOAD_SETUP_INSECURE_REGISTRIES
#				PRELOAD_DEFAULT_DOCKER_IMAGE_TYPE
#				PRELOAD_DOCKER_IMAGE_UBUNTU
#				PRELOAD_DOCKER_IMAGE_ALPINE
#
# [NOTE]
# This function obtains information about the Docker Image in advance.
#
# The value of the --conf option(the prefix of the configuration file name)
# for this script is passed to k2hdkcdockerimage.sh.
# k2hdkcdockerimage.sh uses this configuration file to generate a Dockerfile,
# create a Docker image, and upload the Docker image.
# And this script also sets the path to the K2HDKC Docker Image specified in
# trove/devstack/settings.
# In addition, the path to the K2HDKC Docker Image and the type
# (ALPINE, ubuntu, etc.) of Docker image are also determined by the
# configuration file.
# This function loads the configuration file, parses it, and gets the values,
# just like k2hdkcdockerimage.sh does.
# The obtained values should be consistent with the load results from
# k2hdkcdockerimage.sh.
#
GetDockerImageValuesFromConf()
{
	PRELOAD_SETUP_PUSH_REGISTRY=""
	PRELOAD_SETUP_PUSH_REPOSITORY=""
	PRELOAD_SETUP_INSECURE_REGISTRIES=""
	PRELOAD_DEFAULT_DOCKER_IMAGE_TYPE=""
	PRELOAD_DOCKER_IMAGE_UBUNTU=""
	PRELOAD_DOCKER_IMAGE_ALPINE=""

	if [ -z "$1" ]; then
		return 0
	fi

	_TMP_DOCKER_IMAGE_CONFIG="$1"
	_TMP_DOCKER_IMAGE_SUMMARY_FILE="/tmp/.dockerimage_summary.$$.tmp"

	if [ ! -f "${SCRIPTDIR}/conf/${_TMP_DOCKER_IMAGE_CONFIG}.conf" ]; then
		PRNERR "Not found ${_TMP_DOCKER_IMAGE_CONFIG}.conf file."
		return 1
	fi

	# [NOTE]
	# To load the configuration file without affecting this script,
	# a separate shell is started and the file is loaded within it.
	#
	{
		# shellcheck source=/dev/null
		CONFIG_FILE_DIR="${SCRIPTDIR}/conf" . "${SCRIPTDIR}/conf/${_TMP_DOCKER_IMAGE_CONFIG}.conf"

		{
			echo "SETUP_PUSH_REGISTRY		${SETUP_PUSH_REGISTRY}"
			echo "SETUP_PUSH_REPOSITORY		${SETUP_PUSH_REPOSITORY}"
			echo "SETUP_INSECURE_REGISTRIES	${SETUP_INSECURE_REGISTRIES}"
			echo "DEFAULT_DOCKER_IMAGE_TYPE	${DEFAULT_DOCKER_IMAGE_TYPE}"
			echo "DOCKER_IMAGE_UBUNTU		${DOCKER_IMAGE_UBUNTU}"
			echo "DOCKER_IMAGE_ALPINE		${DOCKER_IMAGE_ALPINE}"

		} > "${_TMP_DOCKER_IMAGE_SUMMARY_FILE}"
	}

	if [ ! -f "${_TMP_DOCKER_IMAGE_SUMMARY_FILE}" ]; then
		PRNERR "Not found \"${_TMP_DOCKER_IMAGE_SUMMARY_FILE}\" temporary file."
		return 1
	fi

	PRELOAD_SETUP_PUSH_REGISTRY=$(grep			'SETUP_PUSH_REGISTRY'		"${_TMP_DOCKER_IMAGE_SUMMARY_FILE}"	| awk '{print $2}' | tr -d '\n')
	PRELOAD_SETUP_PUSH_REPOSITORY=$(grep		'SETUP_PUSH_REPOSITORY'		"${_TMP_DOCKER_IMAGE_SUMMARY_FILE}"	| awk '{print $2}' | tr -d '\n')
	PRELOAD_SETUP_INSECURE_REGISTRIES=$(grep	'SETUP_INSECURE_REGISTRIES'	"${_TMP_DOCKER_IMAGE_SUMMARY_FILE}"	| awk '{print $2}' | tr -d '\n')
	PRELOAD_DEFAULT_DOCKER_IMAGE_TYPE=$(grep	'DEFAULT_DOCKER_IMAGE_TYPE'	"${_TMP_DOCKER_IMAGE_SUMMARY_FILE}"	| awk '{print $2}' | tr -d '\n')
	PRELOAD_DOCKER_IMAGE_UBUNTU=$(grep			'DOCKER_IMAGE_UBUNTU'		"${_TMP_DOCKER_IMAGE_SUMMARY_FILE}"	| awk '{print $2}' | tr -d '\n')
	PRELOAD_DOCKER_IMAGE_ALPINE=$(grep			'DOCKER_IMAGE_ALPINE'		"${_TMP_DOCKER_IMAGE_SUMMARY_FILE}"	| awk '{print $2}' | tr -d '\n')

	rm -f "${_TMP_DOCKER_IMAGE_SUMMARY_FILE}"

	return 0
}

#--------------------------------------------------------------
# Usage
#--------------------------------------------------------------
command_usage()
{
	echo ""
	echo "Usage: ${SCRIPTNAME}                 [--help(-h)] [--version(-v)]"
	echo "       ${SCRIPTNAME} clean(c)        [--with-repos(-r)] [--with-package-repos(-pr)]"
	echo "       ${SCRIPTNAME} start(s)        [--with-trove(-t) | --without-trove(-nt)]"
	echo "                                      [--with-build-image(-i) | --without-build-image(-ni)]"
	echo "                                      [--with-k2hr3(-k) | --without-k2hr3(-ki)]"
	echo "                                      [--with-docker-image(-d) | --without-docker-image(-nd)]"
	echo "                                      [--enable-guest-ipv6(-ipv6)]"
	echo "                                      [--branch(-b) <branch>]"
	echo "                                      [--password(-p) <password>]"
	echo "                                      [--password(-p) <password>]"
	echo "       ${SCRIPTNAME} patch_update(u)"
	echo "       ${SCRIPTNAME} patch_test(t)"
	echo ""
	echo " [Parameter]"
	echo "   clean(c)                       : Cleanup devstack"
	echo "   start(s)                       : Setup and run devstack"
	echo "   patch_update(u)                : Update patch files"
	echo "   patch_test(t)                  : Test patch files"
	echo ""
	echo " [Options]"
	echo "   --help(-h)                     : Print usage."
	echo "   --version(-v)                  : Print version."
	echo ""
	echo "   --with-repos(-r)               : Remove all repository directories. (default: \"not remove repos\")"
	echo "   --with-package-repos(-pr)      : Remove package repositories for devstack and packages. (default: \"not remove package repos\")"
	echo ""
	echo "   --with-build-image(-i)         : Start with biulding guest os image(default)."
	echo "   --without-build-image(-ni)     : Start without biulding guest os image."
	echo "   --with-k2hr3(-k)               : Start with creating/launching K2HR3 cluster(default)."
	echo "   --without-k2hr3(-nk)           : Start without creating/launching K2HR3 cluster."
	echo "   --with-docker-image(-d)        : Create and push docker image for K2HDKC."
	echo "   --without-docker-image(-nd)    : Not create and push docker image for K2HDKC.(default)"
	echo ""
	echo "   --enable-guest-ipv6(-ipv6)     : Enable IPv6 on GuestAgent.(default disabled)"
	echo ""
	echo "   --branch(-b) <branch>          : Repository branch name. (default: \"${DEVSTACK_BRANCH}\")"
	echo "   --password(-p) <password>      : Openstack components password. (default: \"password\")"
	echo "   --conf(-c) <confg file prefix> : Specifies the prefix name for customized configuration files."
	echo "                                    The configuration file is \"conf/xxxxx.conf\" pattern, and specifies"
	echo "                                    the file name without the \".conf\"."
	echo "                                    The default is null(it means unspecified custom configuration file)."
	echo ""
}

#--------------------------------------------------------------
# Version
#--------------------------------------------------------------
print_version()
{
	if [ ! -f "${SCRIPTDIR}/make_release_version_file.sh" ]; then
		SCRIPT_VERSION_STRING="Unknown(not found make_release_version_file.sh)"
	else
		if ! "${SCRIPTDIR}/make_release_version_file.sh" >/dev/null 2>&1; then
			SCRIPT_VERSION_STRING="Unknown(failed to run make_release_version_file.sh)"
		else
			if [ ! -f "${SRCTOPDIR}/RELEASE_VERSION" ]; then
				SCRIPT_VERSION_STRING="Unknown(not found RELEASE_VERSION)"
			else
				SCRIPT_VERSION_STRING=$(cat "${SRCTOPDIR}/RELEASE_VERSION")
			fi
		fi
	fi
	echo "${SCRIPTNAME} version : ${SCRIPT_VERSION_STRING}"
}

#==============================================================
# Start Processing
#==============================================================
SetStartTime

#==============================================================
# Parse options(parameters)
#==============================================================
#
# Option value
#
ALL_SCRIPT_OPTIONS="$*"
RUN_MODE=""
BUILD_IMAGE=""
LAUNCH_K2HR3=""
DOCKER_IMAGE=""
DOCKER_IMAGE_CONFIG=""
ENABLE_GUEST_IPV6=0
CLEAN_ALL_REPODIRS=0
CLEAN_ALL_PCKGREPOS=0
OPT_BUILD_IMAGE=""
OPT_LAUNCH_K2HR3=""
OPT_DOCKER_IMAGE=""
OPT_DOCKER_IMAGE_CONFIG=""
OPT_ENABLE_GUEST_IPV6=0
OPT_BRANCH=""
OPT_PASSWORD=""

while [ $# -ne 0 ]; do
	if [ -z "$1" ]; then
		break;

	elif echo "$1" | grep -q -i -e "^--help$" -e "^-h$"; then
		command_usage
		exit 0

	elif echo "$1" | grep -q -i -e "^--version$" -e "^-v$"; then
		print_version
		exit 0

	elif echo "$1" | grep -q -i -e "^--with-build-image" -e "^-i$"; then
		if [ -n "${OPT_BUILD_IMAGE}" ]; then
			PRNERR "Already specified \"--with-build-image(-i)\" option."
			exit 1
		fi
		OPT_BUILD_IMAGE="yes"

	elif echo "$1" | grep -q -i -e "^--without-build-image" -e "^-ni$"; then
		if [ -n "${OPT_BUILD_IMAGE}" ]; then
			PRNERR "Already specified \"--without-build-image(-ni)\" option."
			exit 1
		fi
		OPT_BUILD_IMAGE="no"

	elif echo "$1" | grep -q -i -e "^--with-k2hr3" -e "^-k$"; then
		if [ -n "${OPT_LAUNCH_K2HR3}" ]; then
			PRNERR "Already specified \"--with-k2hr3(-k)\" option."
			exit 1
		fi
		OPT_LAUNCH_K2HR3="yes"

	elif echo "$1" | grep -q -i -e "^--without-k2hr3" -e "^-nk$"; then
		if [ -n "${OPT_LAUNCH_K2HR3}" ]; then
			PRNERR "Already specified \"--without-k2hr3(-nk)\" option."
			exit 1
		fi
		OPT_LAUNCH_K2HR3="no"

	elif echo "$1" | grep -q -i -e "^--with-docker-image" -e "^-d$"; then
		if [ -n "${OPT_DOCKER_IMAGE}" ]; then
			PRNERR "Already specified \"--with-docker-image(-d)\" option."
			exit 1
		fi
		OPT_DOCKER_IMAGE="yes"

	elif echo "$1" | grep -q -i -e "^--without-docker-image" -e "^-nd$"; then
		if [ -n "${OPT_DOCKER_IMAGE}" ]; then
			PRNERR "Already specified \"--without-docker-image(-nd)\" option."
			exit 1
		fi
		OPT_DOCKER_IMAGE="no"

	elif echo "$1" | grep -q -i -e "^--enable-guest-ipv6" -e "^-ipv6$"; then
		if [ "${OPT_ENABLE_GUEST_IPV6}" -ne 0 ]; then
			PRNERR "Already specified \"--enable-guest-ipv6(-ipv6)\" option."
			exit 1
		fi
		OPT_ENABLE_GUEST_IPV6=1

	elif echo "$1" | grep -q -i -e "^--branch" -e "^-b$"; then
		if [ -n "${OPT_BRANCH}" ]; then
			PRNERR "Already specified \"--branch(-b)\" option(${OPT_BRANCH})."
			exit 1
		fi
		shift
		if [ "$#" -eq 0 ]; then
			PRNERR "Option --branch(-b) needs a parameter"
			exit 1
		fi
		OPT_BRANCH="$1"

	elif echo "$1" | grep -q -i -e "^--password" -e "^-p$"; then
		if [ -n "${OPT_PASSWORD}" ]; then
			PRNERR "Already specified \"--password(-p)\" option(${OPT_PASSWORD})."
			exit 1
		fi
		shift
		if [ "$#" -eq 0 ]; then
			PRNERR "Option --password(-p) needs a parameter"
			exit 1
		fi
		OPT_PASSWORD="$1"

	elif echo "$1" | grep -q -i -e "^--conf$" -e "^-c$"; then
		if [ -n "${OPT_DOCKER_IMAGE_CONFIG}" ]; then
			PRNERR "Already specified --conf(-c) option : \"${OPT_DOCKER_IMAGE_CONFIG}\""
			exit 1
		fi
		shift
		if [ -z "$1" ]; then
			PRNERR "Option --conf(-c) needs parameter."
			exit 1
		fi
		if [ ! -f "${SCRIPTDIR}/conf/$1.conf" ]; then
			PRNERR "Not found ${SCRIPTDIR}/conf/$1.conf file."
			exit 1
		fi
		OPT_DOCKER_IMAGE_CONFIG="$1"

	elif echo "$1" | grep -q -i -e "^--with-repos" -e "^-r$"; then
		if [ "${CLEAN_ALL_REPODIRS}" -ne 0 ]; then
			PRNERR "Already specified \"--with-repos(-r)\" option."
			exit 1
		fi
		CLEAN_ALL_REPODIRS=1

	elif echo "$1" | grep -q -i -e "^--with-package-repos" -e "^-pr$"; then
		if [ "${CLEAN_ALL_PCKGREPOS}" -ne 0 ]; then
			PRNERR "Already specified \"--with-package-repos(-pr)\" option."
			exit 1
		fi
		CLEAN_ALL_PCKGREPOS=1

	elif echo "$1" | grep -q -i -e "^clean" -e "^c$"; then
		if [ -n "${RUN_MODE}" ]; then
			PRNERR "Already specified mode: ${RUN_MODE}"
			exit 1
		fi
		RUN_MODE="clean"

	elif echo "$1" | grep -q -i -e "^start" -e "^s$"; then
		if [ -n "${RUN_MODE}" ]; then
			PRNERR "Already specified mode: ${RUN_MODE}"
			exit 1
		fi
		RUN_MODE="start"

	elif echo "$1" | grep -q -i -e "^patch_update" -e "^u$"; then
		if [ -n "${RUN_MODE}" ]; then
			PRNERR "Already specified mode: ${RUN_MODE}"
			exit 1
		fi
		RUN_MODE="update"

	elif echo "$1" | grep -q -i -e "^patch_test" -e "^t$"; then
		if [ -n "${RUN_MODE}" ]; then
			PRNERR "Already specified mode: ${RUN_MODE}"
			exit 1
		fi
		RUN_MODE="test"

	else
		PRNERR "Unknown option : \"$1\""
		exit 1
	fi
	shift
done

#
# Check options
#
if [ -z "${RUN_MODE}" ]; then
	PRNERR "Not specified mode(start or clean)."
	exit 1
fi

if [ "${RUN_MODE}" = "start" ]; then
	if [ -z "${OPT_BUILD_IMAGE}" ]; then
		BUILD_IMAGE="yes"
	else
		BUILD_IMAGE="${OPT_BUILD_IMAGE}"
	fi
	if [ -z "${OPT_LAUNCH_K2HR3}" ]; then
		LAUNCH_K2HR3="yes"
	else
		LAUNCH_K2HR3="${OPT_LAUNCH_K2HR3}"
	fi
	if [ -z "${OPT_DOCKER_IMAGE}" ]; then
		DOCKER_IMAGE="no"
	else
		DOCKER_IMAGE="${OPT_DOCKER_IMAGE}"
	fi
	if [ "${OPT_ENABLE_GUEST_IPV6}" -eq 0 ]; then
		ENABLE_GUEST_IPV6=0
	else
		ENABLE_GUEST_IPV6=1
	fi
	if [ -n "${OPT_BRANCH}" ]; then
		DEVSTACK_BRANCH="${OPT_BRANCH}"
	fi
	if [ -n "${OPT_PASSWORD}" ]; then
		DEVSTACK_DEFAULT_PASSWORD="${OPT_PASSWORD}"
	fi
	if [ -z "${OPT_DOCKER_IMAGE_CONFIG}" ]; then
		DOCKER_IMAGE_CONFIG=""
	else
		DOCKER_IMAGE_CONFIG="${OPT_DOCKER_IMAGE_CONFIG}"
	fi

elif [ "${RUN_MODE}" = "clean" ] || [ "${RUN_MODE}" = "update" ] || [ "${RUN_MODE}" = "test" ]; then
	if [ -n "${OPT_PLUGIN}" ]; then
		PRNERR "If mode is ${RUN_MODE}, \"--with-trove(-t)\" and \"--without-trove(-nt)\" options cannot be specified."
		exit 1
	fi
	if [ -n "${OPT_BUILD_IMAGE}" ]; then
		PRNERR "If mode is ${RUN_MODE}, \"--with-build-image(-i)\" and \"--without-build-image(-ni)\" option cannot be specified."
		exit 1
	fi
	if [ -n "${OPT_LAUNCH_K2HR3}" ]; then
		PRNERR "If mode is ${RUN_MODE}, \"--with-k2hr3(-k)\" and \"--without-k2hr3(-nk)\" option cannot be specified."
		exit 1
	fi
	if [ -n "${OPT_DOCKER_IMAGE}" ]; then
		PRNERR "If mode is ${RUN_MODE}, \"--with-docker-image(-d)\" and \"--without-docker-image(-nd)\" option cannot be specified."
		exit 1
	fi
	if [ -n "${OPT_BRANCH}" ]; then
		PRNERR "If mode is ${RUN_MODE}, \"--branch(-b)\" option cannot be specified."
		exit 1
	fi
	if [ -n "${OPT_PASSWORD}" ]; then
		PRNERR "If mode is ${RUN_MODE}, \"--password(-p)\" option cannot be specified."
		exit 1
	fi
	if [ -n "${OPT_DOCKER_IMAGE_CONFIG}" ]; then
		PRNERR "If mode is ${RUN_MODE}, \"--config(-c)\" option cannot be specified."
		exit 1
	fi

	if [ "${RUN_MODE}" != "clean" ]; then
		if [ "${CLEAN_ALL_REPODIRS}" -ne 0 ]; then
			PRNERR "If mode is ${RUN_MODE}, \"--with-repos(-r)\" option cannot be specified."
			exit 1
		fi
		if [ "${CLEAN_ALL_PCKGREPOS}" -ne 0 ]; then
			PRNERR "If mode is ${RUN_MODE}, \"--with-package-repos(-pr)\" option cannot be specified."
			exit 1
		fi
	fi
else
	PRNERR "Unknown run mode(${RUN_MODE})."
	exit 1
fi

#==============================================================
# Check current execution environment
#==============================================================
# [NOTICE]
# From this line, only "start" and "clean" and "update" modes are processed.
#
CUR_USER_NAME=$(id -u -n)

if [ "${CUR_USER_NAME}" != "${ROOT_USER_NAME}" ]; then
	SUDO_PREFIX_CMD="sudo"
else
	SUDO_PREFIX_CMD=""
fi

if id -u -n "${STACK_USER_NAME}" >/dev/null 2>&1; then
	STACK_USER_EXIST=1
else
	STACK_USER_EXIST=0
fi

if systemctl | sed -e 's#^[[:space:]]*##g' | grep -q '^devstack@'; then
	CUR_RUN_DEVSTACK=1
else
	CUR_RUN_DEVSTACK=0
fi

#==============================================================
# Processing mentenace mode
#==============================================================
# [NOTICE]
# Only Update and Test of the Patch file are processed here.
#
if [ "${RUN_MODE}" = "update" ]; then
	#
	# Process Update/Create patch files
	#
	PRNTITLE "Update/Create patch files"

	if [ ! -f "${SRCTOPDIR}/RELEASE_VERSION" ]; then
		#
		# Create RELEASE_VERSION for CUR_REPO_VERSION variable
		#
		if [ ! -f "${SCRIPTDIR}/make_release_version_file.sh" ]; then
			PRNERR "Not found ${SCRIPTDIR}/make_release_version_file.sh file."
			exit 1
		fi
		if ({ /bin/sh -c "${SCRIPTDIR}/make_release_version_file.sh" 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to create(update) RELEASE_VERSION file by ${SCRIPTDIR}/make_release_version_file.sh."
			exit 1
		fi
	fi
	if [ ! -f "${SRCTOPDIR}/RELEASE_VERSION" ]; then
		PRNERR "Not found ${SRCTOPDIR}/RELEASE_VERSION file."
		exit 1
	fi
	CUR_REPO_VERSION=$(cat "${SRCTOPDIR}/RELEASE_VERSION")

	echo ""
	echo " Modification directories: ${TROVE_GIT_TOP_DIR}"
	echo "                           ${TROVE_DASHBOARD_GIT_TOP_DIR}"
	echo " Patch directories:        ${TROVE_PATCH_TOP_DIR}"
	echo "                           ${TROVE_DASHBOARD_PATCH_TOP_DIR}"
	echo ""

	#
	# Trove
	#
	PRNMSG "Update/Create ${TROVE_PATCH_DIR_NAME}"
	if ! UpdatePatchFiles "${TROVE_GIT_TOP_DIR}" "${TROVE_PATCH_TOP_DIR}"; then
		PRNERR "Failed to update/create patches for ${TROVE_PATCH_DIR_NAME}"
		exit 1
	fi
	PRNINFO "Succeed to update/create patches for ${TROVE_PATCH_DIR_NAME}"

	#
	# Trove Dashboard
	#
	PRNMSG "Update/Create ${TROVE_DASHBOARD_PATCH_DIR_NAME}"
	if ! UpdatePatchFiles "${TROVE_DASHBOARD_GIT_TOP_DIR}" "${TROVE_DASHBOARD_PATCH_TOP_DIR}"; then
		PRNERR "Failed to update/create patches for ${TROVE_DASHBOARD_PATCH_DIR_NAME}"
		exit 1
	fi
	PRNINFO "Succeed to update/create patches for ${TROVE_DASHBOARD_PATCH_DIR_NAME}"

	PRNSUCCESS "Updated/Created patch files"
	exit 0

elif [ "${RUN_MODE}" = "test" ]; then
	#
	# Test patch files
	#
	PRNTITLE "Start testing patches"
	echo ""
	echo "Patch directories: ${TROVE_PATCH_TOP_DIR}"
	echo "                   ${TROVE_DASHBOARD_PATCH_TOP_DIR}"
	echo ""

	#
	# Trove
	#
	PRNMSG "Test patches for ${TROVE_PATCH_DIR_NAME}"
	if ! TestPatchFiles "${TROVE_PATCH_TOP_DIR}" "${DEVSTACK_BRANCH}"; then
		PRNERR "Failed to test patches for ${TROVE_PATCH_DIR_NAME}"
		exit 1
	fi
	PRNINFO "Succeed to test patches for ${TROVE_PATCH_DIR_NAME}"

	#
	# Trove Dashboard
	#
	PRNMSG "Test patches for ${TROVE_DASHBOARD_PATCH_DIR_NAME}"
	if ! TestPatchFiles "${TROVE_DASHBOARD_PATCH_TOP_DIR}" "${DEVSTACK_BRANCH}"; then
		PRNERR "Failed to test patches for ${TROVE_DASHBOARD_PATCH_DIR_NAME}"
		exit 1
	fi
	PRNINFO "Succeed to test patches for ${TROVE_DASHBOARD_PATCH_DIR_NAME}"

	PRNSUCCESS "Succeed to test all patches"
	exit 0
fi

#==============================================================
# Run start and clean
#==============================================================
#
# Check stack user
#
if [ "${RUN_MODE}" = "clean" ]; then
	#
	# Clean mode
	#
	if [ "${STACK_USER_EXIST}" -ne 1 ]; then
		PRNERR "${STACK_USER_NAME} user does not exist."
		exit 1
	fi
else
	#
	# Start mode
	#
	if [ "${CUR_USER_NAME}" != "${STACK_USER_NAME}" ] && [ "${STACK_USER_EXIST}" -ne 1 ]; then
		PRNTITLE "Setup stack user"

		#
		# Add stack user
		#
		PRNMSG "Add stack user"
		if ({ /bin/sh -c "${SUDO_PREFIX_CMD} useradd -s ${STACK_USER_SHELL} -d ${STACK_USER_HOME} -m ${STACK_USER_NAME}" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to add ${STACK_USER_NAME} user."
			exit 1
		fi

		#
		# Set permisstion to stack user home directory
		#
		PRNMSG "Set permisstion for stack user home directory"
		if ({ /bin/sh -c "${SUDO_PREFIX_CMD} chmod +x ${STACK_USER_HOME}" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to add ${STACK_USER_NAME} user."
			exit 1
		fi

		#
		# Set umask for stackuser
		#
		if [ -f "${STACK_USER_HOME}/.bashrc" ] && ! grep umask ~stack/.bashrc | grep -q 022; then
			PRNMSG "Set umask to ${STACK_USER_NAME} user."
			(
				echo "# Force to set umask 022"
				echo "umask 022"
			) | /bin/sh -c "${SUDO_PREFIX_CMD} tee ${STACK_USER_HOME}/.bashrc" >/dev/null
		fi

		#
		# Check sudoers file
		#
		_NEED_CREATE_SUDOERS=0
		if /bin/sh -c "${SUDO_PREFIX_CMD} stat /etc/sudoers.d/${STACK_USER_NAME} >/dev/null 2>&1"; then
			#
			# found sudoers file
			#
			if ! /bin/sh -c "${SUDO_PREFIX_CMD} grep -q '${STACK_USER_NAME} ALL=(ALL) NOPASSWD: ALL' /etc/sudoers.d/${STACK_USER_NAME}"; then
				#
				# Not found field in sudoers file
				#
				_NEED_CREATE_SUDOERS=1
			fi
		else
			#
			# not found sudoers file
			#
			_NEED_CREATE_SUDOERS=1
		fi

		#
		# Set sudoers file
		#
		if [ "${_NEED_CREATE_SUDOERS}" -eq 1 ]; then
			PRNMSG "Create(add) the field in sudoers for stack user"
			#
			# Create(add) field to sudoers file
			#
			if ! /bin/sh -c "${SUDO_PREFIX_CMD} /bin/sh -c \"echo '${STACK_USER_NAME} ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers.d/${STACK_USER_NAME}\""; then
				PRNERR "Failed to create(add) the field in sudoers for stack user."
				exit 1
			fi

			#
			# Set permission sudoers file
			#
			if ! /bin/sh -c "${SUDO_PREFIX_CMD} chmod 0440 /etc/sudoers.d/${STACK_USER_NAME}"; then
				PRNERR "Failed to set permission sudoers file for stack user."
				exit 1
			fi
			PRNINFO "Succeed to create(add) sudoers file for stack user."

			#
			# Check includedir in sudoers
			#
			if ! /bin/sh -c "${SUDO_PREFIX_CMD} grep -q '^#includedir[[:space:]]*/etc/sudoers.d[[:space:]]*$' /etc/sudoers"; then
				PRNMSG "Add the includedir field in sudoers file"
				if ! /bin/sh -c "${SUDO_PREFIX_CMD} /bin/sh -c \"echo '#includedir /etc/sudoers.d' >> /etc/sudoers\""; then
					PRNERR "Failed to add the includedir field in sudoers file."
					exit 1
				fi
				PRNINFO "Added the includedir field in sudoers file."
			fi
		fi

		PRNSUCCESS "Setup stack user"
	fi

	#
	# Check and Setup root user
	#
	PRNTITLE "Check and Setup root user"

	#
	# Check and Setup adm user/group
	#
	if ! getent group adm >/dev/null 2>&1; then
		PRNMSG "Setup adm group"
		if ! /bin/sh -c "${SUDO_PREFIX_CMD} groupadd adm" >/dev/null 2>&1; then
			PRNERR "Failed to add adm group."
			exit 1
		fi
		if ! /bin/sh -c "${SUDO_PREFIX_CMD} gpasswd -a root adm" >/dev/null 2>&1; then
			PRNERR "Failed to add root to adm group member."
			exit 1
		fi
		if ! /bin/sh -c "${SUDO_PREFIX_CMD} gpasswd -a daemon adm" >/dev/null 2>&1; then
			PRNERR "Failed to add daemon to adm group member."
			exit 1
		fi
		PRNINFO "Succeed to add adm group."
	fi

	if ! getent passwd adm >/dev/null 2>&1; then
		PRNMSG "Setup adm user"
		if ({ /bin/sh -c "${SUDO_PREFIX_CMD} sudo useradd -g adm -G sys -c adm -d /var/adm -s /sbin/nologin adm" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to add adm user."
			exit 1
		fi
		PRNINFO "Succeed to add adm user."
	fi

	if ! getent group adm | awk -F':' '{print $4}' | grep -q adm; then
		PRNMSG "Add adm user to adm group"
		if ! /bin/sh -c "${SUDO_PREFIX_CMD} gpasswd -a adm adm" >/dev/null 2>&1; then
			PRNERR "Failed to add adm user to adm group."
			exit 1
		fi
		PRNINFO "Succeed to add adm user to adm group."
	fi

	#
	# Check and modify umask in root profile files
	#
	# [NOTE]
	# Requires 0022 or higher authorization.
	#
	PRNMSG "Check and modify umask value for root profile"
	_TMP_HAS_UMASK_PROFILE_FILES=$(/bin/sh -c "${SUDO_PREFIX_CMD} grep -v '^#' /etc/profile /etc/profile.d/*" | grep umask | awk -F':' '{print $1}')
	for _one_profile_file in ${_TMP_HAS_UMASK_PROFILE_FILES}; do
		if /bin/sh -c "${SUDO_PREFIX_CMD} sed -i -e 's|umask|#umask|g' ${_one_profile_file}" >/dev/null 2>&1; then
			PRNWARN "Failed to comment out the umask setting in ${_one_profile_file}. This may cause problems later."
		else
			PRNINFO "Succeed to comment out the umask setting in ${_one_profile_file}."
		fi
	done
fi

#==============================================================
# Switch sub-process as stack user
#==============================================================
if [ -z "${K2HDKCSTACK_SH_NESTED}" ]; then

	PRNTITLE "Switch stack user and run ${SCRIPTNAME}"

	#
	# Check Current user
	#
	if [ "${CUR_USER_NAME}" = "${STACK_USER_NAME}" ]; then
		PRNWARN "Current user is ${STACK_USER_NAME}."
	fi

	#
	# Create/Update RELEASE_VERSION for docker image
	#
	# [NOTE]
	# When generating a Docker image, the release version is required.
	# Therefore, create and update the RELEASE_VERSION file as the current user.
	#
	PRNTITLE "Create/Update RELEASE_VERSION file"

	if [ ! -f "${SCRIPTDIR}/make_release_version_file.sh" ]; then
		PRNERR "Not found ${SCRIPTDIR}/make_release_version_file.sh file."
		exit 1
	fi
	if ({ /bin/sh -c "${SCRIPTDIR}/make_release_version_file.sh" 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
		PRNERR "Failed to create(update) RELEASE_VERSION file by ${SCRIPTDIR}/make_release_version_file.sh."
		exit 1
	fi
	if [ ! -f "${SRCTOPDIR}/RELEASE_VERSION" ]; then
		PRNERR "Not found ${SRCTOPDIR}/RELEASE_VERSION file."
		exit 1
	fi
	CUR_REPO_VERSION=$(cat "${SRCTOPDIR}/RELEASE_VERSION")

	PRNSUCCESS "Create/Update RELEASE_VERSION file"

	#
	# Pre-load configuration file for some variables
	#
	if [ "${RUN_MODE}" != "clean" ]; then
		if ! GetDockerImageValuesFromConf "${DOCKER_IMAGE_CONFIG}"; then
			exit 1
		fi
	fi

	#
	# Switch stack user
	#
	# [NOTE]
	# Call this own script as the stack user with the following variables:
	# (It will also be called if current user is stack user)
	#	K2HDKCSTACK_SH_NESTED(=1)
	#	CUR_REPO_VERSION
	#	PRELOAD_SETUP_PUSH_REGISTRY
	#	PRELOAD_SETUP_PUSH_REPOSITORY
	#	PRELOAD_SETUP_INSECURE_REGISTRIES
	#	PRELOAD_DEFAULT_DOCKER_IMAGE_TYPE
	#	PRELOAD_DOCKER_IMAGE_UBUNTU
	#	PRELOAD_DOCKER_IMAGE_ALPINE
	#
	if ! /bin/sh -c "sudo -u ${STACK_USER_NAME} -i K2HDKCSTACK_SH_NESTED=1 CUR_REPO_VERSION=${CUR_REPO_VERSION} PRELOAD_SETUP_PUSH_REGISTRY=${PRELOAD_SETUP_PUSH_REGISTRY} PRELOAD_SETUP_PUSH_REPOSITORY=${PRELOAD_SETUP_PUSH_REPOSITORY} PRELOAD_SETUP_INSECURE_REGISTRIES=${PRELOAD_SETUP_INSECURE_REGISTRIES} PRELOAD_DEFAULT_DOCKER_IMAGE_TYPE=${PRELOAD_DEFAULT_DOCKER_IMAGE_TYPE} PRELOAD_DOCKER_IMAGE_UBUNTU=${PRELOAD_DOCKER_IMAGE_UBUNTU} PRELOAD_DOCKER_IMAGE_ALPINE=${PRELOAD_DOCKER_IMAGE_ALPINE} ${SCRIPTDIR}/${SCRIPTNAME} ${ALL_SCRIPT_OPTIONS}"; then
		PRNERR "Failed to run ${SCRIPTNAME} as stack user."
		exit 1
	fi

	if [ "${RUN_MODE}" != "clean" ]; then
		#
		# Create/Update K2HDKC Docker Image
		#
		# [NOTE]
		# K2HDKC Docker Image is created by not stack user.
		#
		if [ -n "${DOCKER_IMAGE}" ] && [ "${DOCKER_IMAGE}" = "yes" ]; then
			#
			# Create/Update K2HDKC Docker Image
			#
			PRNTITLE "Create/Update K2HDKC Docker Image"

			cd "${SCRIPTDIR}" || exit 1

			#
			# Get versions
			#
			if ! GetLatestK2hdkcImageVersion; then
				exit 1
			fi

			#
			# Setup --conf option value
			#
			if [ -n "${DOCKER_IMAGE_CONFIG}" ]; then
				_TMP_CONF_PARAMTER="--conf ${DOCKER_IMAGE_CONFIG}"
			else
				_TMP_CONF_PARAMTER=""
			fi

			#
			# Clear docker local caches
			#
			if ({ ./k2hdkcdockerimage.sh cleanup-all 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
				PRNERR "Failed to clear docker local caches."
				exit 1
			fi

			#
			# Create and upload docker images
			#
			if [ -n "${PRELOAD_DOCKER_IMAGE_ALPINE}" ] && [ "${PRELOAD_DOCKER_IMAGE_ALPINE}" -eq 1 ]; then
				if ({ /bin/sh -c "./k2hdkcdockerimage.sh upload_image -o alpine -b ${K2HDKC_DOCKER_IMAGE_VERSION} --image-version ${CUR_REPO_VERSION} ${_TMP_CONF_PARAMTER}" 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
					PRNERR "Failed to create dcoker image for alpine."
					exit 1
				fi
			fi
			if [ -n "${PRELOAD_DOCKER_IMAGE_UBUNTU}" ] && [ "${PRELOAD_DOCKER_IMAGE_UBUNTU}" -eq 1 ]; then
				if ({ /bin/sh -c "./k2hdkcdockerimage.sh upload_image -o ubuntu -b ${K2HDKC_DOCKER_IMAGE_VERSION} --image-version ${CUR_REPO_VERSION} ${_TMP_CONF_PARAMTER}" 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
					PRNERR "Failed to create dcoker image for alpine."
					exit 1
				fi
			fi

			PRNSUCCESS "Create/Update K2HDKC Docker Image"
		fi

		#
		# Print summary
		#
		PRNTITLE "Summary : K2HDKC DBaaS Trove"
		if [ -f "${K2HDKCSTACK_SUMMARY_LOG}" ]; then
			cat "${K2HDKCSTACK_SUMMARY_LOG}"
			echo ""
		fi
		if [ -f "${K2HR3SETUP_SUMMARY_LOG}" ]; then
			cat "${K2HR3SETUP_SUMMARY_LOG}"
			echo ""
		fi
	fi

	exit 0
fi

#==============================================================
# Start main processes
#==============================================================
#
# Check if devstack starts
#
if [ "${RUN_MODE}" = "start" ] && [ "${CUR_RUN_DEVSTACK}" -eq 1 ]; then
	#
	# devstack is running
	#
	PRNMSG "${DEVSTACK_NAME} is already started."

	_CONTINUE_PROCESS=0
	while [ "${_CONTINUE_PROCESS}" -eq 0 ]; do
		confirm_input "Do you cleanup and restart ${DEVSTACK_NAME} or abort? [ continue(c) | abort(a) ]" 0 ""
		if [ -n "${CONFIRM_RESULT}" ]; then
			if echo "${CONFIRM_RESULT}" | grep -q -i -e "abort" -e "a"; then
				PRNINFO "Abort processing."
				exit 0
			elif echo "${CONFIRM_RESULT}" | grep -q -i -e "continue" -e "c"; then
				_CONTINUE_PROCESS=1
			else
				PRNWARN "Input must be \"continue(c)\" or \"abort(a)\"."
			fi
		fi
	done
fi

#==============================================================
# Stop and Cleanup devstack
#==============================================================
if [ "${RUN_MODE}" = "clean" ] || [ "${CUR_RUN_DEVSTACK}" -eq 1 ]; then

	PRNTITLE "Stop and Cleanup ${DEVSTACK_NAME}"

	if [ -d "${DEVSTACK_GIT_TOP_DIR}" ]; then
		if [ -f "${DEVSTACK_GIT_TOP_DIR}/${DEVSTACK_CLEAN_SH}" ]; then
			#
			# Run unstack.sh
			#
			cd "${DEVSTACK_GIT_TOP_DIR}" || exit 1

			set_scheme_proxy_env
			if ({ "./${DEVSTACK_CLEAN_SH}" 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
				PRNERR "Failed to add ${STACK_USER_NAME} user."
				exit 1
			fi
			revert_scheme_proxy_env

			PRNINFO "Stopped ${DEVSTACK_NAME}"
		else
			PRNWARN "Not found ${DEVSTACK_CLEAN_SH} script in directory(${DEVSTACK_GIT_TOP_DIR}), maybe already remove it."
		fi
	else
		PRNWARN "Not found ${DEVSTACK_NAME} source code directory(${DEVSTACK_GIT_TOP_DIR}), maybe already remove it."
	fi

	#
	# Clean up rest directories and files
	#
	PRNMSG "Clean up rest directories and files"

	if [ -d "${ETC_TROVE_DIR}" ]; then
		sudo rm -rf "${ETC_TROVE_DIR}" 2>/dev/null
	fi
	for _image_obj_name in "${IMAGES_TOP_DIR}"/*; do
		rm -rf "${_image_obj_name}" 2>/dev/null
	done

	PRNINFO "Succeed to clean up rest directories and files"

	#
	# Clean up iptables
	#
	# [NOTE]
	# The Devstack iptables started by this script is not saved.
	# Restart to initialize the contents of iptables when stopped.
	#
	PRNMSG "Clean up iptables"

	if ({ /bin/sh -c "${SUDO_PREFIX_CMD} systemctl restart iptables.service" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
		PRNWARN "Failed to restart iptables service, so you need to check and modify it manually."
	else
		PRNINFO "Succeed to clean up iptables"
	fi

	#
	# Stop libvirtd services and remove packages
	#
	# [NOTE]
	# A simple systemctl stop command will not be enough to stop libvirtd,
	# so it will loop and wait until it is completely stopped.
	#
	PRNMSG "Stop libvirtd services and remove packages"

	if ({ /bin/sh -c "${SUDO_PREFIX_CMD} systemctl stop libvirtd.service virtlogd.service libvirtd-admin.socket libvirtd-ro.socket libvirtd.socket virtlockd.socket virtlogd-admin.socket virtlogd.socket 2>&1" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
		PRNWARN "Failed to stop libvirtd services, but continue..."
	else
		sleep 1
		PRNINFO "Succeed to stop libvirtd services"
	fi

	#
	# Check rabbitmq file permission
	#
	# [NOTE]
	# This may not be necessary, but in the past there were cases where
	# the permissions were set to root and I was unable to restart, so
	# check and fix that.
	#
	if [ -f /var/log/rabbitmq/rabbit@devstack.log ]; then
		PRNMSG "Check and Fix rabbitmq log file permission"

		RABBITMQ_LOG_OWNER=$(stat --format='%U:%G' /var/log/rabbitmq/rabbit@devstack.log)

		if [ -z "${RABBITMQ_LOG_OWNER}" ] || [ "${RABBITMQ_LOG_OWNER}" != "rabbitmq:rabbitmq" ]; then
			if ({ /bin/sh -c "${SUDO_PREFIX_CMD} chown rabbitmq:rabbitmq /var/log/rabbitmq/rabbit@devstack.log" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
				PRNWARN "Failed to fix /var/log/rabbitmq/rabbit@devstack.log file permission, so you need to check and modify it manually."
			else
				PRNINFO "Succeed to fix rabbitmq log file permission"
			fi
		else
			PRNINFO "Nothing to fix rabbitmq log file permission"
		fi
	fi

	#
	# Cleanup devstack by manual
	#
	PRNMSG "Cleanup ${DEVSTACK_NAME}"

	if [ "${CLEAN_ALL_REPODIRS}" -ne 1 ]; then
		#
		# Interactive Input
		#
		echo ""
		_CONTINUE_CONFIRM=1
		while [ "${_CONTINUE_CONFIRM}" -eq 1 ]; do
			#
			# Confirm
			#
			confirm_input "Do you want to delete the associated directories(repositories)? [yes(y)/no(n)]" 0 ""
			if [ -n "${CONFIRM_RESULT}" ]; then
				if echo "${CONFIRM_RESULT}" | grep -q -i -e "yes" -e "y"; then
					CLEAN_ALL_REPODIRS=1
					_CONTINUE_CONFIRM=0
				elif echo "${CONFIRM_RESULT}" | grep -q -i -e "no" -e "n"; then
					CLEAN_ALL_REPODIRS=0
					_CONTINUE_CONFIRM=0
				else
					PRNWARN "Input must be \"yes(y)\" or \"no(n)\"."
				fi
			fi
		done
	fi
	if [ "${CLEAN_ALL_REPODIRS}" -eq 1 ]; then
		cd "${STACK_USER_HOME}" || exit 1
		sudo rm -rf bin bindep-venv cinder data devstack devstack.subunit glance horizon images keystone logs neutron ova novnc placement rements tempest trove ient nova neutron-tempest-plugin python-troveclient requirements os-test-images swift .troveclient trove-dashboard .novaclient .local .cache .my.cnf "${SRCTOPDIRNAME}" 2>/dev/null
	else
		echo "    -----------------------------------------------------------------"
		echo "    If you want to clean up files under the ${STACK_USER_NAME} user's"
		echo "    ${STACK_USER_HOME} home directory(mainly the ${DEVSTACK_GIT_TOP_DIR}"
		echo "    directory), please do this ${CYEL}manually${CDEF}."
		echo ""
		echo "    [example]"
		echo "    $ cd ~stack"
		echo "    $ sudo rm -rf bin bindep-venv cinder data devstack devstack.subunit"
		echo "                  glance horizon images keystone logs neutron ova novnc"
		echo "                  placement rements tempest trove nova neutron-tempest-plugin"
		echo "                  python-troveclient requirements os-test-images swift"
		echo "                  .troveclient trove-dashboard .novaclient .local .cache"
		echo "                  .my.cnf ${SRCTOPDIRNAME}"
		echo "    -----------------------------------------------------------------"
		echo ""
	fi

	#
	# Cleanup package repositories and packages
	#
	if [ "${CLEAN_ALL_PCKGREPOS}" -eq 1 ]; then
		PRNMSG "Cleanup package repositories and packages"

		#
		# Cleanup systemd services and packages, etc
		#
		PRNMSG "Cleanup systemd services and packages, etc"

		if ! /bin/sh -c "${SUDO_PREFIX_CMD} systemctl stop devstack@q-svc.service rabbitmq-server.service memcached.service mariadb.service polkit.service ovs-vswitchd ovsdb-server system-devstack.slice >/dev/null 2>&1"; then
			PRNWARN "Failed to stop some systemd services : devstack@q-svc.service rabbitmq-server.service memcached.service mariadb.service polkit.service ovs-vswitchd ovsdb-server system-devstack.slice"
		else
			PRNINFO "Succeed to stop systemd services : devstack@q-svc.service rabbitmq-server.service memcached.service mariadb.service polkit.service ovs-vswitchd ovsdb-server system-devstack.slice"
		fi

		if ! /bin/sh -c "${SUDO_PREFIX_CMD} killall dnsmasq >/dev/null 2>&1"; then
			PRNWARN "Failed to kill dnsmasq processes."
		else
			PRNINFO "Succeed to kill dnsmasq processes."
		fi

		if ! /bin/sh -c "${SUDO_PREFIX_CMD} dnf remove -y rabbitmq-server centos-release-rabbitmq-38 >/dev/null 2>&1"; then
			PRNWARN "Failed to remove rabbitmq packages."
		else
			PRNINFO "Succeed to remove rabbitmq packages."
		fi
		/bin/sh -c "${SUDO_PREFIX_CMD} rm -rf /etc/pcp/pmlogconf/rabbitmq /var/lib/pcp/config/pmlogconf/rabbitmq /var/lib/selinux/targeted/active/modules/100/rabbitmq /var/lib/rabbitmq /var/log/rabbitmq 2>/dev/null"

		#
		# Cleanup memcached packages
		#
		PRNMSG "Cleanup memcached packages"

		if ! /bin/sh -c "${SUDO_PREFIX_CMD} dnf remove -y memcached memcached-selinux >/dev/null 2>&1"; then
			PRNWARN "Failed to remove memcached memcached-selinux packages."
		else
			PRNINFO "Succeed to remove memcached memcached-selinux packages."
		fi
		/bin/sh -c "${SUDO_PREFIX_CMD} dnf clean all >/dev/null 2>&1"

		#
		# Cleanup pip packages(oslo, kombu, k2hr3client)
		#
		PRNMSG "Cleanup pip packages - oslo, kombu"

		_TMP_PIP_PACKAGES=$(/bin/sh -c "${SUDO_PREFIX_CMD} pip list 2>/dev/null" | grep -e 'oslo' -e 'kombu' -e 'k2hr3client' | awk '{print $1}')
		for _ONE_PIP_OKG in ${_TMP_PIP_PACKAGES}; do
			if ! /bin/sh -c "${SUDO_PREFIX_CMD} pip uninstall -y ${_ONE_PIP_OKG} >/dev/null 2>&1"; then
				PRNWARN "Failed to remove ${_ONE_PIP_OKG} pip packages."
			else
				PRNINFO "Succeed to remove ${_ONE_PIP_OKG} pip packages."
			fi
		done
	fi

	#
	# Cleanup /etc/fetab and Umount for swift
	#
	PRNMSG "Cleanup /etc/fetab and Umount for swift"

	if /bin/sh -c "${SUDO_PREFIX_CMD} df -k | grep -q '/opt/stack/data/drives/sdb1'"; then
		if ({ /bin/sh -c "${SUDO_PREFIX_CMD} umount /opt/stack/data/drives/sdb1 2>&1" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNWARN "Failed to umount /opt/stack/data/drives/sdb1 for swift."
		else
			PRNINFO "Succeed to umount /opt/stack/data/drives/sdb1 for swift."
		fi
	fi
	if ! /bin/sh -c "${SUDO_PREFIX_CMD} df -k | grep -q '/opt/stack/data/drives/sdb1'"; then
		if /bin/sh -c "${SUDO_PREFIX_CMD} cp -p /etc/fstab /etc/fstab.new >/dev/null 2>&1"; then
			if /bin/sh -c "${SUDO_PREFIX_CMD} grep -v '/opt/stack/data/drives/sdb1' /etc/fstab 2>&1 | ${SUDO_PREFIX_CMD} tee /etc/fstab.new >/dev/null 2>&1"; then
				if ! /bin/sh -c "${SUDO_PREFIX_CMD} diff /etc/fstab /etc/fstab.new >/dev/null 2>&1"; then
					if /bin/sh -c "${SUDO_PREFIX_CMD} mv /etc/fstab.new /etc/fstab >/dev/null 2>&1"; then
						PRNINFO "Succeed to filter /opt/stack/data/drives/sdb1 entry from /etc/fstab."
					else
						PRNWARN "Failed to filter /opt/stack/data/drives/sdb1 entry from /etc/fstab."
					fi
				else
					PRNINFO "fstab does not have /opt/stack/data/drives/sdb1 entry, nothing to do."
				fi
			else
				PRNWARN "Failed to filter /etc/fstab file."
			fi
		else
			PRNWARN "Failed to copy /etc/fstab backup"
		fi
	else
		PRNWARN "Could not umount /opt/stack/data/drives/sdb1 for swift"
	fi
	PRNINFO "Finished to cleanup /etc/fetab and umount for swift"

	#
	# Messages
	#
	PRNSUCCESS "Stopped and Cleanup ${DEVSTACK_NAME}"
fi

#==============================================================
# Start devstack
#==============================================================
if [ "${RUN_MODE}" = "start" ]; then

	PRNTITLE "Start ${DEVSTACK_NAME}"

	#
	# [PRE-PROCESSING] Check kvm driver
	#
	PRNMSG "[PRE-PROCESSING] Check kvm_amd drivers"

	if lsmod | grep -q ^kvm_amd; then
		PRNINFO "Found kvm_amd driver and it is loaded."
	elif lsmod | grep -q ^kvm_intel; then
		PRNINFO "Found kvm_intel driver and it is loaded."
	else
		PRNERR "Not found kvm_amd driver and it is not loaded."
		exit 1
	fi

	#
	# [PRE-PROCESSING] Check nest kvm_amd
	#
	PRNMSG "[PRE-PROCESSING] Check nest kvm_amd"

	_KVM_AMD_NEST=$(cat /sys/module/kvm_amd/parameters/nested 2>/dev/null)
	_KVM_INTEL_NEST=$(cat /sys/module/kvm_intel/parameters/nested 2>/dev/null)
	if [ -n "${_KVM_AMD_NEST}" ] && { [ "${_KVM_AMD_NEST}" = "Y" ] || [ "${_KVM_AMD_NEST}" = "1" ]; }; then
		PRNINFO "Already set nest kvm_amd driver."

		if ! /bin/sh -c "${SUDO_PREFIX_CMD} /bin/sh -c \"/usr/sbin/modprobe -r kvm_amd >/dev/null 2>&1\""; then
			PRNERR "Failed to run \"/usr/sbin/modprobe -r kvm_amd\""
			exit 1
		fi
		if ! /bin/sh -c "${SUDO_PREFIX_CMD} /bin/sh -c \"/usr/sbin/modprobe kvm_amd nested=1 >/dev/null 2>&1\""; then
			PRNERR "Failed to run \"/usr/sbin/modprobe kvm_amd nested=1\""
			exit 1
		fi
	elif [ -n "${_KVM_INTEL_NEST}" ] && { [ "${_KVM_INTEL_NEST}" = "Y" ] || [ "${_KVM_INTEL_NEST}" = "1" ]; }; then
		PRNINFO "Already set nest kvm_intel driver."

		if ! /bin/sh -c "${SUDO_PREFIX_CMD} /bin/sh -c \"/usr/sbin/modprobe -r kvm_intel >/dev/null 2>&1\""; then
			PRNERR "Failed to run \"/usr/sbin/modprobe -r kvm_intel\""
			exit 1
		fi
		if ! /bin/sh -c "${SUDO_PREFIX_CMD} /bin/sh -c \"/usr/sbin/modprobe kvm_intel nested=1 >/dev/null 2>&1\""; then
			PRNERR "Failed to run \"/usr/sbin/modprobe kvm_intel nested=1\""
			exit 1
		fi
	else
		PRNWARN "Not set kvm_amd/kvm_intel driver nest, so set kvm_amd."

		if ! /bin/sh -c "${SUDO_PREFIX_CMD} /bin/sh -c \"echo '1' > /sys/module/kvm_amd/parameters/nested\""; then
			PRNERR "Failed to set 1 to /sys/module/kvm_amd/parameters/nested."
			exit 1
		fi
		PRNINFO "Set 1 to /sys/module/kvm_amd/parameters/nested."
		PRNINFO "${CYEL}Reboot the host${CDEF} for the kvm_amd nest configuration to take effect."
		exit 0
	fi

	#
	# [PRE-PROCESSING] Check and Create fuse module configuration
	#
	PRNMSG "[PRE-PROCESSING] Check and Create fuse module configuration"

	if [ ! -f /etc/sysconfig/modules/fuse.modules ]; then
		PRNINFO "[PRE-PROCESSING] Not found fuse.modules file, so create it"

		(
			echo "#!/bin/sh"
			echo ""
			echo "if [ ! -c /dev/input/uinput ] ; then"
			echo "	exec /sbin/modprobe fuse >/dev/null 2>&1"
			echo "fi"
		) | /bin/sh -c "${SUDO_PREFIX_CMD} tee /etc/sysconfig/modules/fuse.modules" >/dev/null

		if ! /bin/sh -c "${SUDO_PREFIX_CMD} chmod +x /etc/sysconfig/modules/fuse.modules"; then
			PRNERR "Failed to create /etc/sysconfig/modules/fuse.modules file."
			exit 1
		fi
		PRNINFO "Created fuse.modules file"
	else
		PRNINFO "Already existed fuse.modules file"
	fi

	#
	# [PRE-PROCESSING] Load fuse module
	#
	PRNMSG "[PRE-PROCESSING] Check fuse module loading"

	if lsmod | grep -q ^fuse; then
		PRNINFO "Already load fuse module."
	else
		PRNWARN "Not load fuse module."

		if ! /bin/sh -c "${SUDO_PREFIX_CMD} /sbin/modprobe fuse >/dev/null 2>&1"; then
			PRNERR "Failed to load fuse module."
			exit 1
		fi
		PRNINFO "Loaded fuse module."
	fi

	#
	# [PRE-PROCESSING] Check IPv6 in sysctl setting
	#
	PRNMSG "[PRE-PROCESSING] Check IPv6 in sysctl setting"

	for _TMP_SYSCTL_CONF_FILE in /etc/sysctl.d/*; do
		if [ ! -f "${_TMP_SYSCTL_CONF_FILE}" ]; then
			continue
		fi

		#
		# Check net.ipv6.conf.all.disable_ipv6 key in file
		#
		_DISABLE_IPV6_VALUE=$(grep 'net.ipv6.conf.all.disable_ipv6' "${_TMP_SYSCTL_CONF_FILE}" | sed -e 's#net.ipv6.conf.all.disable_ipv6[[:space:]]*=[[:space:]]*##g')

		if [ -n "${_DISABLE_IPV6_VALUE}" ] && [ "${_DISABLE_IPV6_VALUE}" -eq 1 ]; then
			#
			# Modify file for IPv6 disable to 0
			#
			if ! /bin/sh -c "${SUDO_PREFIX_CMD} sed -i -e 's#net.ipv6.conf.all.disable_ipv6[[:space:]]*=[[:space:]]*1#net.ipv6.conf.all.disable_ipv6 = 0#g' ${_TMP_SYSCTL_CONF_FILE}"; then
				PRNERR "Failed to modify ${_TMP_SYSCTL_CONF_FILE} file."
				exit 1
			fi
			PRNINFO "Modified ${_TMP_SYSCTL_CONF_FILE} file."

			#
			# Reload sysctl file
			#
			if ! /bin/sh -c "${SUDO_PREFIX_CMD} sysctl -p ${_TMP_SYSCTL_CONF_FILE}" >/dev/null 2>&1; then
				PRNERR "Failed to reload ${_TMP_SYSCTL_CONF_FILE}"
				exit 1
			fi
			PRNINFO "Reloaded ${_TMP_SYSCTL_CONF_FILE} file."
		else
			PRNINFO "Already enable IPv6 in ${_TMP_SYSCTL_CONF_FILE}"
		fi
	done

	#
	# [PRE-PROCESSING] Check and Restore default repositories
	#
	PRNMSG "[PRE-PROCESSING] Check and Restore default repositories"

	if ({ /bin/sh -c "${SUDO_PREFIX_CMD} dnf makecache 2>&1" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
		PRNERR "Failed to run dnf makecache."
		exit 1
	else
		PRNINFO "Succeed to run dnf makecache."
	fi

	#
	# Setup and Enables Rocky repositories
	#
	if [ -f /etc/yum.repos.d/rocky.repo.org ] && [ ! -f /etc/yum.repos.d/rocky.repo ]; then
		if ({ /bin/sh -c "${SUDO_PREFIX_CMD} mv /etc/yum.repos.d/rocky.repo.org /etc/yum.repos.d/rocky.repo" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to rename from /etc/yum.repos.d/rocky.repo.org to /etc/yum.repos.d/rocky.repo"
			exit 1
		fi
		PRNINFO "Succeed to rename from /etc/yum.repos.d/rocky.repo.org to /etc/yum.repos.d/rocky.repo"
	fi
	if [ -f /etc/yum.repos.d/rocky-devel.repo.org ] && [ ! -f /etc/yum.repos.d/rocky-devel.repo ]; then
		if ({ /bin/sh -c "${SUDO_PREFIX_CMD} mv /etc/yum.repos.d/rocky-devel.repo.org /etc/yum.repos.d/rocky-devel.repo" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to rename from /etc/yum.repos.d/rocky-devel.repo.org to /etc/yum.repos.d/rocky-devel.repo"
			exit 1
		fi
		PRNINFO "Succeed to rename from /etc/yum.repos.d/rocky-devel.repo.org to /etc/yum.repos.d/rocky-devel.repo"
	fi
	if [ -f /etc/yum.repos.d/rocky-extras.repo.org ] && [ ! -f /etc/yum.repos.d/rocky-extras.repo ]; then
		if ({ /bin/sh -c "${SUDO_PREFIX_CMD} mv /etc/yum.repos.d/rocky-extras.repo.org /etc/yum.repos.d/rocky-extras.repo" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to rename from /etc/yum.repos.d/rocky-extras.repo.org to /etc/yum.repos.d/rocky-extras.repo"
			exit 1
		fi
		PRNINFO "Succeed to rename from /etc/yum.repos.d/rocky-extras.repo.org to /etc/yum.repos.d/rocky-extras.repo"
	fi
	if [ -f /etc/yum.repos.d/rocky-addons.repo.org ] && [ ! -f /etc/yum.repos.d/rocky-addons.repo ]; then
		if ({ /bin/sh -c "${SUDO_PREFIX_CMD} mv /etc/yum.repos.d/rocky-addons.repo.org /etc/yum.repos.d/rocky-addons.repo" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to rename from /etc/yum.repos.d/rocky-addons.repo.org to /etc/yum.repos.d/rocky-addons.repo"
			exit 1
		fi
		PRNINFO "Succeed to rename from /etc/yum.repos.d/rocky-addons.repo.org to /etc/yum.repos.d/rocky-addons.repo"
	fi

	#
	# Setup and Enables RabbitMQ repository
	#
	if ! dnf repolist 2>/dev/null | grep -q rabbitmq-38; then
		if ({ /bin/sh -c "${SUDO_PREFIX_CMD} dnf install -y centos-release-rabbitmq-38 2>&1" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to install centos-release-rabbitmq-38."
			exit 1
		fi
		PRNINFO "Succeed to install centos-release-rabbitmq-38."
	fi

	#
	# Setup and Enables OpenStack RDO repository
	#
	if ! dnf repolist 2>/dev/null | grep -q openstack-caracal; then
		if ({ /bin/sh -c "${SUDO_PREFIX_CMD} dnf install -y centos-release-openstack-caracal 2>&1" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to install centos-release-openstack-caracal."
			exit 1
		fi
		PRNINFO "Succeed to install centos-release-openstack-caracal."
	fi

	#
	# Setup and Enables Rocky CRB repository
	#
	if dnf repolist all 2>/dev/null | grep -q rocky-crb; then
		if ! dnf repolist 2>/dev/null | grep -q rocky-crb; then
			if ({ /bin/sh -c "${SUDO_PREFIX_CMD} dnf config-manager --set-enabled rocky-crb 2>&1" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
				PRNERR "Failed to enable rocky-crb repository."
				exit 1
			fi
			PRNINFO "Succeed to enable rocky-crb repository."
		fi
	fi

	#
	# Disable repositories : appstream, vaseos, crb, epel, mariadb-*
	#
	if dnf repolist all 2>/dev/null | grep -q '^rocky-appstream'; then
		if dnf repolist 2>/dev/null | grep -q '^appstream'; then
			if ({ /bin/sh -c "${SUDO_PREFIX_CMD} dnf config-manager --set-disabled appstream 2>&1" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
				PRNWARN "Failed to disable appstream repos"
			else
				PRNINFO "Succeed to disable appstream repos"
			fi
		fi
	fi
	if dnf repolist all 2>/dev/null | grep -q '^rocky-baseos'; then
		if dnf repolist 2>/dev/null | grep -q '^baseos'; then
			if ({ /bin/sh -c "${SUDO_PREFIX_CMD} dnf config-manager --set-disabled baseos 2>&1" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
				PRNWARN "Failed to disable baseos repos"
			else
				PRNINFO "Succeed to disable baseos repos"
			fi
		fi
	fi
	if dnf repolist all 2>/dev/null | grep -q '^rocky-crb'; then
		if dnf repolist 2>/dev/null | grep -q '^crb'; then
			if ({ /bin/sh -c "${SUDO_PREFIX_CMD} dnf config-manager --set-disabled crb 2>&1" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
				PRNWARN "Failed to disable crb repos"
			else
				PRNINFO "Succeed to disable crb repos"
			fi
		fi
	fi
	if dnf repolist all 2>/dev/null | grep -q '^rocky-extras'; then
		if dnf repolist 2>/dev/null | grep -q '^extras'; then
			if ({ /bin/sh -c "${SUDO_PREFIX_CMD} dnf config-manager --set-disabled extras 2>&1" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
				PRNWARN "Failed to disable extras repos"
			else
				PRNINFO "Succeed to disable extras repos"
			fi
		fi
	fi
	if dnf repolist 2>/dev/null | grep -q '^mariadb'; then
		if ({ /bin/sh -c "${SUDO_PREFIX_CMD} dnf config-manager --set-disabled mariadb-main 2>&1" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNWARN "Failed to disable mariadb-main repository."
		else
			PRNINFO "Succeed to disable mariadb-main repository."
		fi
		if ({ /bin/sh -c "${SUDO_PREFIX_CMD} dnf config-manager --set-disabled mariadb-maxscale 2>&1" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNWARN "Failed to disable mariadb-maxscale repository."
		else
			PRNINFO "Succeed to disable mariadb-maxscale repository."
		fi
		if ({ /bin/sh -c "${SUDO_PREFIX_CMD} dnf config-manager --set-disabled mariadb-tools 2>&1" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNWARN "Failed to disable mariadb-tools repository."
		else
			PRNINFO "Succeed to disable mariadb-tools repository."
		fi
	fi
	if dnf repolist all 2>/dev/null | grep -q '^epel'; then
		if ({ /bin/sh -c "${SUDO_PREFIX_CMD} dnf config-manager --set-disabled epel 2>&1" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNWARN "Failed to disable epel repos"
		else
			PRNINFO "Succeed to disable epel repos"
		fi
	fi
	if dnf repolist all 2>/dev/null | grep -q '^epel-next'; then
		if ({ /bin/sh -c "${SUDO_PREFIX_CMD} dnf config-manager --set-disabled epel-next 2>&1" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNWARN "Failed to disable epel-next repos"
		else
			PRNINFO "Succeed to disable epel-next repos"
		fi
	fi
	if dnf repolist all 2>/dev/null | grep -q '^epel-testing'; then
		if ({ /bin/sh -c "${SUDO_PREFIX_CMD} dnf config-manager --set-disabled epel-testing 2>&1" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNWARN "Failed to disable epel-testing repos"
		else
			PRNINFO "Succeed to disable epel-testing repos"
		fi
	fi

	#
	# [PRE-PROCESSING] Check and Install pip
	#
	PRNMSG "[PRE-PROCESSING] Check and Install pip"

	if ! python --version 2>/dev/null | grep -q '3.9'; then
		PRNERR "This host has a version other than Python 3.9 installed. This script targets 3.9."
		exit 1
	fi
	if ! pip --version 2>/dev/null | grep -q 'python[[:space:]]*3.9'; then
		#
		# Install pip for Python 3.9
		#
		PRNINFO "Not found pip for Python 3.9, so install it."

		#
		# Get pip installer
		#
		if ! curl -s -S -o /tmp/get-pip.py https://bootstrap.pypa.io/get-pip.py; then
			PRNERR "Failed to download pip installer."
			exit 1
		fi

		#
		# Install pip
		#
		if ({ /bin/sh -c "${SUDO_PREFIX_CMD} python3.9 /tmp/get-pip.py" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to install pip for Python 3.9."
			rm -f /tmp/get-pip.py
			exit 1
		fi
		rm -f /tmp/get-pip.py

		PRNINFO "installed pip for Python 3.9."
	else
		PRNINFO "Already installed pip for Python 3.9."
	fi

	#
	# [PRE-PROCESSING] Install bind-utils
	#
	PRNMSG "[PRE-PROCESSING] Check and Install bind-utils"

	if ! dnf list installed 2>/dev/null | grep -q 'bind-utils'; then
		#
		# Install bind-utils
		#
		PRNINFO "Not found bind-utils, so install it."

		#
		# Install bind-utils
		#
		if ({ /bin/sh -c "${SUDO_PREFIX_CMD} dnf install -y bind-utils" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to install bind-utils package."
			exit 1
		fi
		PRNINFO "Installed bind-utils."
	else
		PRNINFO "Already installed bind-utils."
	fi

	#
	# [PRE-PROCESSING] Install mariadb
	#
	PRNMSG "[PRE-PROCESSING] Check and Install mariadb"

	if ! dnf list installed 2>/dev/null | grep -q 'MariaDB-server'; then
		#
		# Install mariadb
		#
		PRNINFO "Not found mariadb, so install it."

		#
		# Get mariadb repository setup
		#
		if ! curl -L -s -S -o /tmp/mariadb_repo_setup https://downloads.mariadb.com/MariaDB/mariadb_repo_setup; then
			PRNERR "Failed to get mariadb repository setup."
			exit 1
		fi

		#
		# Setup mariadb
		#
		if ({ /bin/sh -c "${SUDO_PREFIX_CMD} /bin/bash /tmp/mariadb_repo_setup" 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to setup mariadb repository."
			rm -f /tmp/mariadb_repo_setup
			exit 1
		fi
		rm -f /tmp/mariadb_repo_setup

		#
		# Install mariadb
		#
		if ({ /bin/sh -c "${SUDO_PREFIX_CMD} dnf install -y MariaDB-server" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to install MariaDB-server package."
			exit 1
		fi
		PRNINFO "Installed MariaDB-server."
	else
		PRNINFO "Already installed mariadb."
	fi

	#
	# [PRE-PROCESSING] Install Apache(httpd)
	#
	PRNMSG "[PRE-PROCESSING] Check and Install Apache(httpd)"

	if ! dnf list installed 2>/dev/null | grep -q '^httpd\.'; then
		#
		# Install Apache(httpd)
		#
		PRNINFO "Not found Apache(httpd), so install it."

		#
		# Install Apache(httpd)
		#
		if ({ /bin/sh -c "${SUDO_PREFIX_CMD} dnf install -y httpd" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to install Apache(httpd) package."
			exit 1
		fi
		PRNINFO "Installed Apache(httpd)."
	else
		PRNINFO "Already installed Apache(httpd)."
	fi

	#
	# [PRE-PROCESSING] Install iSCSI utils
	#
	PRNMSG "[PRE-PROCESSING] Check and Install iSCSI utils"

	if ! dnf list installed 2>/dev/null | grep -q '^iscsi-initiator-utils\.'; then
		#
		# Install iSCSI utils
		#
		PRNINFO "Not found iSCSI utils, so install it."

		#
		# Install iSCSI utils
		#
		if ({ /bin/sh -c "${SUDO_PREFIX_CMD} dnf install -y iscsi-initiator-utils" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to install iSCSI utils package."
			exit 1
		fi
		PRNINFO "Installed iSCSI utils."
	else
		PRNINFO "Already installed iSCSI utils."
	fi

	#
	# [PRE-PROCESSING] Install libvirt daemon
	#
	PRNMSG "[PRE-PROCESSING] Install libvirt daemon"

	if ! dnf list installed 2>/dev/null | grep -q '^libvirt-daemon\.'; then
		#
		# Install libvirt daemon
		#
		PRNINFO "Not found libvirt daemon, so install it."

		#
		# Install libvirt daemon
		#
		if ({ /bin/sh -c "${SUDO_PREFIX_CMD} dnf install -y libvirt-daemon" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to install libvirt daemon package."
			exit 1
		fi
		PRNINFO "Succeed to installed libvirt daemon."

		#
		# Set libvirtd.service to enable
		#
		if ! /bin/sh -c "${SUDO_PREFIX_CMD} systemctl is-enabled libvirtd >/dev/null 2>&1"; then
			if ({ /bin/sh -c "${SUDO_PREFIX_CMD} systemctl enable libvirtd" 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
				PRNERR "Failed to enable libvirtd service."
				exit 1
			fi
			PRNINFO "Succeed to enable libvirtd service."
		else
			PRNINFO "Already enable libvirtd service."
		fi
	else
		PRNINFO "Already installed libvirt daemon."
	fi

	#
	# [PRE-PROCESSING] Install QEMU driver for libvirt daemon
	#
	PRNMSG "[PRE-PROCESSING] Check and Install QEMU driver for libvirt daemon"

	if ! dnf list installed 2>/dev/null | grep -q '^libvirt-daemon-driver-qemu\.'; then
		#
		# Install QEMU driver for libvirt daemon
		#
		PRNINFO "Not found QEMU driver for libvirt daemon, so install it."

		#
		# Install QEMU driver for libvirt daemon
		#
		if ({ /bin/sh -c "${SUDO_PREFIX_CMD} dnf install -y libvirt-daemon-driver-qemu" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to install QEMU driver for libvirt daemon package."
			exit 1
		fi
		PRNINFO "Installed QEMU driver for libvirt daemon."
	else
		PRNINFO "Already installed QEMU driver for libvirt daemon."
	fi

	#
	# [PRE-PROCESSING] Modify /etc/libvirt/libvirt.conf
	#
	# [NOTE]
	# In some cases, the message Permission Denied will be displayed,
	# so change the permissions.
	#
	PRNMSG "[PRE-PROCESSING] Modify /etc/libvirt/libvirt.conf"

	if /bin/sh -c "${SUDO_PREFIX_CMD} stat /etc/libvirt/libvirt.conf >/dev/null 2>&1" && ! /bin/sh -c "${SUDO_PREFIX_CMD} grep -q 'unix_sock_group' /etc/libvirt/libvirt.conf"; then
		{
			echo ''
			echo 'unix_sock_group = "libvirt"'
			echo 'unix_sock_ro_perms = "0777"'
			echo 'unix_sock_rw_perms = "0770"'
			echo ''
		} | /bin/sh -c "${SUDO_PREFIX_CMD} tee -a /etc/libvirt/libvirt.conf" >/dev/null

		PRNINFO "Modified /etc/libvirt/libvirt.conf"
	else
		PRNINFO "Not modify /etc/libvirt/libvirt.conf"
	fi

	#
	# [PRE-PROCESSING] Install libvirt daemon and Setting
	#
	PRNMSG "[PRE-PROCESSING] Check and Install libvirt daemon and Setting"

	#
	# Check and Run libvirtd.service
	#
	if ({ /bin/sh -c "${SUDO_PREFIX_CMD} systemctl is-active libvirtd" 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
		PRNINFO "libvirtd service is not running, so start it."
		_TMP_LIBVIRT_START_OPT="start"
	else
		PRNINFO "Already running libvirtd service, so restart it."
		_TMP_LIBVIRT_START_OPT="restart"
	fi
	if ({ /bin/sh -c "${SUDO_PREFIX_CMD} systemctl ${_TMP_LIBVIRT_START_OPT} libvirtd" 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
		PRNERR "Failed to start libvirtd service."
		exit 1
	fi
	PRNINFO "Succeed to ${_TMP_LIBVIRT_START_OPT} libvirtd services."

	#
	# [PRE-PROCESSING] Destroy default libvirt network
	#
	PRNMSG "[PRE-PROCESSING] Destroy default libvirt network"

	if /bin/sh -c "${SUDO_PREFIX_CMD} virsh net-list --all 2>/dev/null | grep -v inactive | grep -q default"; then
		if ({ /bin/sh -c "${SUDO_PREFIX_CMD} virsh net-destroy default" 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNWARN "Failed to destroy default libvirt network by virsh"
		else
			PRNINFO "Succeed to destroy default libvirt network by virsh"
		fi
	else
		PRNINFO "Already destroy default libvirt network"
	fi
	if /bin/sh -c "${SUDO_PREFIX_CMD} virsh net-list --all 2>/dev/null | grep default | awk '{print $3}' | grep -q -i 'yes'"; then
		if ({ /bin/sh -c "${SUDO_PREFIX_CMD} virsh net-autostart --network default --disable" 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNWARN "Failed to set disable autostart for default libvirt network by virsh"
		else
			PRNINFO "Succeed to set disable autostart for default libvirt network by virsh"
		fi
	else
		PRNINFO "Already disable autostart for default libvirt network"
	fi
	PRNINFO "Succeed to destroy default libvirt network"

	#
	# [PRE-PROCESSING] Install libvirt for Python 3
	#
	PRNMSG "[PRE-PROCESSING] Check and Install libvirt for Python 3"

	if ! dnf list installed 2>/dev/null | grep -q '^python3-libvirt\.'; then
		#
		# Install libvirt for Python 3
		#
		PRNINFO "Not found libvirt for Python 3, so install it."

		#
		# Install libvirt for Python 3
		#
		if ({ /bin/sh -c "${SUDO_PREFIX_CMD} dnf install -y python3-libvirt" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to install libvirt for Python 3 package."
			exit 1
		fi
		PRNINFO "Installed libvirt for Python 3."
	else
		PRNINFO "Already installed libvirt for Python 3."
	fi

	#
	# [PRE-PROCESSING] Install Memcached
	#
	PRNMSG "[PRE-PROCESSING] Check and Install Memcached"

	if ! dnf list installed 2>/dev/null | grep -q '^memcached\.'; then
		#
		# Install Memcached
		#
		PRNINFO "Not found Memcached, so install it."

		#
		# Install Memcached
		#
		if ({ /bin/sh -c "${SUDO_PREFIX_CMD} dnf install -y memcached" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to install Memcached package."
			exit 1
		fi
		PRNINFO "Installed Memcached."
	else
		PRNINFO "Already installed Memcached."
	fi

	#
	# Set to use only IPv4
	#
	if [ -f /etc/sysconfig/memcached ]; then
		if ! /bin/sh -c "${SUDO_PREFIX_CMD} sed -i -e 's#-l 127.0.0.1,::1#-l 127.0.0.1#g' /etc/sysconfig/memcached >/dev/null 2>&1"; then
			PRNERR "Failed to modify /etc/sysconfig/memcached file."
			exit 1
		fi
		if ! /bin/sh -c "${SUDO_PREFIX_CMD} systemctl enable memcached >/dev/null 2>&1"; then
			PRNERR "Failed to enable memcached"
			exit 1
		fi
		if ! /bin/sh -c "${SUDO_PREFIX_CMD} systemctl restart memcached >/dev/null 2>&1"; then
			PRNERR "Failed to restart memcached."
			exit 1
		fi
	fi

	#
	# [PRE-PROCESSING] Install HAProxy
	#
	PRNMSG "[PRE-PROCESSING] Check and Install HAProxy"

	if ! dnf list installed 2>/dev/null | grep -q '^haproxy\.'; then
		#
		# Install HAProxy
		#
		PRNINFO "Not found HAProxy, so install it."

		#
		# Install HAProxy
		#
		if ({ /bin/sh -c "${SUDO_PREFIX_CMD} dnf install -y haproxy" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to install HAProxy package."
			exit 1
		fi
		PRNINFO "Installed HAProxy."
	else
		PRNINFO "Already installed HAProxy."
	fi

	#
	# [PRE-PROCESSING] Check and Install Python uWSGI
	#
	PRNMSG "[PRE-PROCESSING] Check and Install Python uWSGI"

	if ! pip3 freeze | grep -q -i '^uwsgi'; then
		#
		# Install Python uWSGI
		#
		PRNINFO "Not found Python uWSGI, so install it."

		#
		# Check and Install python3-devel
		#
		if ! dnf list installed 2>/dev/null | grep -q '^python3-devel\.'; then
			#
			# Install python3-devel
			#
			if ({ /bin/sh -c "${SUDO_PREFIX_CMD} dnf install -y python3-devel" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
				PRNERR "Failed to install python3-devel package."
				exit 1
			fi
			PRNINFO "Installed python3-devel."
		fi

		#
		# Install Python uWSGI
		#
		if ({ /bin/sh -c "${SUDO_PREFIX_CMD} pip3 install uwsgi" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to install Python uWSGI package."
			exit 1
		fi
		PRNINFO "Installed Python uWSGI."
	else
		PRNINFO "Already installed Python uWSGI."
	fi

	#
	# [PRE-PROCESSING] Install dstat command
	#
	PRNMSG "[PRE-PROCESSING] Check and Install dstat command"

	if ! dnf list installed 2>/dev/null | grep -q '^pcp-system-tools\.'; then
		#
		# Install dstat command
		#
		PRNINFO "Not found dstat command, so install it."

		if ({ /bin/sh -c "${SUDO_PREFIX_CMD} dnf install -y pcp-system-tools" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to install dstat command package."
			exit 1
		fi
		PRNINFO "Installed dstat command."
	else
		PRNINFO "Already installed dstat command."
	fi

	#
	# [PRE-PROCESSING] Install debootstrap packages
	#
	# [NOTE]
	# If debootstrap is newer than 1.0.134, building the guest os image will fail.
	# This is because the configuration file (directory) for jammy is no longer
	# available and the PGP key is old.
	# When building an image with RockyLinux, PGP updates are difficult, so we will
	# apply a patch to debootstrap here.
	#
	PRNMSG "[PRE-PROCESSING] Check and Install debootstrap package"

	if ! dnf list installed 2>/dev/null | grep -q '^debootstrap\.'; then
		#
		# Install debootstrap packages
		#
		PRNINFO "Not found debootstrap package, so install it."

		if ({ /bin/sh -c "${SUDO_PREFIX_CMD} dnf --enablerepo=epel install -y debootstrap" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to install debootstrap package."
			exit 1
		fi
		PRNINFO "Installed debootstrap package."
	else
		PRNINFO "Already installed debootstrap package."
	fi

	#
	# [PRE-PROCESSING] Install xorriso packages for mkisofs command
	#
	# [NOTE]
	# Install xorriso, which contains the mkisofs command.
	# This is used in os-test-images.
	#
	PRNMSG "[PRE-PROCESSING] Install xorriso packages for mkisofs command"

	if ! command -v mkisofs >/dev/null 2>&1; then
		if ! dnf list installed 2>/dev/null | grep -q '^xorriso\.'; then
			#
			# Install xorriso packages
			#
			PRNINFO "Not found xorriso package, so install it."

			if ({ /bin/sh -c "${SUDO_PREFIX_CMD} dnf install -y xorriso" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
				PRNERR "Failed to install xorriso package."
				exit 1
			fi
			PRNINFO "Installed xorriso package."
		else
			PRNINFO "Already installed xorriso package. But why does not exist mkisofs command? (this script will fail.)"
		fi
	else
		PRNINFO "Already installed mkisofs command."
	fi

	#
	# Patch for jammy(like 1.0.134 version)
	#
	if [ -f /usr/share/debootstrap/scripts/jammy ]; then
		PRNINFO "Found /usr/share/debootstrap/scripts/jammy file in debootstrap package, so nothing to do."
	else
		#
		# Create symlink /usr/share/debootstrap/scripts/jammy to /usr/share/debootstrap/scripts/gutsy
		#
		PRNINFO "Not found /usr/share/debootstrap/scripts/jammy file in debootstrap package, so create symlink to gutsy."

		if ({ /bin/sh -c "${SUDO_PREFIX_CMD} ln -s /usr/share/debootstrap/scripts/gutsy /usr/share/debootstrap/scripts/jammy" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to create symlink /usr/share/debootstrap/scripts/jammy to /usr/share/debootstrap/scripts/gutsy"
			exit 1
		fi
	fi

	#
	# Patch for ignore for checking pgp
	#
	if [ -f /usr/local/lib/python3.9/site-packages/diskimage_builder/elements/debootstrap/root.d/08-debootstrap ]; then
		if ! /bin/sh -c "${SUDO_PREFIX_CMD} sed -i -e 's#--variant=minbase[[:space:]]*\\\\#--variant=minbase --no-check-gpg \\\\#g' /usr/local/lib/python3.9/site-packages/diskimage_builder/elements/debootstrap/root.d/08-debootstrap" >/dev/null 2>&1; then
			PRNERR "Failed to set ignoring check pgp file."
			exit 1
		fi
		PRNINFO "Succeed to patch for ignore for checking pgp."
	fi

	#
	# [PRE-PROCESSING] Install liberasurecode-devel and rsync-daemon for Swift and PyECLib
	#
	# [NOTE]
	# When we enable Swift and run stack.sh, the following error occurs:
	#    ERROR: Failed building wheel for PyECLib
	# To avoid this, you need to install liberasurecode-devel.
	#
	PRNMSG "[PRE-PROCESSING] Install liberasurecode-devel and rsync-daemon for Swift and PyECLib"

	if ! dnf list installed 2>/dev/null | grep -q '^liberasurecode-devel\.'; then
		#
		# Install liberasurecode-devel packages
		#
		PRNINFO "Not found liberasurecode-devel package, so install it."

		if ({ /bin/sh -c "${SUDO_PREFIX_CMD} dnf install -y liberasurecode-devel" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to install liberasurecode-devel package."
			exit 1
		fi
		PRNINFO "Installed liberasurecode-devel package."
	else
		PRNINFO "Already installed liberasurecode-devel package."
	fi
	if ! dnf list installed 2>/dev/null | grep -q '^rsync-daemon\.'; then
		#
		# Install rsync-daemon packages
		#
		PRNINFO "Not found rsync-daemon package, so install it."

		if ({ /bin/sh -c "${SUDO_PREFIX_CMD} dnf install -y rsync-daemon" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to install rsync-daemon package."
			exit 1
		fi
		PRNINFO "Installed rsync-daemon package."
	else
		PRNINFO "Already installed rsync-daemon package."
	fi

	#
	# [PRE-PROCESSING] Uninstall conflict packages
	#
	PRNMSG "[PRE-PROCESSING] Check and Uninstall conflict packages"

	if dnf list installed 2>/dev/null | grep -q '^python3-requests\.'; then
		#
		# Found python3-requests package
		#
		PRNINFO "Found python3-requests package, so uninstall it."

		#
		# Uninstall python3-requests package
		#
		if ({ /bin/sh -c "${SUDO_PREFIX_CMD} dnf remove -y python3-requests" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to uninstall python3-requests package."
			exit 1
		fi
		PRNINFO "Uninstalled python3-requests package."
	else
		PRNINFO "Already uninstalled python3-requests package."
	fi

	if dnf list installed 2>/dev/null | grep -q '^python3-chardet\.'; then
		#
		# Found python3-chardet package
		#
		PRNINFO "Found python3-chardet package, so uninstall it."

		#
		# Uninstall python3-chardet package
		#
		if ({ /bin/sh -c "${SUDO_PREFIX_CMD} dnf remove -y python3-chardet" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to uninstall python3-chardet package."
			exit 1
		fi
		PRNINFO "Uninstalled python3-chardet package."
	else
		PRNINFO "Already uninstalled python3-chardet package."
	fi

	if dnf list installed 2>/dev/null | grep -q '^python3-jsonschema\.'; then
		#
		# Found python3-jsonschema package
		#
		PRNINFO "Found python3-jsonschema package, so uninstall it."

		#
		# Uninstall python3-jsonschema package
		#
		if ({ /bin/sh -c "${SUDO_PREFIX_CMD} dnf remove -y python3-jsonschema" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to uninstall python3-jsonschema package."
			exit 1
		fi
		PRNINFO "Uninstalled python3-jsonschema package."
	else
		PRNINFO "Already uninstalled python3-jsonschema package."
	fi

	if dnf list installed 2>/dev/null | grep -q '^python3-ptyprocess\.'; then
		#
		# Found python3-ptyprocess package
		#
		PRNINFO "Found python3-ptyprocess package, so uninstall it."

		#
		# Uninstall python3-ptyprocess package
		#
		if ({ /bin/sh -c "${SUDO_PREFIX_CMD} dnf remove -y python3-ptyprocess" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to uninstall python3-ptyprocess package."
			exit 1
		fi
		PRNINFO "Uninstalled python3-ptyprocess package."
	else
		PRNINFO "Already uninstalled python3-ptyprocess package."
	fi

	#
	# [PRE-PROCESSING] Check and Set SHA1(old) crypto policy
	#
	PRNMSG "[PRE-PROCESSING] Check and Set SHA1(old) crypto policy"

	if ! update-crypto-policies --show | grep -q 'SHA1'; then
		#
		# Not set SHA1(old) crypto policy
		#
		PRNINFO "Not set SHA1(old) crypto policy."

		#
		# Set SHA1(old) crypto policy
		#
		if ({ /bin/sh -c "${SUDO_PREFIX_CMD} update-crypto-policies --set DEFAULT:SHA1" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to set SHA1(old) crypto policy."
			exit 1
		fi
		PRNINFO "Set SHA1(old) crypto policy."
	else
		PRNINFO "Already set SHA1(old) crypto policy."
	fi

	#
	# [PRE-PROCESSING] Check and Setup iptables service
	#
	# If the firewalld service is running, switch to legacy iptables.
	#
	PRNMSG "[PRE-PROCESSING] Check and Setup iptables service"
	if ! systemctl status iptables >/dev/null 2>&1; then
		#
		# Try to install iptables service
		#
		PRNINFO "Try to install iptables service"

		if ({ /bin/sh -c "${SUDO_PREFIX_CMD} dnf install -y iptables-services" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to install iptables service."
			exit 1
		fi
		PRNINFO "Succeed to install iptables service."

		#
		# Stop firewalld service
		#
		PRNINFO "Stop firewalld service"

		if ({ /bin/sh -c "${SUDO_PREFIX_CMD} systemctl stop firewalld" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNWARN "Failed to stop firewalld service (It may not have been started already)."
		fi
		PRNINFO "Succeed to stop firewalld service."

		#
		# Disable firewalld service
		#
		PRNINFO "Disable firewalld service"

		if ({ /bin/sh -c "${SUDO_PREFIX_CMD} systemctl disable firewalld" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNWARN "Failed to disable firewalld service (It may not have been enabled already)."
		fi
		PRNINFO "Succeed to disable firewalld service."

		#
		# Enable iptables service
		#
		PRNINFO "Enable iptables service"

		if ({ /bin/sh -c "${SUDO_PREFIX_CMD} systemctl enable iptables" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to enable iptables service."
			exit 1
		fi
		PRNINFO "Succeed to enable iptables service."

		#
		# Start iptables service
		#
		PRNINFO "Start iptables service"

		if ({ /bin/sh -c "${SUDO_PREFIX_CMD} systemctl start iptables" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to start iptables service."
			exit 1
		fi
		PRNINFO "Succeed to start iptables service."
	fi

	#
	# [PRE-PROCESSING] Check and Add ACCEPT 80 port to iptables
	#
	PRNMSG "[PRE-PROCESSING] Check and Add ACCEPT 80 port to iptables"

	if ! /bin/sh -c "${SUDO_PREFIX_CMD} grep -q -i 'INPUT.*--dport[[:space:]]*80.*-j[[:space:]]*ACCEPT' /etc/sysconfig/iptables"; then
		_TMP_CR_CODE_FOR_SED=$(printf '\\n')
		if ! /bin/sh -c "${SUDO_PREFIX_CMD} sed -i -e 's#^.*-j[[:space:]]*REJECT.*\$##g' -e 's#^[[:space:]]*COMMIT[[:space:]]*\$#-A INPUT -p tcp -m state --state NEW -m tcp --dport 80 -j ACCEPT${_TMP_CR_CODE_FOR_SED}COMMIT#g' -e '/^\$/d' /etc/sysconfig/iptables"; then
			PRNERR "Failed to insert ACCEPT 80 port line and remove REJECT lines in iptables."
			exit 1
		fi
	else
		if ! /bin/sh -c "${SUDO_PREFIX_CMD} sed -i -e 's#^.*-j[[:space:]]*REJECT.*\$##g' -e '/^\$/d' /etc/sysconfig/iptables"; then
			PRNERR "Failed to remove REJECT lines in iptables."
			exit 1
		fi
	fi

	#
	# Restart iptabels
	#
	if ({ /bin/sh -c "${SUDO_PREFIX_CMD} service iptables restart" 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
		PRNERR "Failed to restart iptables for ACCEPT 80 port."
		exit 1
	fi
	PRNINFO "Succeed to restart iptables for ACCEPT 80 port."

	#
	# [PRE-PROCESSING] Stop dnf-makecache.timer
	#
	# [NOTE]
	# When stopping and restarting DevStack, the following command may hang in stack.sh.
	#     /usr/bin/python3.9 /usr/bin/dnf makecache --timer
	# The direct cause is that the dnf-makecache service fails to start, but it is unclear
	# why it fails to start.
	# But avoid this by not starting the dnf-makecache service.
	#
	PRNMSG "[PRE-PROCESSING] Stop dnf-makecache.timer"

	PRNINFO "Try to stop and disable dnf-makecache.timer (Not check result)"
	/bin/sh -c "${SUDO_PREFIX_CMD} systemctl stop dnf-makecache.timer" 2>&1    | sed -e 's|^|    |g'
	/bin/sh -c "${SUDO_PREFIX_CMD} systemctl disable dnf-makecache.timer" 2>&1 | sed -e 's|^|    |g'

	PRNINFO "Try to stop and disable dnf-makecache (Not check result)"
	/bin/sh -c "${SUDO_PREFIX_CMD} systemctl stop dnf-makecache" 2>&1    | sed -e 's|^|    |g'
	/bin/sh -c "${SUDO_PREFIX_CMD} systemctl disable dnf-makecache" 2>&1 | sed -e 's|^|    |g'

	#
	# [PRE-PROCESSING] Check and Start openvswitch ovs-vswitchd ovsdb-server services
	#
	# [NOTE]
	# The openvswitch ovs-vswitchd ovsdb-server services should be running.
	# Check for it and restart it if it is not running.
	#
	PRNMSG "[PRE-PROCESSING] Check and Start openvswitch ovs-vswitchd ovsdb-server services"

	if ! dnf list installed 2>/dev/null | grep -q '^openvswitch'; then
		if ! /bin/sh -c "${SUDO_PREFIX_CMD} dnf install -y openvswitch" >/dev/null 2>&1; then
			PRNERR "Failed to install openvswitch."
			exit 1
		fi
	fi

	#
	# Force enable openvswitch.service
	#
	if ! /bin/sh -c "${SUDO_PREFIX_CMD} systemctl enable openvswitch.service" >/dev/null 2>&1; then
		PRNERR "Failed to enable openvswitch.service."
		exit 1
	fi

	#
	# Force restart openvswitch.service
	#
	if ! /bin/sh -c "${SUDO_PREFIX_CMD} systemctl restart openvswitch.service" >/dev/null 2>&1; then
		PRNERR "Failed to restart openvswitch.service."
		exit 1
	fi

	#
	# Check ovs-vswitchd and ovsdb-server
	#
	_IS_RUN_OVSDB=1
	if ! /bin/sh -c "${SUDO_PREFIX_CMD} systemctl is-active ovs-vswitchd" >/dev/null 2>&1; then
		_IS_RUN_OVSDB=0
	fi
	if ! /bin/sh -c "${SUDO_PREFIX_CMD} systemctl is-active ovsdb-server" >/dev/null 2>&1; then
		_IS_RUN_OVSDB=0
	fi
	if [ "${_IS_RUN_OVSDB}" -eq 0 ]; then
		if ! /bin/sh -c "${SUDO_PREFIX_CMD} systemctl restart ovs-vswitchd ovsdb-server" >/dev/null 2>&1; then
			PRNERR "Failed to restart restart ovs-vswitchd and ovsdb-server systemd.service."
			exit 1
		fi
		PRNINFO "Succeed to restart ovs-vswitchd and ovsdb-server systemd.service."
	fi

	#
	# Initialize bridge
	#
	if ! /bin/sh -c "${SUDO_PREFIX_CMD} ovs-vsctl init" >/dev/null 2>&1; then
		PRNERR "Failed to initialize ovs bridges."
		exit 1
	fi
	_TMP_FOUND_BRIDGE=0
	_TMP_BRIDGE_LIST=$(/bin/sh -c "${SUDO_PREFIX_CMD} ovs-vsctl list-br")
	for _tmp_br_name in ${_TMP_BRIDGE_LIST}; do
		if [ "${_tmp_br_name}" = "br-int" ]; then
			_TMP_FOUND_BRIDGE=1
		fi
	done
	if [ "${_TMP_FOUND_BRIDGE}" -eq 0 ]; then
		if ! /bin/sh -c "${SUDO_PREFIX_CMD} ovs-vsctl add-br br-int" >/dev/null 2>&1; then
			PRNERR "Failed to command : ovs-vsctl add-br br-int."
			exit 1
		fi
		PRNINFO "Succeed to command : ovs-vsctl add-br br-int."
	fi
	PRNINFO "Succeed to start openvswitch ovs-vswitchd ovsdb-server services."

	#
	# [SETUP] Check and Backup devstack repository
	#
	PRNMSG "[SETUP] Check and Backup devstack repository"

	if [ -d "${DEVSTACK_GIT_TOP_DIR}" ]; then
		#
		# Found the directory for devstack repository
		#
		PRNINFO "Found the directory(${DEVSTACK_GIT_TOP_DIR}) for devstack repository."

		#
		# Confirm
		#
		echo ""
		_CONTINUE_PROCESS=0
		_USE_NEW_CLONE=0
		while [ "${_CONTINUE_PROCESS}" -eq 0 ]; do
			confirm_input "Do you use new cloned repository for devstack? [ yes(y) | no(n) ]" 0 ""
			if [ -n "${CONFIRM_RESULT}" ]; then
				if echo "${CONFIRM_RESULT}" | grep -q -i -e "yes" -e "y"; then
					_USE_NEW_CLONE=1
					_CONTINUE_PROCESS=1
				elif echo "${CONFIRM_RESULT}" | grep -q -i -e "no" -e "n"; then
					_USE_NEW_CLONE=0
					_CONTINUE_PROCESS=1
				else
					PRNWARN "Input must be \"yes(y)\" or \"no(n)\"."
				fi
			fi
		done

		if [ "${_USE_NEW_CLONE}" -eq 1 ]; then
			#
			# Backup directories
			#
			_BACKUP_SUFFIX=$(date "+%Y%m%d-%H:%M:%S")
			if ! mv "${DEVSTACK_GIT_TOP_DIR}" "${DEVSTACK_GIT_TOP_DIR}.${_BACKUP_SUFFIX}"; then
				PRNERR "Failed to backup devstack directory from ${DEVSTACK_GIT_TOP_DIR} to ${DEVSTACK_GIT_TOP_DIR}.${_BACKUP_SUFFIX}"
				exit 1
			fi
			PRNINFO "Succeed to backup devstack directory from ${DEVSTACK_GIT_TOP_DIR} to ${DEVSTACK_GIT_TOP_DIR}.${_BACKUP_SUFFIX}"
		else
			PRNINFO "Use existed devstack directory(${DEVSTACK_GIT_TOP_DIR})."
		fi
	else
		PRNINFO "Not found the directory(${DEVSTACK_GIT_TOP_DIR}) for devstack repository."
	fi

	#
	# [SETUP] Setup devstack repository and local.conf
	#
	PRNMSG "[SETUP] Setup devstack repository and local.conf"

	if [ ! -d "${DEVSTACK_GIT_TOP_DIR}" ]; then
		#
		# Clone devstack repository
		#
		if ! CloneRepositoryAndSetBranch "${DEVSTACK_GIT_NAME}" "${STACK_USER_HOME}" "${DEVSTACK_BRANCH}"; then
			exit 1
		fi

		#
		# Copy sample local.conf
		#
		PRNINFO "Copy sample local.conf"

		if ! cp ${DEVSTACK_GIT_TOP_DIR}/samples/local.conf ${DEVSTACK_GIT_TOP_DIR}/local.conf; then
			PRNERR "Failed to copy local.conf from samples/local.conf"
			exit 1
		fi
		PRNINFO "Copied local.conf from ${DEVSTACK_GIT_TOP_DIR}/samples/local.conf"
		echo ""

		#
		# Set password for all components
		#
		PRNINFO "Make local.conf with password from ${DEVSTACK_GIT_TOP_DIR}/samples/local.conf"

		if ! sed -i -e "s|_PASSWORD=.*$|_PASSWORD=${DEVSTACK_DEFAULT_PASSWORD}|g" "${DEVSTACK_GIT_TOP_DIR}/local.conf" 2>/dev/null; then
			PRNERR "Failed to modify local.conf for password"
			exit 1
		fi

		#
		# Set RECLONE to False
		#
		PRNINFO "Set RECLONE to False in local.conf"
		{
			echo ''
			echo '# Re-clone setting'
			echo '# -----'
			echo ''
			echo 'RECLONE=False'
			echo ''
		} >> "${DEVSTACK_GIT_TOP_DIR}/local.conf"

		#
		# Set Trove setting
		#
		# [NOTE]
		# TROVE_DATASTORE_VERSION=5.7 is a mysql tag that exists in the internal docker repository.
		# (There is no tag such as 5.7.x, so an error will occur if it is not set.)
		#
		PRNINFO "Add Trove configuration to ${DEVSTACK_GIT_TOP_DIR}/local.conf"
		{
			echo ''
			echo '# Trove plugins'
			echo '# -----'
			echo 'enable_plugin trove https://opendev.org/openstack/trove'
			echo 'enable_plugin trove-dashboard https://opendev.org/openstack/trove-dashboard'
			echo ''
			echo 'LIBS_FROM_GIT+=,python-troveclient'
			echo ''
			echo "TROVE_BRANCH=${DEVSTACK_BRANCH}"
			echo "TROVE_CLIENT_BRANCH=${DEVSTACK_BRANCH}"
			echo "TROVE_DASHBOARD_BRANCH=${DEVSTACK_BRANCH}"
			echo "TRIPLEO_IMAGES_BRANCH=${DEVSTACK_BRANCH}"
			echo "TROVE_ROOT_PASSWORD=${DEVSTACK_DEFAULT_PASSWORD}"
			echo "TROVE_DATASTORE_VERSION=5.7"
			echo 'SYNC_LOG_TO_CONTROLLER=True'
			echo ''
			echo '# Enable services, these services depend on neutron plugin.'
			echo '# -----'
			echo '# [NOTE]'
			echo '# The "enable_plugin neutron" below is not necessary.'
			echo '# For now, we will add this.'
			echo '#'
			echo '# This is modeled after the example code below.'
			echo '# https://opendev.org/openstack/neutron/src/branch/master/devstack/ovn-local.conf.sample'
			echo '#'
			echo 'Q_AGENT=ovn'
			echo 'Q_ML2_PLUGIN_MECHANISM_DRIVERS=ovn,logger'
			echo 'Q_ML2_PLUGIN_TYPE_DRIVERS=local,flat,vlan,geneve'
			echo 'Q_ML2_TENANT_NETWORK_TYPE="geneve"'
			echo ''
			echo 'enable_service ovn-northd'
			echo 'enable_service ovn-controller'
			echo 'enable_service q-ovn-metadata-agent'
			echo ''
			echo '# Use Neutron'
			echo 'enable_service q-svc'
			echo ''
			echo '# Disable Neutron agents not used with OVN.'
			echo 'disable_service q-agt'
			echo 'disable_service q-l3'
			echo 'disable_service q-dhcp'
			echo 'disable_service q-meta'
			echo ''
			echo '# Enable services, these services depend on neutron plugin.'
			echo 'enable_plugin neutron https://opendev.org/openstack/neutron'
			echo 'enable_service q-trunk'
			echo 'enable_service q-dns'
			echo 'enable_service q-port-forwarding'
			echo 'enable_service q-qos'
			echo 'enable_service neutron-segments'
			echo 'enable_service q-log'
			echo ''
			echo '# Enable neutron tempest plugin tests'
			echo 'enable_plugin neutron-tempest-plugin https://opendev.org/openstack/neutron-tempest-plugin'
			echo ''
			echo 'OVN_BUILD_MODULES=True'
			echo ''
			echo 'ENABLE_CHASSIS_AS_GW=True'
			echo ''
			echo '# For IP Address'
			echo '# -----'
			echo '# [NOTE]'
			echo '# If you want to use fixed IPv4, please set the following.'
			echo '#'
			echo 'IP_VERSION=4'
			echo ''
			echo '# [NOTE]'
			echo '# A safe IPv4 address range is specified.'
			echo '# (You can delete it if not required.)'
			echo '#'
			echo 'IPV4_ADDRS_SAFE_TO_USE="10.0.3.0/24"'
			echo ''
			echo '# Enable SWIFT and additional setting'
			echo '# -----'
			echo '# Enable SWIFT'
			echo 'ENABLED_SERVICES+=,swift'
			echo ''
			echo '# Swift default 5G'
			echo 'SWIFT_MAX_FILE_SIZE=5368709122'
			echo ''
			echo '# Swift disk size 10G'
			echo 'SWIFT_LOOPBACK_DISK_SIZE=10G'

			if [ "${BUILD_IMAGE}" = "no" ]; then
				echo ''
				echo 'TROVE_ENABLE_IMAGE_BUILD=false'
			fi
		} >> "${DEVSTACK_GIT_TOP_DIR}/local.conf"

		# [NOTE]
		# MySQL Trove requires Cinder.
		# DevStack has Cinder disabled by default.
		# Here, we will extract the keywords to enable the disabled settings.
		#
		PRNINFO "Add cinder setting in local.conf"

		#
		# Add 'cinder' enabled line.
		#
		if ! sed -i -e 's#\[\[local|localrc\]\]#\[\[local|localrc\]\]\nenable_service cinder c-sch c-api c-vol#g' "${DEVSTACK_GIT_TOP_DIR}/local.conf" 2>/dev/null; then
			PRNERR "Failed to modify local.conf for cinder enabled line."
			exit 1
		fi

		PRNINFO "Succeed to make local.conf with password from sample local.conf"
	else
		PRNINFO "Use existed devstack repository(${DEVSTACK_GIT_TOP_DIR}) and local.conf."
	fi

	#
	# [SETUP] Clone requirements repository
	#
	PRNMSG "[SETUP] Clone requirements repository"

	if [ ! -d "${REQUIREMENTS_GIT_TOP_DIR}" ]; then
		#
		# Clone requirements repository
		#
		if ! CloneRepositoryAndSetBranch "${REQUIREMENTS_GIT_NAME}" "${STACK_USER_HOME}" "${DEVSTACK_BRANCH}"; then
			exit 1
		fi
		PRNINFO "Succeed to clone requirements repository."
	else
		PRNINFO "Already requirements repository directory."
	fi

	#
	# [SETUP] Trove repository and Add files to Trove guest os image
	#
	PRNMSG "[SETUP] Trove repository and Add files to Trove guest os image"

	if [ ! -d "${TROVE_GIT_TOP_DIR}" ]; then
		#
		# Get K2HDKC docker image latest version
		#
		if ! GetLatestK2hdkcImageVersion; then
			exit 1
		fi

		#
		# Clone trove repository
		#
		if ! CloneRepositoryAndSetBranch "${TROVE_GIT_NAME}" "${STACK_USER_HOME}" "${DEVSTACK_BRANCH}"; then
			exit 1
		fi

		#
		# Setup patch directories and files
		#
		if ! ExtractPatchFiles "${TROVE_PATCH_TOP_DIR}" "${TROVE_GIT_TOP_DIR}"; then
			exit 1
		fi
		PRNINFO "Succeed to apply patch ${SRCTOPDIR}/${TROVE_PATCH_DIR_NAME} to ${STACK_USER_HOME}/${TROVE_PATCH_DIR_NAME}"
		echo ""

		#
		# Set Environment about interface for building image
		#
		# [NOTE]
		# Since we will not use the eth0/1 interface but rather ens3/4, we set
		# the DIB_NETWORK_INTERFACE_NAMES environment variable here.
		# By setting DIB_NETWORK_INTERFACE_NAMES, the /etc/network/interfaces.d/ensX
		# file will be automatically created when the image is created.
		#
		PRNINFO "Set DIB_NETWORK_INTERFACE_NAMES Environment"

		if [ -z "${DIB_NETWORK_INTERFACE_NAMES}" ]; then
			PRNINFO "Set and Export DIB_NETWORK_INTERFACE_NAMES Environment"
			export DIB_NETWORK_INTERFACE_NAMES="ens3 ens4"

		elif [ "${DIB_NETWORK_INTERFACE_NAMES}" = "ens3 ens4" ]; then
			PRNINFO "Already set DIB_NETWORK_INTERFACE_NAMES Environment"
			export DIB_NETWORK_INTERFACE_NAMES
		else
			PRNWARN "DIB_NETWORK_INTERFACE_NAMES Environment has ${DIB_NETWORK_INTERFACE_NAMES} value, but we set ens3 and ens4."
			export DIB_NETWORK_INTERFACE_NAMES="ens3 ens4"
		fi

		#
		# Modify 12-ssh-key-dev file
		#
		PRNINFO "Modify ${TROVE_GIT_TOP_DIR}/${GUEST_INSTALL_SSH_KEY_FILE} file"

		if [ ! -f "${TROVE_GIT_TOP_DIR}/${GUEST_INSTALL_SSH_KEY_FILE}" ]; then
			PRNERR "Not found ${TROVE_GIT_TOP_DIR}/${GUEST_INSTALL_SSH_KEY_FILE} file."
			exit 1
		fi
		{
			echo ''
			echo "if [[ \${DEV_MODE} == \"true\" && -e \"\${TMP_HOOKS_DIR}/id_rsa\" ]]; then"
			echo "    sudo -Hiu \${GUEST_USERNAME} dd of=\${GUEST_SSH_DIR}/authorized_keys if=\${TMP_HOOKS_DIR}/id_rsa.pub"
			echo "    sudo -Hiu \${GUEST_USERNAME} chmod 600 \${GUEST_SSH_DIR}/authorized_keys"
			echo 'fi'
		} >> "${TROVE_GIT_TOP_DIR}/${GUEST_INSTALL_SSH_KEY_FILE}"

		PRNINFO "Succeed to modify ${TROVE_GIT_TOP_DIR}/${GUEST_INSTALL_SSH_KEY_FILE} file"
		echo ""

		#
		# Create 13-resolv-conf file
		#
		# [NOTE]
		# If a local DNS is set for the HOST where devstack was started,
		# it will be reflected.
		#
		PRNINFO "Create ${TROVE_GIT_TOP_DIR}/${GUEST_INSTALL_RESOLV_CONF_FILE} file"

		if [ -f "${TROVE_GIT_TOP_DIR}/${GUEST_INSTALL_RESOLV_CONF_FILE}" ]; then
			rm -f "${TROVE_GIT_TOP_DIR}/${GUEST_INSTALL_RESOLV_CONF_FILE}"
		fi

		_LOCALHOST_DNS_RESOLV_IPS=$(grep '^[[:space:]]*nameserver' /etc/resolv.conf | awk '{print $2}' | sort | uniq | tr '\n' ' ' | sed -e 's#[[:space:]]*$##g')
		if [ -z "${_LOCALHOST_DNS_RESOLV_IPS}" ]; then
			PRNINFO "Not found any DNS resolv IP addresses in local /etc/resolv.conf, so skip this."
			echo ""
		else
			{
				echo '#!/bin/sh'
				echo ''
				echo "if [ -n \"\${DIB_DEBUG_TRACE}\" ] && [ \"\${DIB_DEBUG_TRACE}\" -gt 0 ]; then"
				echo '    set -x'
				echo 'fi'
				echo 'set -eu'
				echo 'set -o xtrace'
				echo ''
				echo 'echo "Modify /etc/systemd/resolved.conf for adding local DNS"'
				echo ''
				echo 'cat << EOF >> /etc/systemd/resolved.conf'
				echo 'DNSStubListener=no'
				echo "DNS=${_LOCALHOST_DNS_RESOLV_IPS}"
				echo 'EOF'
				echo ''
			} > "${TROVE_GIT_TOP_DIR}/${GUEST_INSTALL_RESOLV_CONF_FILE}"

			if ! chmod +x "${TROVE_GIT_TOP_DIR}/${GUEST_INSTALL_RESOLV_CONF_FILE}" 2>/dev/null; then
				PRNERR "Failed to change permission to ${TROVE_GIT_TOP_DIR}/${GUEST_INSTALL_RESOLV_CONF_FILE} file."
				exit 1
			fi

			PRNINFO "Succeed to create ${TROVE_GIT_TOP_DIR}/${GUEST_INSTALL_RESOLV_CONF_FILE} file"
			echo ""
		fi

		#
		# Create 14-apt-conf file
		#
		PRNINFO "Create ${TROVE_GIT_TOP_DIR}/${GUEST_INSTALL_APT_CONF_FILE} file"

		set_scheme_proxy_env

		if [ -n "${HTTP_PROXY}" ] || [ -n "${http_proxy}" ] || [ -n "${HTTPS_PROXY}" ] || [ -n "${https_proxy}" ]; then

			if [ -f "${TROVE_GIT_TOP_DIR}/${GUEST_INSTALL_APT_CONF_FILE}" ]; then
				rm -f "${TROVE_GIT_TOP_DIR}/${GUEST_INSTALL_APT_CONF_FILE}"
			fi
			{
				echo '#!/bin/sh'
				echo ''
				echo "if [ -n \"\${DIB_DEBUG_TRACE}\" ] && [ \"\${DIB_DEBUG_TRACE}\" -gt 0 ]; then"
				echo '    set -x'
				echo 'fi'
				echo 'set -eu'
				echo ''
				echo 'echo "Add apt configuration for PROXY"'
				echo ''
				echo 'cat << EOF > /etc/apt/apt.conf.d/00-aptproxy.conf'

				if [ -n "${HTTP_PROXY}" ]; then
					echo "Acquire::http::Proxy \"${HTTP_PROXY}\";"
				elif [ -n "${http_proxy}" ]; then
					echo "Acquire::http::Proxy \"${http_proxy}\";"
				fi
				if [ -n "${HTTPS_PROXY}" ]; then
					echo "Acquire::https::Proxy \"${HTTPS_PROXY}\";"
				elif [ -n "${https_proxy}" ]; then
					echo "Acquire::https::Proxy \"${https_proxy}\";"
				fi
				echo 'EOF'
			} > "${TROVE_GIT_TOP_DIR}/${GUEST_INSTALL_APT_CONF_FILE}"

			if ! chmod +x "${TROVE_GIT_TOP_DIR}/${GUEST_INSTALL_APT_CONF_FILE}" 2>/dev/null; then
				PRNERR "Failed to change permission to ${TROVE_GIT_TOP_DIR}/${GUEST_INSTALL_APT_CONF_FILE} file."
				exit 1
			fi
			PRNINFO "Succeed to create ${TROVE_GIT_TOP_DIR}/${GUEST_INSTALL_APT_CONF_FILE} file"
		else
			PRNINFO "${TROVE_GIT_TOP_DIR}/${GUEST_INSTALL_APT_CONF_FILE} will not be created, because this does not have any PROXY environment."
		fi
		echo ""
		revert_scheme_proxy_env

		#
		# Create 15-ipv6disable-conf
		#
		# [NOTE]
		# IPv6 is enabled in the GuestAgent(OS) image.
		# When using ALPINE-based containers in K2HDKC DBaaS, a timeout occurs in DNS
		# access if IPv6 is enabled.
		# To avoid this, we disable IPv6.(default)
		# Since the container specifies network=host, the sysctl (net.ipv6.conf.all.disable_ipv6=1)
		# at container startup does not work.
		# Therefore, you must disable IPv6 in the GuestAgent(OS).
		#
		PRNINFO "Create ${TROVE_GIT_TOP_DIR}/${GUEST_INSTALL_IPV6DISABLE_CONF_FILE} file"

		if [ -f "${TROVE_GIT_TOP_DIR}/${GUEST_INSTALL_IPV6DISABLE_CONF_FILE}" ]; then
			rm -f "${TROVE_GIT_TOP_DIR}/${GUEST_INSTALL_IPV6DISABLE_CONF_FILE}"
		fi
		if [ "${ENABLE_GUEST_IPV6}" -eq 0 ]; then
			{
				echo '#!/bin/sh'
				echo ''
				echo '#'
				echo '# Disable IPv6 to sysctl.conf'
				echo '#'
				echo 'echo "net.ipv6.conf.all.disable_ipv6=1" >> /etc/sysctl.conf'
				echo ''
				echo '#'
				echo '# Disable IPv6 to /etc/sysctl.d/60-ipv6-disable.conf'
				echo '#'
				echo '{'
				echo '	echo "net.ipv6.conf.all.disable_ipv6=1"'
				echo '	echo "net.ipv6.conf.default.disable_ipv6=1"'
				echo '	echo "net.ipv6.conf.lo.disable_ipv6=1"'
				echo '} >> /etc/sysctl.d/60-ipv6-disable.conf'
				echo ''
				echo '#'
				echo '# Disable IPv6 to /etc/rc.local'
				echo '#'
				echo '{'
				echo '	echo "#!/bin/sh"'
				echo '	echo ""'
				echo '	echo "systemctl restart procps"'
				echo '	echo ""'
				echo '	echo "exit 0"'
				echo '} > /etc/rc.local'
				echo 'chmod +x /etc/rc.local'
				echo ''
				echo 'exit 0'

			} > "${TROVE_GIT_TOP_DIR}/${GUEST_INSTALL_IPV6DISABLE_CONF_FILE}"

			if ! chmod +x "${TROVE_GIT_TOP_DIR}/${GUEST_INSTALL_IPV6DISABLE_CONF_FILE}" 2>/dev/null; then
				PRNERR "Failed to change permission to ${TROVE_GIT_TOP_DIR}/${GUEST_INSTALL_IPV6DISABLE_CONF_FILE} file."
				exit 1
			fi
			PRNINFO "Succeed to create ${TROVE_GIT_TOP_DIR}/${GUEST_INSTALL_IPV6DISABLE_CONF_FILE} file"
		else
			PRNINFO "${TROVE_GIT_TOP_DIR}/${GUEST_INSTALL_IPV6DISABLE_CONF_FILE} will not be created, so enable IPv6 on GuestAgent(OS)."
		fi
		echo ""

		#
		# Rename GuestOS image name
		#
		PRNINFO "Rename GuestOS image name from ubuntu-guest to ubuntu-jammy"

		cp -rp "${TROVE_GIT_TOP_DIR}/integration/scripts/files/elements/ubuntu-guest" "${TROVE_GIT_TOP_DIR}/integration/scripts/files/elements/ubuntu-jammy"

		#
		# Set K2HDKC versoin number
		#
		# [NOTE]
		# Here, replace the K2HDKC Version(K2HDKC_DOCKER_IMAGE_VERSION) written
		# in the trove/devstack/plugin.sh and trove/backup/install.sh files.
		#
		PRNINFO "Set K2HDKC versoin number(${K2HDKC_DOCKER_IMAGE_VERSION}) to plugin.sh and install.sh"

		if ! sed -i -e "s#TROVE_DATASTORE_VERSION_K2HDKC=.*#TROVE_DATASTORE_VERSION_K2HDKC=\"${K2HDKC_DOCKER_IMAGE_VERSION}\"#g" "${TROVE_GIT_TOP_DIR}/devstack/plugin.sh" >/dev/null 2>&1; then
			PRNERR "Failed to replace K2HDKC version(TROVE_DATASTORE_VERSION_K2HDKC variable) in trove/devstack/plugin.sh to ${K2HDKC_DOCKER_IMAGE_VERSION}."
			exit 1
		fi
		if ! sed -i -e "/^[[:space:]]*elif \[ \"\$1\" = \"k2hdkc\" \]; then/,/^[[:space:]]*else/ s#OPT_DATASTORE_VERSION=.*#OPT_DATASTORE_VERSION=\"${K2HDKC_DOCKER_IMAGE_VERSION}\"#g" "${TROVE_GIT_TOP_DIR}/backup/install.sh" >/dev/null 2>&1; then
			PRNERR "Failed to replace K2HDKC version(OPT_DATASTORE_VERSION variable) in trove/backup/install.sh to ${K2HDKC_DOCKER_IMAGE_VERSION}."
			exit 1
		fi

		#
		# Set(Change) K2HDKC Docker image path
		#
		# [NOTE]
		# Here, replace the K2HDKC Docker image path written in the trove/devstack/settings file.
		#
		if [ -n "${DOCKER_IMAGE_CONFIG}" ]; then
			echo ""
			PRNINFO "Set K2HDKC Docker image path in settings file"

			if [ -z "${PRELOAD_SETUP_PUSH_REGISTRY}" ] || [ -z "${PRELOAD_SETUP_PUSH_REPOSITORY}" ]; then
				PRNERR "Not found PRELOAD_SETUP_PUSH_REGISTRY and PRELOAD_SETUP_PUSH_REPOSITORY variables"
				exit 1
			fi

			#
			# Paths
			#
			_TMP_K2HDKC_TROVE_DOCKER_IMAGE_PATH="${PRELOAD_SETUP_PUSH_REGISTRY}${PRELOAD_SETUP_PUSH_REPOSITORY}/k2hdkc-trove:${CUR_REPO_VERSION}-${PRELOAD_DEFAULT_DOCKER_IMAGE_TYPE}"
			_TMP_K2HDKC_BACKUP_DOCKER_IMAGE_PATH="${PRELOAD_SETUP_PUSH_REGISTRY}${PRELOAD_SETUP_PUSH_REPOSITORY}/k2hdkc-trove-backup:${CUR_REPO_VERSION}-${PRELOAD_DEFAULT_DOCKER_IMAGE_TYPE}"

			#
			# Replace
			#
			if ! sed -i -e "/^[[:space:]]*#K2HDKC-START/,/^[[:space:]]*#K2HDKC-END/ s|^\([[:space:]]*TROVE_INSECURE_DOCKER_REGISTRIES=\).*$|\1\${TROVE_INSECURE_DOCKER_REGISTRIES:-\"${PRELOAD_SETUP_INSECURE_REGISTRIES}\"}|g" "${TROVE_GIT_TOP_DIR}/devstack/settings" >/dev/null 2>&1; then
				PRNERR "Failed to replace K2HDKC Trove Docker image path(TROVE_INSECURE_DOCKER_REGISTRIES=${PRELOAD_SETUP_INSECURE_REGISTRIES}) in trove/devstack/settings."
				exit 1
			fi
			if ! sed -i -e "/^[[:space:]]*#K2HDKC-START/,/^[[:space:]]*#K2HDKC-END/ s|^\([[:space:]]*TROVE_DATABASE_IMAGE_K2HDKC=\).*$|\1\${TROVE_DATABASE_IMAGE_K2HDKC:-\"${_TMP_K2HDKC_TROVE_DOCKER_IMAGE_PATH}\"}|g" "${TROVE_GIT_TOP_DIR}/devstack/settings" >/dev/null 2>&1; then
				PRNERR "Failed to replace K2HDKC Trove Docker image path(TROVE_DATABASE_IMAGE_K2HDKC=${_TMP_K2HDKC_TROVE_DOCKER_IMAGE_PATH}) in trove/devstack/settings."
				exit 1
			fi
			if ! sed -i -e "/^[[:space:]]*#K2HDKC-START/,/^[[:space:]]*#K2HDKC-END/ s|^\([[:space:]]*TROVE_DATABASE_BACKUP_IMAGE_K2HDKC=\).*$|\1\${TROVE_DATABASE_BACKUP_IMAGE_K2HDKC:-\"${_TMP_K2HDKC_BACKUP_DOCKER_IMAGE_PATH}\"}|g" "${TROVE_GIT_TOP_DIR}/devstack/settings" >/dev/null 2>&1; then
				PRNERR "Failed to replace K2HDKC Trove Backup Docker image path(TROVE_DATABASE_BACKUP_IMAGE_K2HDKC=${_TMP_K2HDKC_BACKUP_DOCKER_IMAGE_PATH}) in trove/devstack/settings."
				exit 1
			fi
		fi
		PRNINFO "Succeed to clone trove repository and setup."
	else
		PRNINFO "Already trove repository directory."
	fi

	#
	# [SETUP] Trove-Dashboard repository
	#
	PRNMSG "[SETUP] Trove-Dashboard repository"

	if [ ! -d "${TROVE_DASHBOARD_GIT_TOP_DIR}" ]; then
		#
		# Clone trove-dashboard repository
		#
		if ! CloneRepositoryAndSetBranch "${TROVE_DASHBOARD_GIT_NAME}" "${STACK_USER_HOME}" "${DEVSTACK_BRANCH}"; then
			exit 1
		fi

		#
		# Setup patch directories and files
		#
		if ! ExtractPatchFiles "${TROVE_DASHBOARD_PATCH_TOP_DIR}" "${TROVE_DASHBOARD_GIT_TOP_DIR}"; then
			exit 1
		fi
		PRNINFO "Succeed to apply patch ${SRCTOPDIR}/${TROVE_DASHBOARD_PATCH_DIR_NAME} to ${STACK_USER_HOME}/${TROVE_DASHBOARD_PATCH_DIR_NAME}"
	else
		PRNINFO "Already has Trove-Dashboard repository."
	fi

	#
	# [SETUP] Install k2hr3clinet python
	#
	PRNMSG "[SETUP] Install k2hr3clinet python"
	(
		if [ -n "${HTTPS_PROXY}" ] && ! echo "${HTTPS_PROXY}" | grep -q '^http.*://'; then
			HTTPS_PROXY="http://${HTTPS_PROXY}"
		fi
		if [ -n "${HTTP_PROXY}" ] && ! echo "${HTTP_PROXY}" | grep -q '^http.*://'; then
			HTTP_PROXY="http://${HTTP_PROXY}"
		fi
		if [ -n "${https_proxy}" ] && ! echo "${https_proxy}" | grep -q '^http.*://'; then
			https_proxy="http://${https_proxy}"
		fi
		if [ -n "${http_proxy}" ] && ! echo "${http_proxy}" | grep -q '^http.*://'; then
			http_proxy="http://${http_proxy}"
		fi

		if ({ pip install k2hr3client 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to install k2hr3client python"
			exit 1
		fi
		PRNINFO "Succeed to install k2hr3client python package."
	)

	#
	# [SETUP] Patch SCSS file in Horizon
	#
	# [NOTE]
	# In some cases, an error occurs when compressing Horizon SCSS files.
	# This occurs because "display:inline-block;" does not contain spaces,
	# so we will apply a patch here.
	#
	PRNMSG "[SETUP] Patch SCSS file in Horizon"

	if [ ! -d "${HORIZON_GIT_TOP_DIR}" ]; then
		#
		# Clone horizon repository
		#
		if ! CloneRepositoryAndSetBranch "${HORIZON_GIT_NAME}" "${STACK_USER_HOME}" "${DEVSTACK_BRANCH}"; then
			exit 1
		fi

		#
		# Patch to "display: inline-block" SCSS
		#
		{
			cd "${HORIZON_GIT_TOP_DIR}" || exit 1

			# shellcheck disable=SC2038
			if ! find . -name serial_console.scss 2>/dev/null | xargs sed -i -e 's|display:inline-block;|display: inline-block;|g'; then
				PRNERR "Failed to patch to \"display: inline-block\" in SCSS"
			else
				PRNINFO "Succeed to patch to \"display: inline-block\" in SCSS"
			fi
		}
		PRNINFO "Succeed to patch SCSS file in Horizon."
	else
		PRNINFO "Not found ${HORIZON_GIT_TOP_DIR} directory, so pass..."
	fi

	#
	# [SETUP] Clone Neutron repository before start devstack
	#
	PRNMSG "[SETUP] Clone Neutron repository before start devstack"

	if [ ! -d "${NEUTRON_GIT_TOP_DIR}" ]; then
		#
		# Clone neutron repository
		#
		if ! CloneRepositoryAndSetBranch "${NEUTRON_GIT_NAME}" "${STACK_USER_HOME}" "${DEVSTACK_BRANCH}"; then
			exit 1
		fi
		PRNINFO "Succeed to clone Neutron repository."
	else
		PRNINFO "Already neutron repository directory."
	fi

	#
	# [RUN] Devstack
	#
	PRNMSG "[RUN] Devstack"

	cd "${DEVSTACK_GIT_TOP_DIR}" || exit 1

	set_scheme_proxy_env
	if ({ printf '\n' | "./${DEVSTACK_START_SH}" 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
		PRNERR "Failed to run ${DEVSTACK_START_SH}"
		exit 1
	fi
	revert_scheme_proxy_env

	PRNINFO "Succeed to run ${DEVSTACK_START_SH}"

	#
	# [MODIFY] Set iptables for accessing outside network
	#
	PRNMSG "[MODIFY] Set iptables for accessing outside network"

	if /bin/sh -c "${SUDO_PREFIX_CMD} iptables -L INPUT" | grep -q -i REJECT; then
		#
		# Remove the REJECT filter on INPUT
		#
		PRNINFO "Remove the REJECT filter on INPUT"

		_REJECT_LINE_NUMBER=$(/bin/sh -c "${SUDO_PREFIX_CMD} iptables -L INPUT --line-number" | grep -i REJECT | awk '{print $1}')

		if ! /bin/sh -c "${SUDO_PREFIX_CMD} iptables -D INPUT ${_REJECT_LINE_NUMBER}"; then
			PRNWARN "Failed to remove the REJECT filter on INPUT, so remove it manually."
		else
			PRNINFO "Succeed to remove the REJECT filter on INPUT"
		fi
	else
		PRNINFO "Not found any REJECT filter on INPUT"
	fi

	if /bin/sh -c "${SUDO_PREFIX_CMD} iptables -L FORWARD" | grep -q -i REJECT; then
		#
		# Remove the REJECT filter on FORWARD
		#
		PRNINFO "Remove the REJECT filter on FORWARD"

		_REJECT_LINE_NUMBER=$(/bin/sh -c "${SUDO_PREFIX_CMD} iptables -L FORWARD --line-number" | grep -i REJECT | awk '{print $1}')

		if ! /bin/sh -c "${SUDO_PREFIX_CMD} iptables -D FORWARD ${_REJECT_LINE_NUMBER}"; then
			PRNWARN "Failed to remove the REJECT filter on FORWARD, so remove it manually."
		else
			PRNINFO "Succeed to remove the REJECT filter on FORWARD"
		fi
	else
		PRNINFO "Not found any REJECT filter on FORWARD"
	fi

	#
	# [RESTART] Change configuration and restart Trove processes(for trove)
	#
	PRNMSG "[RUN] Change configuration and restart Trove processes"

	cd "${DEVSTACK_GIT_TOP_DIR}" || exit 1

	#
	# Modify trove.conf
	#
	# [NOTE]
	# In devstack, add 22 to tcp_ports to allow SSH.
	#
	PRNINFO "Modify ${ETC_TROVE_CONF_FILE} configuration"
	if [ ! -f "${ETC_TROVE_CONF_FILE}" ]; then
		PRNERR "Not found ${ETC_TROVE_CONF_FILE} file."
		exit 1
	fi
	sed -i -e 's|^[[:space:]]*tcp_ports[[:space:]]*=[[:space:]]*|tcp_ports = 22,|g' "${ETC_TROVE_CONF_FILE}" 2>/dev/null

	PRNINFO "Succeed to modify ${ETC_TROVE_CONF_FILE} configuration"

	#
	# Modify trove-guestagent.conf
	#
	PRNINFO "Modify ${ETC_TROVE_GUEST_CONF_FILE} configuration"
	if [ ! -f "${ETC_TROVE_GUEST_CONF_FILE}" ]; then
		PRNERR "Not found ${ETC_TROVE_GUEST_CONF_FILE} file."
		exit 1
	fi
	PRNINFO "Succeed to modify ${ETC_TROVE_GUEST_CONF_FILE} configuration"

	#
	# Restart Trove services and processes
	#
	PRNINFO "Restart Trove services and processes"

	if ! sudo systemctl restart httpd; then
		PRNERR "Failed to restart httpd service."
		exit 1
	fi
	if ! sudo systemctl restart devstack@tr-*; then
		PRNERR "Failed to restart devstack@tr-* service."
		exit 1
	fi
	PRNINFO "Succeed to restart Trove services and processes"

	#
	# Get docker image information
	#
	if [ -f "${TROVE_GIT_TOP_DIR}/devstack/settings" ]; then
		# shellcheck disable=SC2016
		K2HDKC_DOCKER_IMAGE_TROVE=$(grep 'TROVE_DATABASE_IMAGE_K2HDKC' "${TROVE_GIT_TOP_DIR}/devstack/settings" | tail -1 | sed -e 's#^[[:space:]]*TROVE_DATABASE_IMAGE_K2HDKC=\${TROVE_DATABASE_IMAGE_K2HDKC:-"##g' -e 's#"}.*$##g')
		# shellcheck disable=SC2016
		K2HDKC_DOCKER_IMAGE_TROVE_BACKUP=$(grep 'TROVE_DATABASE_BACKUP_IMAGE_K2HDKC' "${TROVE_GIT_TOP_DIR}/devstack/settings" | tail -1 | sed -e 's#^[[:space:]]*TROVE_DATABASE_BACKUP_IMAGE_K2HDKC=\${TROVE_DATABASE_BACKUP_IMAGE_K2HDKC:-"##g' -e 's#"}.*$##g')
	else
		K2HDKC_DOCKER_IMAGE_TROVE="Unknown"
		K2HDKC_DOCKER_IMAGE_TROVE_BACKUP="Unknown"
	fi

	{
		PRNSUCCESS "Started ${DEVSTACK_NAME}"

		echo "    You can access the ${CGRN}DevStack${CDEF}(OpenStack) console from the URL:"
		echo "        ${CGRN}http://${MYHOSTNAME}/${CDEF}"
		echo "    Initial administrator users log in with ${CGRN}admin${CDEF} : ${CGRN}${DEVSTACK_DEFAULT_PASSWORD}${CDEF}."
		echo ""
		echo "    K2HDKC Trove docker image:        ${K2HDKC_DOCKER_IMAGE_TROVE}"
		echo "    K2HDKC Trove backup docker image: ${K2HDKC_DOCKER_IMAGE_TROVE_BACKUP}"
	} | tee -a "${K2HDKCSTACK_SUMMARY_LOG}"
	echo ""
fi

#==============================================================
# Start K2HR3 Cluster
#==============================================================
if [ -n "${LAUNCH_K2HR3}" ] && [ "${LAUNCH_K2HR3}" = "yes" ]; then

	PRNTITLE "Start to launch K2HR3 Cluster"

	cd "${SCRIPTDIR}" || exit 1

	if ! ./k2hr3setup.sh -c; then
		PRNERR "Failed to launch K2HR3 Cluster"
		exit 1
	fi
	PRNSUCCESS "Launched K2HR3 Cluster"
fi

#==============================================================
# All Processes are finished without error
#==============================================================
#
# Get duration time
#
_proc_time=$(GetDurationTime)

echo ""
echo "${CGRN}${CREV}[SUCCESS]${CDEF} ${CGRN}All processes are complete${CDEF} (Duration Time : ${_proc_time})"
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
