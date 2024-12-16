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
# CREATE:   Mon May 20 2024
# REVISION:
#

#==============================================================
# Common Variables
#==============================================================
export LANG=C

#
# Instead of pipefail(for shells not support "set -o pipefail")
#
#PIPEFAILURE_FILE="/tmp/.pipefailure.$(od -An -tu4 -N4 /dev/random | tr -d ' \n')"

SCRIPTNAME=$(basename "${0}")
SCRIPTDIR=$(dirname "${0}")
SCRIPTDIR=$(cd "${SCRIPTDIR}" || exit 1; pwd)

#
# Directory paths
#
ETC_ANTPICKAX_DIR='/etc/antpickax'
VAR_ANTPICKAX_DIR='/var/lib/antpickax'
DATA_ANTPICKAX_DIR="${VAR_ANTPICKAX_DIR}/k2hdkc"

#
# Parameter name(file name)
#
PARAM_NAME_CLUSTER_NAME='cluster-name'
PARAM_NAME_EXTDATA_URL='extdata-url'
PARAM_NAME_CHMPX_SERVER_PORT='chmpx-server-port'
PARAM_NAME_CHMPX_SERVER_CTLPORT='chmpx-server-ctlport'
PARAM_NAME_CHMPX_SLAVE_CTLPORT='chmpx-slave-ctlport'

#
# Registration script file from Exedata URL
#
EXTDATA_URL_USER_AGENT='extdata_k2hr3_trove'
REGISTER_K2HR3_SH_NAME='register_k2hr3.sh'
REGISTER_K2HR3_SH="${ETC_ANTPICKAX_DIR}/${REGISTER_K2HR3_SH_NAME}"

#
# K2HDKC Configuration symbols
#
K2HDKC_CONFIG_FILE="${ETC_ANTPICKAX_DIR}/k2hdkc.ini"
K2HDKC_CONFIG_KEY_K2HFILE='K2HFILE'
K2HDKC_CONFIG_KEY_K2HMASKBIT='K2HMASKBIT'
K2HDKC_CONFIG_KEY_K2HCMASKBIT='K2HCMASKBIT'
K2HDKC_CONFIG_KEY_K2HMAXELE='K2HMAXELE'
K2HDKC_CONFIG_KEY_K2HPAGESIZE='K2HPAGESIZE'
K2HDKC_CONFIG_KEY_K2HFULLMAP='K2HFULLMAP'

#
# Backup/Restore
#
DEFAULT_SNAPSHOT_NAME='trovebackup'
DEFAULT_TOP_DATA_DIR="${DATA_ANTPICKAX_DIR}"
SUFFIX_AR_FILENAME=".k2har"

UNIX_TIME=$(date +%s)
K2HLINETOOL_CMD_FILE="/tmp/.${SCRIPTNAME}-${UNIX_TIME}.cmd"

BACKUP_K2HDKC_CONFIG_FILE="${DATA_ANTPICKAX_DIR}/backup_k2hdkc.ini"

#
# Variables for waiting
#
RESOURCE_UPDATE_INTERVAL_SEC=30
FIRST_RESOURCE_UPDATE_INTERVAL_SEC=30
LAUNCH_INTERVAL_SEC=10

#
# For signal handler
#
CAUGHT_SIGNAL=0

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
#	CGRN=$(printf '\033[32m')
	CDEF=$(printf '\033[0m')
else
	# shellcheck disable=SC2034
	CBLD=""
	CREV=""
	CRED=""
	CYEL=""
#	CGRN=""
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
	echo "${CYEL}${CREV}[WARNING]${CDEF} $*"
}

PRNINFO()
{
	echo "${CREV}[INFO]${CDEF} $*"
}

#--------------------------------------------------------------
# Utility Functions
#--------------------------------------------------------------
#
# Check directories
#
CheckDirectories()
{
	#
	# /etc/antpickax
	#
	if [ ! -d "${ETC_ANTPICKAX_DIR}" ]; then
		PRNERR "${ETC_ANTPICKAX_DIR} directory does not exist."
		return 1
	fi
	if ! touch "${ETC_ANTPICKAX_DIR}/.test_premission_file" 2>/dev/null; then
		if ! /bin/sh -c "${SUDO_CMD} chmod 0777 ${ETC_ANTPICKAX_DIR} 2>/dev/null"; then
			PRNERR "Could not set permission to ${ETC_ANTPICKAX_DIR} directory."
			return 1
		fi
	else
		rm -f "${ETC_ANTPICKAX_DIR}/.test_premission_file"
	fi

	#
	# /var/lib/antpickax
	#
	if [ ! -d "${VAR_ANTPICKAX_DIR}" ]; then
		PRNERR "${VAR_ANTPICKAX_DIR} directory does not exist."
		return 1
	fi

	#
	# /var/lib/antpickax/k2hdkc
	#
	if [ ! -d "${DATA_ANTPICKAX_DIR}" ]; then
		PRNWARN "${DATA_ANTPICKAX_DIR} does not exist, so try to create it."

		#
		# Check parent directory's permission
		#
		if ! touch "${VAR_ANTPICKAX_DIR}/.test_premission_file" 2>/dev/null; then
			if ! /bin/sh -c "${SUDO_CMD} chmod 0777 ${VAR_ANTPICKAX_DIR} 2>/dev/null"; then
				PRNERR "Could not set permission to ${VAR_ANTPICKAX_DIR} directory."
				return 1
			fi
		else
			rm -f "${VAR_ANTPICKAX_DIR}/.test_premission_file"
		fi

		#
		# Create directory
		#
		if ! /bin/sh -c "${SUDO_CMD} mkdir -p ${DATA_ANTPICKAX_DIR} 2>/dev/null"; then
			PRNERR "Could not create ${DATA_ANTPICKAX_DIR} directory."
			return 1
		fi
		if ! /bin/sh -c "${SUDO_CMD} chmod 0777 ${DATA_ANTPICKAX_DIR} 2>/dev/null"; then
			PRNERR "Could not set permission to ${DATA_ANTPICKAX_DIR} directory."
			return 1
		fi
	else
		#
		# Check permission
		#
		if ! touch "${DATA_ANTPICKAX_DIR}/.test_premission_file" 2>/dev/null; then
			if ! /bin/sh -c "${SUDO_CMD} chmod 0777 ${DATA_ANTPICKAX_DIR} 2>/dev/null"; then
				PRNERR "Could not set permission to ${DATA_ANTPICKAX_DIR} directory."
				return 1
			fi
		else
			rm -f "${DATA_ANTPICKAX_DIR}/.test_premission_file"
		fi
	fi

	return 0
}

#
# Load and Reset PROXY Environments
#
# [NOTE]
# Reset the PROXY environment variable.
# Environment variables are searched in the order of uppercase and lowercase letters.
#
ResetProxyEnv()
{
	#
	# Load current environments
	#
	_HTTP_PROXY_VALUE=$(env | grep "^[[:space:]]*HTTP_PROXY[[:space:]]*=[[:space:]]*" | sed -e "s|[[:space:]]*HTTP_PROXY[[:space:]]*=[[:space:]]*||g" | tr -d '\n')
	if [ -z "${_HTTP_PROXY_VALUE}" ]; then
		_HTTP_PROXY_VALUE=$(env | grep "^[[:space:]]*http_proxy[[:space:]]*=[[:space:]]*" | sed -e "s|[[:space:]]*http_proxy[[:space:]]*=[[:space:]]*||g" | tr -d '\n')
	fi

	_HTTPS_PROXY_VALUE=$(env | grep "^[[:space:]]*HTTPS_PROXY[[:space:]]*=[[:space:]]*" | sed -e "s|[[:space:]]*HTTPS_PROXY[[:space:]]*=[[:space:]]*||g" | tr -d '\n')
	if [ -z "${_HTTPS_PROXY_VALUE}" ]; then
		_HTTPS_PROXY_VALUE=$(env | grep "^[[:space:]]*https_proxy[[:space:]]*=[[:space:]]*" | sed -e "s|[[:space:]]*https_proxy[[:space:]]*=[[:space:]]*||g" | tr -d '\n')
	fi

	_NO_PROXY_VALUE=$(env | grep "^[[:space:]]*NO_PROXY[[:space:]]*=[[:space:]]*" | sed -e "s|[[:space:]]*NO_PROXY[[:space:]]*=[[:space:]]*||g" | tr -d '\n')
	if [ -z "${_NO_PROXY_VALUE}" ]; then
		_NO_PROXY_VALUE=$(env | grep "^[[:space:]]*no_proxy[[:space:]]*=[[:space:]]*" | sed -e "s|[[:space:]]*no_proxy[[:space:]]*=[[:space:]]*||g" | tr -d '\n')
	fi

	#
	# Reset environments
	#
	if [ -n "${_HTTP_PROXY_VALUE}" ]; then
		if ! echo "${_HTTP_PROXY_VALUE}" | grep -q -i -e "^false$" -e "^no$" -e "^empty$" -e "^n/a$" -e "^0$" -e "^none$"; then
			HTTP_PROXY="${_HTTP_PROXY_VALUE}"
			http_proxy="${_HTTP_PROXY_VALUE}"
			export HTTP_PROXY
			export http_proxy
		else
			unset HTTP_PROXY
			unset http_proxy
		fi
	else
		unset HTTP_PROXY
		unset http_proxy
	fi

	if [ -n "${_HTTPS_PROXY_VALUE}" ]; then
		if ! echo "${_HTTPS_PROXY_VALUE}" | grep -q -i -e "^false$" -e "^no$" -e "^empty$" -e "^n/a$" -e "^0$" -e "^none$"; then
			HTTPS_PROXY="${_HTTPS_PROXY_VALUE}"
			https_proxy="${_HTTPS_PROXY_VALUE}"
			export HTTPS_PROXY
			export https_proxy
		else
			unset HTTPS_PROXY
			unset https_proxy
		fi
	else
		unset HTTPS_PROXY
		unset https_proxy
	fi

	if [ -n "${_NO_PROXY_VALUE}" ]; then
		if ! echo "${_NO_PROXY_VALUE}" | grep -q -i -e "^false$" -e "^no$" -e "^empty$" -e "^n/a$" -e "^0$" -e "^none$"; then
			NO_PROXY="${_NO_PROXY_VALUE}"
			no_proxy="${_NO_PROXY_VALUE}"
			export NO_PROXY
			export no_proxy
		else
			unset NO_PROXY
			unset no_proxy
		fi
	else
		unset NO_PROXY
		unset no_proxy
	fi

	return 0
}

#
# Read and Check One Environment, and Create a file
#
# Input:	$1	Environment and File name
#
ReadOneEnvAndCreateFile()
{
	#
	# Environment/File name
	#
	if [ -z "$1" ]; then
		PRNERR "Internal error: Environment name is empty."
		return 1
	fi
	_ENV_NAME="$1"
	_ENV_NAME_UB=$(echo "${_ENV_NAME}" | sed -e 's|-|_|g')

	#
	# Get environment value
	#
	_ENV_VALUE=$(env | grep "^[[:space:]]*${_ENV_NAME_UB}[[:space:]]*=[[:space:]]*" | sed -e "s|[[:space:]]*${_ENV_NAME_UB}[[:space:]]*=[[:space:]]*||g" | tr -d '\n')
	if [ -z "${_ENV_VALUE}" ]; then
		PRNERR "Could not find ${_ENV_NAME}(${_ENV_NAME_UB}) environment."
		return 1
	fi

	#
	# Create environment value to file
	#
	if ! (printf "%s" "${_ENV_VALUE}" > "${ETC_ANTPICKAX_DIR}/${_ENV_NAME}") 2>/dev/null; then
		PRNERR "Could not create ${ETC_ANTPICKAX_DIR}/${_ENV_NAME} file and write ${_ENV_NAME} environment value(${_ENV_VALUE})."
		return 1
	fi
	return 0
}

#
# Read and Check Environments, and Create files
#
ReadEnvAndCreateFile()
{
	if ! ReadOneEnvAndCreateFile "${PARAM_NAME_CLUSTER_NAME}"			|| \
	   ! ReadOneEnvAndCreateFile "${PARAM_NAME_EXTDATA_URL}"			|| \
	   ! ReadOneEnvAndCreateFile "${PARAM_NAME_CHMPX_SERVER_PORT}"		|| \
	   ! ReadOneEnvAndCreateFile "${PARAM_NAME_CHMPX_SERVER_CTLPORT}"	|| \
	   ! ReadOneEnvAndCreateFile "${PARAM_NAME_CHMPX_SLAVE_CTLPORT}"	; then

		return 1
	fi
	return 0
}

#
# Setup sudo command prefix(SUDO_CMD)
#
SetupSudoPrefix()
{
	_CURRENT_USER_NAME=$(id -u -n)
	_CURRENT_USER_ID=$(id -u)

	if [ -n "${_CURRENT_USER_NAME}" ] && [ "${_CURRENT_USER_NAME}" = "root" ]; then
		SUDO_CMD=""
	elif [ -n "${_CURRENT_USER_ID}" ] && [ "${_CURRENT_USER_ID}" -eq 0 ]; then
		SUDO_CMD=""
	else
		SUDO_CMD="sudo"
	fi
	return 0
}

#
# Wait Svrnodes to avoid conflicts when starting at the same time
#
# [NOTE]
# This function parses the INI file and waits for the SVRNODE to start
# up under the following conditions:
#
#	- The first SVRNODE in the INI file is the MASTER SVRNODE.
#	- The entry for self SVRNODE is determined by SELFCUK.
#	- If self SVRNODE is the MASTER SVRNODE, it will not wait at all.
#	- If it is not the MASTER SVRNODE, it will first wait for the
#	  MASTER NODE to start up.
#	  Then it will wait for the SVRNODEs before self SVRNODE entry to
#	  start up.
#	- After all startup, this function will wait 1 over seconds before
#	  returning.
#
# SVRNODE startup is confirmed by access to the control port(5 second
# timeout).
#
WaitSvrnodes()
{
	#
	# Check INI file
	#
	if [ ! -f "${K2HDKC_CONFIG_FILE}" ]; then
		PRNWARN "${K2HDKC_CONFIG_FILE} file does not exist yet."
		return 1
	fi

	#------------------------------------------------------
	# Parse INI file
	#------------------------------------------------------
	#
	# Initialize self CUK and SVRNODE list
	#
	_SELFCUK_VAL=""
	_ALL_SVRNODE=""

	#
	# Loop for parsing INI file
	#
	_IN_SEC_GLOBAL=0
	_IN_SEC_SVRNODE=0
	_TMP_SVRNODE_CUK=""
	_TMP_SVRNODE_NAME=""
	_TMP_SVRNODE_CTLPORT=0

	while IFS= read -r _INI_ONE_LINE; do
		#
		# Cut comments and spaces
		#
		_INI_ONE_LINE=$(echo "${_INI_ONE_LINE}" | sed -e 's|[[:space:]]*#.*$||g' -e 's#[[:space:]]*=[[:space:]]*#=#g' -e 's#[[:space:]]*\[[[:space:]]*#\[#g' -e 's#[[:space:]]*\][[:space:]]*#\]#g' -e 's#^[[:space:]]*##g' -e 's#[[:space:]]*$##g')
		if [ -z "${_INI_ONE_LINE}" ]; then
			continue
		fi

		if echo "${_INI_ONE_LINE}" | grep -q -i '^\[GLOBAL\]$'; then
			#
			# Found [GLOBAL] Area(Start)
			#
			if [ "${_IN_SEC_GLOBAL}" -ne 0 ]; then
				#
				# [GLOBAL] to [GLOBAL]	=> Nothing to do
				#
				:

			elif [ "${_IN_SEC_SVRNODE}" -ne 0 ]; then
				#
				# [SVRNODE] to [GLOBAL]
				#
				if [ -n "${_TMP_SVRNODE_CUK}" ] && [ -n "${_TMP_SVRNODE_NAME}" ] && [ -n "${_TMP_SVRNODE_CTLPORT}" ]; then
					#
					# Add SVRNODE( <cuk>:<name>:<ctlport> ) to ALL list
					#
					_ALL_SVRNODE="${_ALL_SVRNODE} ${_TMP_SVRNODE_CUK}:${_TMP_SVRNODE_NAME}:${_TMP_SVRNODE_CTLPORT}"
				else
					#
					# Incomplete SVRNODE
					#
					PRNERR "The SVRNODE information is incomplete and will be ignored, skip this SVRNODE(${_TMP_SVRNODE_CUK}:${_TMP_SVRNODE_NAME}:${_TMP_SVRNODE_CTLPORT})"
				fi

			else
				#
				# Not target area to [GLOBAL]
				#
				:
			fi
			_TMP_SVRNODE_CUK=""
			_TMP_SVRNODE_NAME=""
			_TMP_SVRNODE_CTLPORT=0

			_IN_SEC_GLOBAL=1
			_IN_SEC_SVRNODE=0

		elif echo "${_INI_ONE_LINE}" | grep -q -i '^\[SVRNODE\]$'; then
			#
			# Found [SVRNODE] Area(Start)
			#
			if [ "${_IN_SEC_GLOBAL}" -ne 0 ]; then
				#
				# [GLOBAL] to [SVRNODE]
				#
				:

			elif [ "${_IN_SEC_SVRNODE}" -ne 0 ]; then
				#
				# [SVRNODE] to [SVRNODE]
				#
				if [ -n "${_TMP_SVRNODE_CUK}" ] && [ -n "${_TMP_SVRNODE_NAME}" ] && [ -n "${_TMP_SVRNODE_CTLPORT}" ]; then
					#
					# Add SVRNODE( <cuk>:<name>:<ctlport> ) to ALL list
					#
					_ALL_SVRNODE="${_ALL_SVRNODE} ${_TMP_SVRNODE_CUK}:${_TMP_SVRNODE_NAME}:${_TMP_SVRNODE_CTLPORT}"
				else
					#
					# Incomplete SVRNODE
					#
					PRNERR "The SVRNODE information is incomplete and will be ignored, skip this SVRNODE(${_TMP_SVRNODE_CUK}:${_TMP_SVRNODE_NAME}:${_TMP_SVRNODE_CTLPORT})"
				fi

			else
				#
				# Not target area to [SVRNODE]
				#
				:
			fi
			_TMP_SVRNODE_CUK=""
			_TMP_SVRNODE_NAME=""
			_TMP_SVRNODE_CTLPORT=0

			_IN_SEC_GLOBAL=0
			_IN_SEC_SVRNODE=1

		elif echo "${_INI_ONE_LINE}" | grep -q -i '^\[.*\]$'; then
			#
			# Found new Area other than [GLOBAL] and [SVRNODE]
			#
			if [ "${_IN_SEC_GLOBAL}" -ne 0 ]; then
				#
				# [GLOBAL] to Not target area
				#
				_IN_SEC_GLOBAL=0

			elif [ "${_IN_SEC_SVRNODE}" -ne 0 ]; then
				#
				# [SVRNODE] to Not target area
				#
				if [ -n "${_TMP_SVRNODE_CUK}" ] && [ -n "${_TMP_SVRNODE_NAME}" ] && [ -n "${_TMP_SVRNODE_CTLPORT}" ]; then
					#
					# Add SVRNODE( <cuk>:<name>:<ctlport> ) to ALL list
					#
					_ALL_SVRNODE="${_ALL_SVRNODE} ${_TMP_SVRNODE_CUK}:${_TMP_SVRNODE_NAME}:${_TMP_SVRNODE_CTLPORT}"
				else
					#
					# Incomplete SVRNODE
					#
					PRNERR "The SVRNODE information is incomplete and will be ignored, skip this SVRNODE(${_TMP_SVRNODE_CUK}:${_TMP_SVRNODE_NAME}:${_TMP_SVRNODE_CTLPORT})"
				fi
				_IN_SEC_SVRNODE=0

			else
				#
				# Not target area to Not target area
				#
				:
			fi
			_TMP_SVRNODE_CUK=""
			_TMP_SVRNODE_NAME=""
			_TMP_SVRNODE_CTLPORT=0

			_IN_SEC_GLOBAL=0
			_IN_SEC_SVRNODE=0

		else
			#
			# In contents area
			#
			if [ "${_IN_SEC_GLOBAL}" -ne 0 ]; then
				#
				# Check SELFCUK value in [GLOBAL] Area
				#
				if echo "${_INI_ONE_LINE}" | grep -q -i '^SELFCUK='; then
					_SELFCUK_VAL=$(echo "${_INI_ONE_LINE}" | sed -e 's#SELFCUK=##g' | tr -d '\n')
				fi

			elif [ "${_IN_SEC_SVRNODE}" -ne 0 ]; then
				#
				# Check values in [SVRNODE] Area
				#
				if echo "${_INI_ONE_LINE}" | grep -q -i '^CUK='; then
					_TMP_SVRNODE_CUK=$(echo "${_INI_ONE_LINE}" | sed -e 's#CUK=##g' | tr -d '\n')
				elif echo "${_INI_ONE_LINE}" | grep -q -i '^NAME='; then
					_TMP_SVRNODE_NAME=$(echo "${_INI_ONE_LINE}" | sed -e 's#NAME=##g' | tr -d '\n')
				elif echo "${_INI_ONE_LINE}" | grep -q -i '^CTLPORT='; then
					_TMP_SVRNODE_CTLPORT=$(echo "${_INI_ONE_LINE}" | sed -e 's#CTLPORT=##g' | tr -d '\n')
				fi

			else
				#
				# Not target area to [GLOBAL]
				#
				:
			fi
		fi
	done < "${K2HDKC_CONFIG_FILE}"

	#
	# Processes parsing the SVRNODE area if it is not complete.
	#
	if [ "${_IN_SEC_SVRNODE}" -ne 0 ]; then
		if [ -n "${_TMP_SVRNODE_CUK}" ] && [ -n "${_TMP_SVRNODE_NAME}" ] && [ -n "${_TMP_SVRNODE_CTLPORT}" ]; then
			#
			# Add SVRNODE( <cuk>:<name>:<ctlport> ) to ALL list
			#
			_ALL_SVRNODE="${_ALL_SVRNODE} ${_TMP_SVRNODE_CUK}:${_TMP_SVRNODE_NAME}:${_TMP_SVRNODE_CTLPORT}"
		else
			#
			# Incomplete SVRNODE
			#
			PRNERR "The SVRNODE information is incomplete and will be ignored, skip this SVRNODE(${_TMP_SVRNODE_CUK}:${_TMP_SVRNODE_NAME}:${_TMP_SVRNODE_CTLPORT})"
		fi
	fi

	#
	# Check values
	#
	_SELFCUK_VAL=$(echo "${_SELFCUK_VAL}" | sed -e 's#^[[:space:]]*##g' -e 's#[[:space:]]*$##g')
	_ALL_SVRNODE=$(echo "${_ALL_SVRNODE}" | sed -e 's#^[[:space:]]*##g' -e 's#[[:space:]]*$##g')

	if [ -z "${_SELFCUK_VAL}" ] || [ -z "${_ALL_SVRNODE}" ]; then
		PRNWARN "SELFCUK(${_SELFCUK_VAL}) or SVRNODE(${_ALL_SVRNODE}) is empty."
		return 1
	fi

	PRNINFO "Succeed to parse ${K2HDKC_CONFIG_FILE}: SELFCUK(${_SELFCUK_VAL}), ALL SVRNODEs(${_ALL_SVRNODE})"

	#------------------------------------------------------
	# Check master SVRNODE and create waiting SVRNODE list
	#------------------------------------------------------
	_IS_MASTER_SVRNODE=0
	_WAIT_MASTER_SVRNODE=""
	_WAIT_OTHER_SVRNODES=""

	_SVRNODE_NUMBER=0
	for _ONE_SVRNODE in ${_ALL_SVRNODE}; do
		#
		# Parse NAME and CTLPORT
		#
		_TMP_NAME_CTLPORT_PAIR=$(echo "${_ONE_SVRNODE}" | awk -F ':' '{print $2":"$3}' | tr -d '\n')

		#
		# The first SVRNODE is Master
		#
		if [ "${_SVRNODE_NUMBER}" -eq 0 ]; then
			_WAIT_MASTER_SVRNODE="${_TMP_NAME_CTLPORT_PAIR}"
		fi

		#
		# Check Self CUK
		#
		if echo "${_ONE_SVRNODE}" | grep -q -i "${_SELFCUK_VAL}"; then
			if [ "${_SVRNODE_NUMBER}" -eq 0 ]; then
				#
				# This is the Master SVRNODE
				#
				_IS_MASTER_SVRNODE=1
			else
				_IS_MASTER_SVRNODE=0
			fi
			break
		fi

		#
		# Not found self SVRNODE
		#
		if [ "${_SVRNODE_NUMBER}" -ne 0 ]; then
			_WAIT_OTHER_SVRNODES="${_WAIT_OTHER_SVRNODES} ${_TMP_NAME_CTLPORT_PAIR}"
		fi

		_SVRNODE_NUMBER=$((_SVRNODE_NUMBER + 1))
	done
	_WAIT_OTHER_SVRNODES=$(echo "${_WAIT_OTHER_SVRNODES}" | sed -e 's#^[[:space:]]*##g' -e 's#[[:space:]]*$##g')

	PRNINFO "This node is master(1)/not master(0) => ${_IS_MASTER_SVRNODE}"
	PRNINFO "Master SVRNODE                       => ${_WAIT_MASTER_SVRNODE}"
	PRNINFO "Need to wait other SVRNODE up        => ${_WAIT_OTHER_SVRNODES}"

	#------------------------------------------------------
	# Wait SVRNODEs
	#------------------------------------------------------
	if [ "${_IS_MASTER_SVRNODE}" -ne 1 ]; then
		#
		# Create command file for control port
		#
		_CTL_COMMAND_FILE="/tmp/.$$.cmd"
		echo "SELFSTATUS" > "${_CTL_COMMAND_FILE}"

		#
		# Wait for Master SVRNODE up.
		#
		PRNINFO "Wait Master SVRNODE(${_WAIT_MASTER_SVRNODE})"
		_IS_LOOP=1
		while [ "${_IS_LOOP}" -eq 1 ]; do
			#
			# Check every XX seconds(1 second timeout)
			#
			if curl -m 1 "telnet://${_WAIT_MASTER_SVRNODE}" < "${_CTL_COMMAND_FILE}" 2>&1 | grep -q -i '\[SERVICE IN\]\[UP\]\[n/a\]\[Nothing\]\[NoSuspend\]'; then
				PRNINFO "Master SVRNODE(${_WAIT_MASTER_SVRNODE}) is up."
				_IS_LOOP=0
			else
				sleep 5
			fi
		done

		#
		# Wait other SVRNODEs
		#
		for _ONE_WAIT_OTHER_SVRNODE in ${_WAIT_OTHER_SVRNODES}; do
			PRNINFO "Wait Other SVRNODE(${_ONE_WAIT_OTHER_SVRNODE})"
			_IS_LOOP=1
			while [ "${_IS_LOOP}" -eq 1 ]; do
				#
				# Check every XX seconds(1 second timeout)
				#
				if curl -m 1 "telnet://${_ONE_WAIT_OTHER_SVRNODE}" < "${_CTL_COMMAND_FILE}" 2>&1 | grep -q -i '\[SERVICE IN\]\[UP\]\[n/a\]\[Nothing\]\[NoSuspend\]'; then
					PRNINFO "Other SVRNODE(${_ONE_WAIT_OTHER_SVRNODE}) is up."
					_IS_LOOP=0
				else
					sleep 5
				fi
			done
		done

		rm -f "${_CTL_COMMAND_FILE}"
	fi

	return 0
}

#--------------------------------------------------------------
# Utility Functions : Registration
#--------------------------------------------------------------
#
# Load registration script from extdata url
#
# Input:	$1	FilePath for Exedata URL
#
# [NOTE]
# If you try to access the extdata url at the same time as starting the VM,
# the request may be blocked unintentionally.
# In that case, the curl timeout option may not be effective.
# To avoid this, send the request in a child process, and when the timeout
# occurs, stop the request and retry.
#
LoadRegistrationScript()
{
	if [ -z "$1" ] || [ ! -f "$1" ]; then
		PRNERR "Internal error: Extdata URL file path is empty or does not exist."
		return 1
	fi

	#
	# Load extdata url
	#
	if ! _EXTDATA_URL=$(tr -d '\n' < "$1"); then
		PRNERR "Could not read $1 file content."
		return 1
	fi
	TMP_CHECK_RESULT=$(echo "${_EXTDATA_URL}" | grep -q -i -e "^false$" -e "^no$" -e "^empty$" -e "^n/a$" -e "^0$" -e "^none$")
	if [ -n "${TMP_CHECK_RESULT}" ]; then
		PRNERR "Extdata URL(${_EXTDATA_URL}) is not set or wrong."
		return 1
	fi

	#
	# Create background script for request
	#
	_SUB_SCRIPT_SH="/tmp/sub_${SCRIPTNAME}"
	_SUB_SCRIPT_RESULT_FILE="/tmp/sub_${SCRIPTNAME}.result"
	{
		echo '#!/bin/sh'
		echo "rm -f ${REGISTER_K2HR3_SH} ${_SUB_SCRIPT_RESULT_FILE}"
		# shellcheck disable=SC2028
		echo "if ! REQ_RESULT=\$(curl -s -S -m 10 -X GET -H 'User-Agent: ${EXTDATA_URL_USER_AGENT}' -w '%{http_code}\\n' -o ${REGISTER_K2HR3_SH} ${_EXTDATA_URL} 2>/dev/null); then"
		echo "	rm -f ${REGISTER_K2HR3_SH}"
		echo 'fi'
		echo "echo \"\${REQ_RESULT}\" > ${_SUB_SCRIPT_RESULT_FILE}"
		echo 'exit 0'
	} > "${_SUB_SCRIPT_SH}"

	if ! chmod +x "${_SUB_SCRIPT_SH}"; then
		PRNERR "Failed to set permission to ${_SUB_SCRIPT_SH}"
		return 1
	fi

	#
	# Download extdata as script
	#
	_REQUEST_ERROR=0
	while [ "${_REQUEST_ERROR}" -eq 0 ]; do
		if [ -f "${REGISTER_K2HR3_SH}" ]; then
			rm -f "${REGISTER_K2HR3_SH}"
		fi

		#
		# Send the request as background process
		#
		"${_SUB_SCRIPT_SH}" >/dev/null 2>&1 &
		_SUB_SCRIPT_PID=$!

		#
		# Wait up to 10 seconds
		#
		_EXTDATA_RESULT=0
		_CHECK_COUNT=0
		while [ "${_CHECK_COUNT}" -lt 10 ]; do
			#
			# Check the result every second.
			#
			sleep 1

			if [ -f "${_SUB_SCRIPT_RESULT_FILE}" ]; then
				#
				# The request completed, so read result code.
				#
				_EXTDATA_RESULT=$(cat "${_SUB_SCRIPT_RESULT_FILE}")
				break
			else
				#
				# The request is not yet complete, so wait more 1 second
				#
				_CHECK_COUNT=$((_CHECK_COUNT + 1))
			fi
		done

		#
		# Post-processing the background script
		#
		_SUB_SCRIPT_CPIDS=$(pgrep -P "${_SUB_SCRIPT_PID}" 2>/dev/null)
		/bin/sh -c "${SUDO_CMD} kill -KILL ${_SUB_SCRIPT_PID} ${_SUB_SCRIPT_CPIDS} >/dev/null 2>&1"
		rm -f "${_SUB_SCRIPT_RESULT_FILE}"

		#
		# Check result
		#
		if [ -n "${_EXTDATA_RESULT}" ]; then
			if [ "${_EXTDATA_RESULT}" -eq 200 ]; then
				if [ -s "${REGISTER_K2HR3_SH}" ]; then
					#
					# SUCCEED: The request was completed successfully
					#
					break
				else
					#
					# ERROR: There is no download file or the file size is zero.
					#
					PRNERR "Could not create script file(or empty) from ${_EXTDATA_URL}."
					_REQUEST_ERROR=1
				fi
			elif [ "${_EXTDATA_RESULT}" -eq 0 ]; then
				#
				# RETRY: The request timed out
				#
				PRNWARN "Could not get script file by timeout, so retry to connect and send request."
			else
				#
				# ERROR: An error other than a timeout occurred
				#
				PRNERR "Could not get script file from ${_EXTDATA_URL} by ${_EXTDATA_RESULT} status error."
				_REQUEST_ERROR=1
			fi
		else
			#
			# ERROR: Something error occurred
			#
			PRNWARN "Why the result of request is not set, but continue as timeout..."
			_REQUEST_ERROR=1
		fi
	done
	rm -f "${_SUB_SCRIPT_SH}"

	if [ "${_REQUEST_ERROR}" -eq 1 ]; then
		return 1
	fi

	#
	# Check script file
	#
	if ! head -1 "${REGISTER_K2HR3_SH}" | grep -q '^#![[:space:]]*/'; then
		PRNERR "Downloaded file from ${_EXTDATA_URL} is not script file."
		rm -f "${REGISTER_K2HR3_SH}"
		return 1
	fi

	#
	# Set permission
	#
	if ! chmod +x "${REGISTER_K2HR3_SH}" 2>/dev/null; then
		PRNERR "Could not set permission to ${REGISTER_K2HR3_SH} for executing."
		rm -f "${REGISTER_K2HR3_SH}"
		return 1
	fi

	return 0;
}

#
# Register Node to K2HR3
#
RegisterNode()
{
	if [ ! -f "${ETC_ANTPICKAX_DIR}/${PARAM_NAME_CLUSTER_NAME}" ]			|| \
	   [ ! -f "${ETC_ANTPICKAX_DIR}/${PARAM_NAME_EXTDATA_URL}" ]			|| \
	   [ ! -f "${ETC_ANTPICKAX_DIR}/${PARAM_NAME_CHMPX_SERVER_PORT}" ]		|| \
	   [ ! -f "${ETC_ANTPICKAX_DIR}/${PARAM_NAME_CHMPX_SERVER_CTLPORT}" ]	|| \
	   [ ! -f "${ETC_ANTPICKAX_DIR}/${PARAM_NAME_CHMPX_SLAVE_CTLPORT}" ]	; then

		PRNERR "Not found some Configuration files in ${ETC_ANTPICKAX_DIR}."
		return 1
	fi

	#
	# Load registration script
	#
	if ! LoadRegistrationScript "${ETC_ANTPICKAX_DIR}/${PARAM_NAME_EXTDATA_URL}"; then
		return 1
	fi

	#
	# Register Node
	#
	if ! _RESULT_MSG=$("${REGISTER_K2HR3_SH}" -r 2>&1); then
		PRNERR "Failed to register node by ${REGISTER_K2HR3_SH} with error: ${_RESULT_MSG}"
		return 1
	fi

	return 0
}

#
# Unregister Node from K2HR3
#
# shellcheck disable=SC2317
UnregisterNode()
{
	if [ ! -f "${REGISTER_K2HR3_SH}" ]; then
		PRNERR "Not found ${REGISTER_K2HR3_SH} script."
		return 1
	fi

	#
	# Unregister Node
	#
	if ! _RESULT_MSG=$("${REGISTER_K2HR3_SH}" -d 2>&1); then
		PRNERR "Failed to unregister node by ${REGISTER_K2HR3_SH} with error: ${_RESULT_MSG}"
		return 1
	fi

	return 0
}

#
# Signal Handler
#
# shellcheck disable=SC2317
SigHandle()
{
	CAUGHT_SIGNAL=1

	#
	# Unregister Node
	#
	UnregisterNode

	exit 0
}

#--------------------------------------------------------------
# Utility Functions : Backup/Restore
#--------------------------------------------------------------
#
# Get value from K2HDKC configuration file
#
# Input:	$1	Keyword
#			$2	Configuration file path(if empty, use default file path)
#
GetConfigValue()
{
	if [ -z "$1" ]; then
		return 1
	fi
	if [ -n "$2" ]; then
		_TMP_K2HDKC_CONFIG_FILE="$2"
	else
		_TMP_K2HDKC_CONFIG_FILE="${K2HDKC_CONFIG_FILE}"
	fi
	if [ ! -f "${_TMP_K2HDKC_CONFIG_FILE}" ]; then
		return 1
	fi
	_CONFIG_KEYWORD="$1"

	_CONFIG_VALUE=$(sed -ne "/^\[K2HDKC\]/,/^\[.*\]/ { /^${_CONFIG_KEYWORD}[[:space:]]*=/ p; }" "${_TMP_K2HDKC_CONFIG_FILE}" | tail -1 | sed -e "s|^[[:space:]]*${_CONFIG_KEYWORD}[[:space:]]*=[[:space:]]*||g" -e 's|#.*$||g' -e 's|[[:space:]]*$||g')
	if [ -z "${_CONFIG_VALUE}" ]; then
		return 1
	fi

	echo "${_CONFIG_VALUE}"
	return 0
}

#
# Stop datadase and Unregister
#
StopDatabaseAndUnregister()
{
	#
	# Get CHMPX node information
	#
	HOSTNAME_PART=$(chmpxstatus -conf "${K2HDKC_CONFIG_FILE}" -self | grep 'hostname' | awk '{print $NF}' | tr -d '\n')
	CTLPORT_PART=$(chmpxstatus -conf "${K2HDKC_CONFIG_FILE}" -self | grep 'control port' | awk '{print $NF}' | tr -d '\n')
	CUK_PART=$(chmpxstatus -conf "${K2HDKC_CONFIG_FILE}" -self | grep 'cuk' | awk '{print $NF}' | tr -d '\n')

	#
	# Do service out
	#
	if [ -n "${HOSTNAME_PART}" ] && [ -n "${CTLPORT_PART}" ] && [ -n "${CUK_PART}" ]; then
		#
		# Node name is "<hostname>:<cntrol port>:<cuk>::"
		#
		NODE_NAME="${HOSTNAME_PART}:${CTLPORT_PART}:${CUK_PART}::"

		#
		# Create chmpxlinetool command file.
		#
		CHMPXLINETOOL_CMDFILE="/tmp/$$.serviceout.cmd"
		{
			echo "serviceout ${NODE_NAME}"
			echo 'exit'
		} > "${CHMPXLINETOOL_CMDFILE}"

		#
		# Service Out this node
		#
		if ! chmpxlinetool -conf "${K2HDKC_CONFIG_FILE}" -run "${CHMPXLINETOOL_CMDFILE}" >/dev/null 2>&1; then
			PRNWARN "Failed to run serviceout this node(${NODE_NAME}), but continue..."
		fi
		rm -f "${CHMPXLINETOOL_CMDFILE}"
	else
		PRNWARN "It looks like chmpx hasn't been run successfully on this node yet."
	fi

	#
	# Unregister from K2HR3
	#
	if ! UnregisterNode; then
		PRNWARN "Failed to unregister this node, but continue..."
	fi

	return 0
}

#
# Create K2hash Archive file
#
CreateBackupArchive()
{
	#
	# Delete old archive file
	#
	DeleteBackupArchive

	#
	# Check and Create snapshot directory
	#
	if [ ! -d "${K2HDKC_AR_FILE_DIR}" ]; then
		if ! /bin/sh -c "${SUDO_CMD} mkdir -p ${K2HDKC_AR_FILE_DIR} 2>/dev/null"; then
			PRNERR "Could not create ${K2HDKC_AR_FILE_DIR} directory."
			return 1
		fi
		if ! /bin/sh -c "${SUDO_CMD} chmod 0777 ${K2HDKC_AR_FILE_DIR} 2>/dev/null"; then
			PRNERR "Could not set permission to ${K2HDKC_AR_FILE_DIR} directory."
			return 1
		fi
	else
		if ! touch "${K2HDKC_AR_FILE_DIR}/.test_premission_file" 2>/dev/null; then
			if ! /bin/sh -c "${SUDO_CMD} chmod 0777 ${K2HDKC_AR_FILE_DIR} 2>/dev/null"; then
				PRNERR "Could not set permission to ${K2HDKC_AR_FILE_DIR} directory."
				return 1
			fi
		else
			rm -f "${K2HDKC_AR_FILE_DIR}/.test_premission_file"
		fi
	fi

	#
	# Get K2HASH file path from configuration file
	#
	if [ -f "${BACKUP_K2HDKC_CONFIG_FILE}" ]; then
		_TMP_K2HDKC_CONFIG_FILE="${BACKUP_K2HDKC_CONFIG_FILE}"
	else
		_TMP_K2HDKC_CONFIG_FILE="${K2HDKC_CONFIG_FILE}"
	fi
	if ! _K2HDKC_CONFIG_VAL_K2HFILE=$(GetConfigValue "${K2HDKC_CONFIG_KEY_K2HFILE}" "${_TMP_K2HDKC_CONFIG_FILE}"); then
		# [NOTE]
		# If /etc/antpickax directory is not mounted, we can not find k2hash file path.
		# So set it here as hard.
		#
		PRNINFO "Not found ${K2HDKC_CONFIG_KEY_K2HFILE} keyword in K2HDKC configuration file, so set /var/lib/antpickax/k2hdkc/k2hdkc.k2h as default."
		_K2HDKC_CONFIG_VAL_K2HFILE="/var/lib/antpickax/k2hdkc/k2hdkc.k2h"
	fi

	#
	# Create k2hlinetool command file
	#
	{
		echo "ar put ${K2HDKC_AR_FILE}"
		echo "exit"
	} > "${K2HLINETOOL_CMD_FILE}"

	#
	# Create archive file
	#
	if ! _RESULT_MSG=$(k2hlinetool -f "${_K2HDKC_CONFIG_VAL_K2HFILE}" -run "${K2HLINETOOL_CMD_FILE}" 2>&1); then
		PRNERR "Failed to create archive file: ${_RESULT_MSG}"
		rm -f "${K2HLINETOOL_CMD_FILE}"
		return 1
	fi
	rm -f "${K2HLINETOOL_CMD_FILE}"

	return 0
}

#
# Delete K2hash Archive file
#
DeleteBackupArchive()
{
	if [ -f "${K2HDKC_AR_FILE}" ]; then
		rm -f "${K2HDKC_AR_FILE}"
	fi
	return 0
}

#
# Restore from K2hash Archive file
#
RestoreFromArchive()
{
	#
	# Check Archive file
	#
	if [ ! -f "${K2HDKC_AR_FILE}" ]; then
		PRNERR "Not found ${K2HDKC_AR_FILE} archive file.(In this case, if you create a backup file that contains empty data, the extracted file(k2ar) may be empty.)"
		return 1
	fi

	#
	# Get some parameter configuration file
	#
	if [ -f "${BACKUP_K2HDKC_CONFIG_FILE}" ]; then
		_TMP_K2HDKC_CONFIG_FILE="${BACKUP_K2HDKC_CONFIG_FILE}"
	else
		_TMP_K2HDKC_CONFIG_FILE="${K2HDKC_CONFIG_FILE}"
	fi
	_K2HDKC_CONFIG_VAL_K2HFILE=$(GetConfigValue "${K2HDKC_CONFIG_KEY_K2HFILE}" "${_TMP_K2HDKC_CONFIG_FILE}")
	_K2HDKC_CONFIG_VAL_K2HMASKBIT=$(GetConfigValue "${K2HDKC_CONFIG_KEY_K2HMASKBIT}" "${_TMP_K2HDKC_CONFIG_FILE}")
	_K2HDKC_CONFIG_VAL_K2HCMASKBIT=$(GetConfigValue "${K2HDKC_CONFIG_KEY_K2HCMASKBIT}" "${_TMP_K2HDKC_CONFIG_FILE}")
	_K2HDKC_CONFIG_VAL_K2HMAXELE=$(GetConfigValue "${K2HDKC_CONFIG_KEY_K2HMAXELE}" "${_TMP_K2HDKC_CONFIG_FILE}")
	_K2HDKC_CONFIG_VAL_K2HPAGESIZE=$(GetConfigValue "${K2HDKC_CONFIG_KEY_K2HPAGESIZE}" "${_TMP_K2HDKC_CONFIG_FILE}")
	_K2HDKC_CONFIG_VAL_K2HFULLMAP=$(GetConfigValue "${K2HDKC_CONFIG_KEY_K2HFULLMAP}" "${_TMP_K2HDKC_CONFIG_FILE}")

	#
	# Setup options
	#
	if [ -n "${_K2HDKC_CONFIG_VAL_K2HMASKBIT}" ]; then
		_OPT_K2HMASKBIT="-mask ${_K2HDKC_CONFIG_VAL_K2HMASKBIT}"
	else
		_OPT_K2HMASKBIT=""
	fi
	if [ -n "${_K2HDKC_CONFIG_VAL_K2HCMASKBIT}" ]; then
		_OPT_K2HCMASKBIT="-cmask ${_K2HDKC_CONFIG_VAL_K2HCMASKBIT}"
	else
		_OPT_K2HCMASKBIT=""
	fi
	if [ -n "${_K2HDKC_CONFIG_VAL_K2HMAXELE}" ]; then
		_OPT_K2HMAXELE="-elementcnt ${_K2HDKC_CONFIG_VAL_K2HMAXELE}"
	else
		_OPT_K2HMAXELE=""
	fi
	if [ -n "${_K2HDKC_CONFIG_VAL_K2HPAGESIZE}" ]; then
		_OPT_K2HPAGESIZE="-pagesize ${_K2HDKC_CONFIG_VAL_K2HPAGESIZE}"
	else
		_OPT_K2HPAGESIZE=""
	fi
	if [ -n "${_K2HDKC_CONFIG_VAL_K2HFULLMAP}" ]; then
		if echo "${_K2HDKC_CONFIG_VAL_K2HFULLMAP}" | grep -q -i -e "^on$" -e "^yes$" -e "^y$"; then
			_OPT_K2HFULLMAP="-fullmap"
		else
			_OPT_K2HFULLMAP=""
		fi
	else
		_OPT_K2HFULLMAP=""
	fi

	#
	# Check k2hash file and directory
	#
	if [ -z "${_K2HDKC_CONFIG_VAL_K2HFILE}" ]; then
		# [NOTE]
		# If /etc/antpickax directory is not mounted, we can not find k2hash file path.
		# So set it here as hard.
		#
		PRNINFO "Not found ${K2HDKC_CONFIG_KEY_K2HFILE} keyword in K2HDKC configuration file, so set /var/lib/antpickax/k2hdkc/k2hdkc.k2h as default."
		_K2HDKC_CONFIG_VAL_K2HFILE="/var/lib/antpickax/k2hdkc/k2hdkc.k2h"
	fi
	if [ ! -f "${_K2HDKC_CONFIG_VAL_K2HFILE}" ]; then
		# [NOTE]
		# When k2hash file is not existed, check directory and creat it if it does not exist.
		#
		_K2HFILE_DIR=$(dirname "${_K2HDKC_CONFIG_VAL_K2HFILE}")
		if [ ! -d "${_K2HFILE_DIR}" ]; then
			PRNWARN "Not found ${_K2HFILE_DIR} directory for ${_K2HDKC_CONFIG_VAL_K2HFILE} file, so try to create it."

			if ! /bin/sh -c "${SUDO_CMD} mkdir -p ${_K2HFILE_DIR} 2>/dev/null"; then
				PRNERR "Could not create ${_K2HFILE_DIR} directory for ${_K2HDKC_CONFIG_VAL_K2HFILE} file."
				return 1
			fi
			if ! /bin/sh -c "${SUDO_CMD} mkmod 0777 ${_K2HFILE_DIR} 2>/dev/null"; then
				PRNERR "Failed to set permission to ${_K2HFILE_DIR} directory for ${_K2HDKC_CONFIG_VAL_K2HFILE} file."
				return 1
			fi
		else
			if ! touch "${_K2HFILE_DIR}/.test_premission_file" 2>/dev/null; then
				if ! /bin/sh -c "${SUDO_CMD} chmod 0777 ${_K2HFILE_DIR} 2>/dev/null"; then
					PRNERR "Could not set permission to ${_K2HFILE_DIR} directory."
					return 1
				fi
			else
				rm -f "${_K2HFILE_DIR}/.test_premission_file"
			fi
		fi
	fi

	#
	# Create k2hlinetool command file
	#
	{
		echo "ar load ${K2HDKC_AR_FILE}"
		echo "exit"
	} > "${K2HLINETOOL_CMD_FILE}"

	#
	# Load archive file
	#
	if ! _RESULT_MSG=$(/bin/sh -c "k2hlinetool -f ${_K2HDKC_CONFIG_VAL_K2HFILE} ${_OPT_K2HMASKBIT} ${_OPT_K2HCMASKBIT} ${_OPT_K2HMAXELE} ${_OPT_K2HPAGESIZE} ${_OPT_K2HFULLMAP} -run ${K2HLINETOOL_CMD_FILE}" 2>&1); then
		PRNERR "Failed to load archive file: ${_RESULT_MSG}"
		rm -f "${K2HLINETOOL_CMD_FILE}"
		return 1
	fi
	rm -f "${K2HLINETOOL_CMD_FILE}"

	return 0
}

#
# Check and Force SERVICE IN
#
# [NOTE]
# If the status is [SERVICE OUT][UP][n/a][Nothing][NoSuspend], force SERVICE IN.
#
CheckAndForceServiceIn()
{
	if chmpxstatus -conf /etc/antpickax/k2hdkc.ini -self | grep -q '\[SERVICE OUT]\.*\[UP\].*\[n/a\].*\[Nothing\].*\[NoSuspend\]'; then
		#
		# This node status it SERVICE OUT, so do SERVICE IN
		#
		HOSTNAME_PART=$(chmpxstatus -conf "${K2HDKC_CONFIG_FILE}" -self | grep 'hostname' | awk '{print $NF}' | tr -d '\n')
		CTLPORT_PART=$(chmpxstatus -conf "${K2HDKC_CONFIG_FILE}" -self | grep 'control port' | awk '{print $NF}' | tr -d '\n')
		CUK_PART=$(chmpxstatus -conf "${K2HDKC_CONFIG_FILE}" -self | grep 'cuk' | awk '{print $NF}' | tr -d '\n')

		if [ -n "${HOSTNAME_PART}" ] && [ -n "${CTLPORT_PART}" ] && [ -n "${CUK_PART}" ]; then
			#
			# Node name is "<hostname>:<cntrol port>:<cuk>::"
			#
			NODE_NAME="${HOSTNAME_PART}:${CTLPORT_PART}:${CUK_PART}::"

			#
			# Create chmpxlinetool command file.
			#
			CHMPXLINETOOL_CMDFILE="/tmp/$$.serviceout.cmd"
			{
				echo "servicein ${NODE_NAME}"
				echo 'exit'
			} > "${CHMPXLINETOOL_CMDFILE}"

			#
			# Service Out this node
			#
			if ! chmpxlinetool -conf "${K2HDKC_CONFIG_FILE}" -run "${CHMPXLINETOOL_CMDFILE}" >/dev/null 2>&1; then
				PRNWARN "Failed to run servicein this node(${NODE_NAME})"
			fi
			rm -f "${CHMPXLINETOOL_CMDFILE}"
		else
			PRNWARN "It looks like chmpx hasn't been run successfully on this node."
		fi
	fi

	return 0
}

#
# Check Conatiner Status
#
IsSafeConatinerStatus()
{
	if ! pgrep -x chmpx >/dev/null 2>&1; then
		return 1
	fi
	if ! chmpxstatus -conf /etc/antpickax/k2hdkc.ini -self 2>/dev/null | grep -q "status.*\[SERVICE IN\].*\[UP\].*\[NoSuspend\]"; then
		return 1
	fi

	return 0
}

#--------------------------------------------------------------
# Usage
#--------------------------------------------------------------
Usage()
{
	echo ""
	echo "Usage: ${SCRIPTNAME} --help(-h)"
	echo "       ${SCRIPTNAME} [ start(s) | stop(a) ]"
	echo "       ${SCRIPTNAME} [ backup(b) | delete(d) | restore(r) ] <data dir> <snapshot name>"
	echo "       ${SCRIPTNAME} [ status(t) ]"
	echo ""
	echo " [Parameter]"
	echo "   start(s)           : Start main processes"
	echo "   stop(a)            : Stop database and unregister(abort)"
	echo "   backup(b)          : Run backup mode"
	echo "   delete(d)          : Run delete backup mode"
	echo "   restore(r)         : Run restore mode"
	echo "   status(t)          : Get container status: RUNNING or HEALTHY"
	echo ""
	echo "   <data dir>         : K2HDKC Data Top directory path for backup/restore/delete mode"
	echo "   <snapshot name>	: Snapshot name(sub-directory name) for backup/restore/delete mode"
	echo ""
	echo " [Options]"
	echo "   --help(-h)         : Print usage."
	echo ""
}

#==============================================================
# Parse options(parameters)
#==============================================================
#
# Option value
#
RUN_MODE=""
OPT_DATA_TOP_DIR=""
OPT_SNAPSHOT_NAME=""

while [ $# -ne 0 ]; do
	if [ -z "$1" ]; then
		break;

	elif [ "$1" = "-h" ] || [ "$1" = "-H" ] || [ "$1" = "--help" ] || [ "$1" = "--HELP" ]; then
		Usage
		exit 0

	elif [ "$1" = "start" ] || [ "$1" = "START" ] || [ "$1" = "s" ] || [ "$1" = "S" ]; then
		RUN_MODE="start"

	elif [ "$1" = "stop" ] || [ "$1" = "STOP" ] || [ "$1" = "a" ] || [ "$1" = "A" ]; then
		RUN_MODE="stop"

	elif [ "$1" = "backup" ] || [ "$1" = "BACKUP" ] || [ "$1" = "b" ] || [ "$1" = "B" ]; then
		RUN_MODE="backup"

	elif [ "$1" = "delete" ] || [ "$1" = "DELETE" ] || [ "$1" = "d" ] || [ "$1" = "D" ]; then
		RUN_MODE="delete"

	elif [ "$1" = "restore" ] || [ "$1" = "RESTORE" ] || [ "$1" = "r" ] || [ "$1" = "R" ]; then
		RUN_MODE="restore"

	elif [ "$1" = "status" ] || [ "$1" = "STATUS" ] || [ "$1" = "t" ] || [ "$1" = "T" ]; then
		RUN_MODE="status"

	else
		if [ -z "${OPT_DATA_TOP_DIR}" ]; then
			OPT_DATA_TOP_DIR="$1"
		elif [ -z "${OPT_SNAPSHOT_NAME}" ]; then
			OPT_SNAPSHOT_NAME="$1"
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
if [ -z "${RUN_MODE}" ]; then
	PRNINFO "Not specified mode(start or backup or restore), so set \"start\" as default."
	RUN_MODE="start"
fi

if [ "${RUN_MODE}" = "start" ] || [ "${RUN_MODE}" = "stop" ] || [ "${RUN_MODE}" = "status" ]; then
	if [ -n "${OPT_DATA_TOP_DIR}" ] || [ -n "${OPT_SNAPSHOT_NAME}" ]; then
		PRNERR "The data top directory and snapshot name parameters cannot be specified in start mode."
		exit 1
	fi
else
	# [NOTE]
	# The default values of the symbols are:
	#	_TOP_DATA_DIR		: /var/lib/antpickax/k2hdkc
	#	SNAPSHOT_NAME		: trovebackup
	#	K2HDKC_AR_FILE_DIR	: /var/lib/antpickax/k2hdkc/snapshots/trovebackup
	#	K2HDKC_AR_FILE		: /var/lib/antpickax/k2hdkc/snapshots/trovebackup/trovebackup.k2har
	#
	if [ -n "${OPT_DATA_TOP_DIR}" ]; then
		_TOP_DATA_DIR="${OPT_DATA_TOP_DIR}"
	else
		_TOP_DATA_DIR="${DEFAULT_TOP_DATA_DIR}"
	fi
	if [ -n "${OPT_SNAPSHOT_NAME}" ]; then
		SNAPSHOT_NAME="${OPT_SNAPSHOT_NAME}"
	else
		SNAPSHOT_NAME="${DEFAULT_SNAPSHOT_NAME}"
	fi
	K2HDKC_AR_FILE_DIR="${_TOP_DATA_DIR}/snapshots/${SNAPSHOT_NAME}"
	K2HDKC_AR_FILE="${K2HDKC_AR_FILE_DIR}/${SNAPSHOT_NAME}${SUFFIX_AR_FILENAME}"
fi

#==============================================================
# Processing
#==============================================================
#
# Setup sudo command prefix
#
SetupSudoPrefix

#
# Load and Reset PROXY Environments
#
if ! ResetProxyEnv; then
	exit 1
fi

#
# Main Processing
#
IS_ERROR=0

if [ "${RUN_MODE}" = "start" ]; then
	#----------------------------------------------------------
	# Start all processes
	#----------------------------------------------------------
	#
	# Check directories
	#
	if ! CheckDirectories; then
		exit 1
	fi

	#
	# Read and Check Environments, and Create files
	#
	if ! ReadEnvAndCreateFile; then
		exit 1
	fi

	#
	# Register Node to K2HR3
	#
	if ! RegisterNode; then
		exit 1
	fi

	#
	# Wait until other nodes have also registered
	#
	sleep 15

	#
	# Set trap signal( SIGTERM(15) )
	#
	# [NOTE]
	# Normally, if it is not changed with the STOPSIGNAL command or --stop-signal
	# option when stopping a container, this process receives a SIGTERM(and then
	# a SIGKILL).
	# This process immediately unregister the Node from K2HR3 upon receiving SIGTERM.
	#
	trap 'SigHandle 15'	15

	FIRST_EXEC=1
	CHMPX_HELPER_PID=0
	K2HDKC_HELPER_PID=0
	while [ "${CAUGHT_SIGNAL}" -eq 0 ]; do
		#
		# Wait
		#
		if [ "${FIRST_EXEC}" -eq 1 ]; then
			sleep "${FIRST_RESOURCE_UPDATE_INTERVAL_SEC}"
		else
			sleep "${RESOURCE_UPDATE_INTERVAL_SEC}"
		fi
		if [ "${CAUGHT_SIGNAL}" -ne 0 ]; then
			break;
		fi

		#
		# Run k2hr3-get-resource
		#
		# [NOTE]
		# k2hr3-get-resource starts as a non-daemon.
		# (Do not set "-daemon" option and also set "USE_DAEMON=false"(in config file).)
		# Thus, it will start k2hr3-get-resource in OneShot.
		#
		# The k2hr3-get-resource process requires the /var/lib/cloud/data/instance-id file.
		# You need to mount it when starting this container.
		#
		if ! /usr/libexec/k2hr3-get-resource-helper; then
			if [ "${FIRST_EXEC}" -eq 1 ]; then
				PRNERR "Failed to run k2hr3-get-resource-helper."
				continue
			fi
			PRNWARN "Failed to run k2hr3-get-resource-helper, but continue..."
		else
			# [NOTE]
			# The backup/restore mechanism requires values from the k2hdkc.ini file.
			# However, the backup/restore container does not run k2hr3-get-resource-helper.
			# Therefore, copy the k2hdkc.ini file output by the main container to the
			# data directory. This data directory is mounted and shared in each
			# container, so it can be accessed from backup/restore.
			#
			if [ -f "${BACKUP_K2HDKC_CONFIG_FILE}" ]; then
				if ! diff "${K2HDKC_CONFIG_FILE}" "${BACKUP_K2HDKC_CONFIG_FILE}" >/dev/null 2>&1; then
					if ! cp -p "${K2HDKC_CONFIG_FILE}" "${BACKUP_K2HDKC_CONFIG_FILE}" >/dev/null 2>&1; then
						PRNWARN "Failed to copy ${K2HDKC_CONFIG_FILE} to ${BACKUP_K2HDKC_CONFIG_FILE}, but continue..."
					fi
				fi
			else
				if ! cp -p "${K2HDKC_CONFIG_FILE}" "${BACKUP_K2HDKC_CONFIG_FILE}" >/dev/null 2>&1; then
					PRNWARN "Failed to copy ${K2HDKC_CONFIG_FILE} to ${BACKUP_K2HDKC_CONFIG_FILE}, but continue..."
				fi
			fi
		fi

		#
		# Run CHMPX process
		#
		if [ "${CHMPX_HELPER_PID}" -ne 0 ]; then
			if ! ps p "${CHMPX_HELPER_PID}" >/dev/null 2>&1; then
				CHMPX_HELPER_PID=0
			fi
		fi
		if [ "${CHMPX_HELPER_PID}" -eq 0 ]; then
			#
			# Wait other/master nodes up
			#
			if ! WaitSvrnodes; then
				sleep 1
				continue
			else
				if [ "${FIRST_EXEC}" -eq 1 ]; then
					sleep "${LAUNCH_INTERVAL_SEC}"
				fi
			fi

			#
			# Run wrapper
			#
			nohup /usr/libexec/chmpx-service-helper start >/dev/null 2>&1 &
			CHMPX_HELPER_PID=$!

			sleep "${LAUNCH_INTERVAL_SEC}"
			if ! ps p "${CHMPX_HELPER_PID}" >/dev/null 2>&1; then
				CHMPX_HELPER_PID=0
				continue
			fi
		else
			# [NOTE]
			# If CHMPX and K2HDKC are running and in SERVICE OUT state,
			# force SERVICE IN.
			#
			if [ "${K2HDKC_HELPER_PID}" -ne 0 ]; then
				CheckAndForceServiceIn
			fi
		fi

		#
		# Run K2HDKC process
		#
		if [ "${K2HDKC_HELPER_PID}" -ne 0 ]; then
			if ! ps p "${K2HDKC_HELPER_PID}" >/dev/null 2>&1; then
				K2HDKC_HELPER_PID=0
			fi
		fi
		if [ "${K2HDKC_HELPER_PID}" -eq 0 ]; then
			#
			# Run wrapper
			#
			nohup /usr/libexec/k2hdkc-service-helper start >/dev/null 2>&1 &
			K2HDKC_HELPER_PID=$!

			sleep "${LAUNCH_INTERVAL_SEC}"
			if ! ps p "${K2HDKC_HELPER_PID}" >/dev/null 2>&1; then
				K2HDKC_HELPER_PID=0
				continue
			fi
		fi

		if [ "${FIRST_EXEC}" -eq 1 ]; then
			FIRST_EXEC=0
		fi
	done

elif [ "${RUN_MODE}" = "stop" ]; then
	#----------------------------------------------------------
	# Stop database and unregister
	#----------------------------------------------------------
	if ! StopDatabaseAndUnregister; then
		PRNERR "Failed to stop database and unregister."
		IS_ERROR=1
	fi

elif [ "${RUN_MODE}" = "backup" ]; then
	#----------------------------------------------------------
	# Backup processing
	#----------------------------------------------------------
	if ! CreateBackupArchive; then
		PRNERR "Failed to backup."
		IS_ERROR=1
	fi

elif [ "${RUN_MODE}" = "delete" ]; then
	#----------------------------------------------------------
	# Delete backup processing
	#----------------------------------------------------------
	if ! DeleteBackupArchive; then
		PRNERR "Failed to delete backup."
		IS_ERROR=1
	fi

elif [ "${RUN_MODE}" = "restore" ]; then
	#----------------------------------------------------------
	# Restore processing
	#----------------------------------------------------------
	if ! RestoreFromArchive; then
		PRNERR "Failed to restore."
		IS_ERROR=1
	fi

elif [ "${RUN_MODE}" = "status" ]; then
	#----------------------------------------------------------
	# Get Conatiner Status
	#----------------------------------------------------------
	if IsSafeConatinerStatus; then
		echo "HEALTHY"
	else
		echo "RUNNING"
	fi

else
	PRNERR "Unknown process run mode: ${RUN_MODE}"
	IS_ERROR=1
fi

if [ "${IS_ERROR}" -eq 1 ]; then
	exit 1
fi

exit 0

#
# Local variables:
# tab-width: 4
# c-basic-offset: 4
# End:
# vim600: noexpandtab sw=4 ts=4 fdm=marker
# vim<600: noexpandtab sw=4 ts=4
#
