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
# [NOTE]
# This file defines common functions that are loaded into 
# k2hdkcstack.sh and k2hdkcdockerimage.sh.
#
# BE CAREFUL! when editing the content as it will affect both
# scripts.
#==============================================================

#--------------------------------------------------------------
# Check and Set undefined variables and functions
#--------------------------------------------------------------
if [ -z "${PIPEFAILURE_FILE}" ]; then
	PIPEFAILURE_FILE="/tmp/.pipefailure.$(od -An -tu4 -N4 /dev/random | tr -d ' \n')"
fi
if ! type PRNERR >/dev/null 2>&1; then
	PRNERR()
	{
		echo ""
		echo "[ERROR] $*"
	}
fi
if ! type PRNINFO >/dev/null 2>&1; then
	PRNINFO()
	{
		echo ""
		echo "    [INFO] $*"
	}
fi

if [ -z "${PATCHFILE_LIST_FILENAME}" ]; then
	PATCHFILE_LIST_FILENAME="patch_list"
fi

#--------------------------------------------------------------
# Common utility functions
#--------------------------------------------------------------
#
# Extract patch files
#
# Input	$1	: Source directry to patch files	(ex. "/home/user/k2hdkc_dbaas_trove/trove")
#		$2	: Destination directory path		(ex. "/opt/stack/trove")
#
ExtractPatchFiles()
{
	if [ $# -lt 2 ]; then
		PRNERR "Parameters are wrong."
		return 1
	fi
	_PATCH_SRC_DIR="$1"
	_PATCH_DEST_DIR="$2"

	#
	# Patch files list
	#
	_PATCH_FILES_LIST="${_PATCH_SRC_DIR}/${PATCHFILE_LIST_FILENAME}"
	if [ ! -f "${_PATCH_FILES_LIST}" ]; then
		PRNERR "Not found ${_PATCH_FILES_LIST} file."
		return 1
	fi

	#
	# Patch from patch files
	#
	_PATCH_FILES=$(sed -n "/^[[:space:]]*\[PATCH\][[:space:]]*$/,/^[[:space:]]*\[.*\][[:space:]]*$/p" "${_PATCH_FILES_LIST}" 2>/dev/null | sed -e 's/^[[:space:]]*\[.*\].*$//g' -e 's/^[[:space:]]*//g' -e 's/[[:space:]]*$//g' -e '/^$/d' | grep -v '^[[:space:]]*#')
	for _one_patch_file in ${_PATCH_FILES}; do
		if [ ! -f "${_PATCH_SRC_DIR}/${_one_patch_file}.patch" ]; then
			PRNERR "Not found source patch file: ${_PATCH_SRC_DIR}/${_one_patch_file}.patch"
			return 1
		fi
		if [ ! -f "${_PATCH_DEST_DIR}/${_one_patch_file}" ]; then
			PRNERR "Not found destination patch file: ${_PATCH_DEST_DIR}/${_one_patch_file}"
			return 1
		fi

		if ({ patch -u "${_PATCH_DEST_DIR}/${_one_patch_file}" < "${_PATCH_SRC_DIR}/${_one_patch_file}.patch" 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to patch to ${_PATCH_DEST_DIR}/${_one_patch_file} by ${_PATCH_SRC_DIR}/${_one_patch_file}.patch file"
			return 1
		fi
	done

	#
	# Copy additional files
	#
	_COPY_FILES=$(sed -n "/^[[:space:]]*\[COPY\][[:space:]]*$/,/^[[:space:]]*\[.*\][[:space:]]*$/p" "${_PATCH_FILES_LIST}" | sed -e 's/^[[:space:]]*\[.*\].*$//g' -e 's/^[[:space:]]*//g' -e 's/[[:space:]]*$//g' -e '/^$/d' | grep -v '^[[:space:]]*#')

	for _one_copy_file in ${_COPY_FILES}; do
		if [ ! -f "${_PATCH_SRC_DIR}/${_one_copy_file}" ]; then
			PRNERR "Not found additinal file: ${_PATCH_SRC_DIR}/${_one_copy_file}"
			return 1
		fi
		if [ -f "${_PATCH_DEST_DIR}/${_one_copy_file}" ]; then
			PRNERR "Found destination file(so could not copy file): ${_PATCH_DEST_DIR}/${_one_copy_file}"
			return 1
		fi

		_DEST_DIR_PATH=$(dirname "${_PATCH_DEST_DIR}/${_one_copy_file}")
		if [ ! -d "${_DEST_DIR_PATH}" ]; then
			if ! mkdir -p "${_DEST_DIR_PATH}" 2>/dev/null; then
				PRNERR "Failed to create directory ${_DEST_DIR_PATH}"
				return 1
			fi
		fi

		if ! cp "${_PATCH_SRC_DIR}/${_one_copy_file}" "${_PATCH_DEST_DIR}/${_one_copy_file}" >/dev/null 2>&1; then
			PRNERR "Failed to copy ${_PATCH_SRC_DIR}/${_one_copy_file} to ${_PATCH_DEST_DIR}/${_one_copy_file}"
			return 1
		fi
		echo "    copied file ${_PATCH_DEST_DIR}/${_one_copy_file}"
	done

	return 0
}

#
# Clone repository and Set branch
#
# Input	$1	: repository name(for https://opendev.org/openstack)
#		$2	: base directory
#		$3	: branch name
#
CloneRepositoryAndSetBranch()
{
	_CLONE_REPO_NAME="$1"
	_CLONE_BASE_DIR="$2"
	_SWITCH_BRANCH_NAME="$3"

	if [ -z "${_CLONE_REPO_NAME}" ]; then
		PRNERR "Not specified repository name."
		return 1
	fi
	if [ -z "${_CLONE_BASE_DIR}" ] || [ ! -d "${_CLONE_BASE_DIR}" ]; then
		PRNERR "Not specified base directory to clone repository(${_CLONE_REPO_NAME}), or not found base directory(${_CLONE_BASE_DIR}) to clone repository.."
		return 1
	fi
	if [ -z "${_SWITCH_BRANCH_NAME}" ]; then
		PRNERR "Not specified branch name."
		return 1
	fi

	(
		PRNINFO "Clone ${_CLONE_REPO_NAME} repository to ${_CLONE_BASE_DIR}/${_CLONE_REPO_NAME}"

		cd "${_CLONE_BASE_DIR}" || exit 1

		if ({ git clone "https://opendev.org/openstack/${_CLONE_REPO_NAME}" 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to clone ${_CLONE_REPO_NAME} repository"
			exit 1
		fi
		PRNINFO "Succeed to clone ${_CLONE_REPO_NAME} repository to ${_CLONE_BASE_DIR}/${_CLONE_REPO_NAME}"
		echo ""

		cd "${_CLONE_BASE_DIR}/${_CLONE_REPO_NAME}" || exit 1

		if ({ git checkout "${_SWITCH_BRANCH_NAME}" 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's|^|    |g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to switch branch to ${_SWITCH_BRANCH_NAME}."
			exit 1
		fi
		PRNINFO "Succeed to switch branch to ${_SWITCH_BRANCH_NAME}"
		echo ""
	)

	return 0
}

#
# Local variables:
# tab-width: 4
# c-basic-offset: 4
# End:
# vim600: noexpandtab sw=4 ts=4 fdm=marker
# vim<600: noexpandtab sw=4 ts=4
#
