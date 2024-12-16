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

#===============================================================
# Configuration for trove_build_helper.sh
#===============================================================
# This file is loaded into the build_helper.sh script.
# The build_helper.sh script is a Github Actions helper script that
# builds and packages the target repository.
# This file is mainly created to define variables that differ depending
# on the OS and version.
# It also contains different information(such as packages to install)
# for each repository.
#
# In the initial state, you need to set the following variables:
#   INSTALL_PKG_LIST  : A list of packages to be installed for build and packaging
#   INSTALLER_BIN     : Package management command
#   UPDATE_CMD        : Update sub command for package management command
#   UPDATE_CMD_ARG    : Update sub command arguments for package management command
#   INSTALL_CMD       : Install sub command for package management command
#   INSTALL_CMD_ARG   : Install sub command arguments for package management command
#   INSTALL_AUTO_ARG  : No interaption arguments for package management command
#   INSTALL_QUIET_ARG : Quiet arguments for package management command
#   BASE_OS_UBUNTU    : Set to 1 for Ubuntu, 0 otherwise
#   BASE_OS_ROCKY     : Set to 1 for Rocky, 0 otherwise
#   BASE_OS_ALPINE    : Set to 1 for Alpine, 0 otherwise
#

#----------------------------------------------------------
# Default values
#----------------------------------------------------------
INSTALL_PKG_LIST=""
INSTALLER_BIN=""
UPDATE_CMD=""
UPDATE_CMD_ARG=""
INSTALL_CMD=""
INSTALL_CMD_ARG=""
INSTALL_AUTO_ARG=""
INSTALL_QUIET_ARG=""

BASE_OS_UBUNTU=0
BASE_OS_ROCKY=0
BASE_OS_ALPINE=0

#----------------------------------------------------------
# Variables for each OS Type
#----------------------------------------------------------
BASE_OSTYPE=$(grep -i '^ID=' /etc/os-release | sed -e 's/[[:space:]]//g' -e 's/ID=//g' -e 's/"//g')

if [ -z "${BASE_OSTYPE}" ]; then
	#
	# Unknown OS : Nothing to do
	#
	:

elif echo "${BASE_OSTYPE}" | grep -q -i -e "ubuntu"; then
	INSTALL_PKG_LIST="git"
	INSTALLER_BIN="apt-get"
	UPDATE_CMD="update"
	UPDATE_CMD_ARG=""
	INSTALL_CMD="install"
	INSTALL_CMD_ARG=""
	INSTALL_AUTO_ARG="-y"
	INSTALL_QUIET_ARG="-qq"
	BASE_OS_UBUNTU=1

elif echo "${BASE_OSTYPE}" | grep -q -i "rocky"; then
	INSTALL_PKG_LIST="git"
	INSTALLER_BIN="dnf"
	UPDATE_CMD="update"
	UPDATE_CMD_ARG=""
	INSTALL_CMD="install"
	INSTALL_CMD_ARG=""
	INSTALL_AUTO_ARG="-y"
	INSTALL_QUIET_ARG="-q"
	BASE_OS_ROCKY=1

	#
	# Enable CRB repository
	#
	if "${INSTALLER_BIN}" "${INSTALL_CMD}" "${INSTALL_AUTO_ARG}" 'dnf-command(config-manager)'; then
		if ! "${INSTALLER_BIN}" config-manager --set-enabled crb; then
			echo "[ERROR] Failed to enable CRB repository. The script doesn't break here, but fails to install the package."
		fi
	else
		echo "[ERROR] Failed to install \"dnf-command(config-manager)\". The script doesn't break here, but fails to install the package."
	fi

elif echo "${BASE_OSTYPE}" | grep -q -i "alpine"; then
	INSTALL_PKG_LIST="bash sudo git"
	INSTALLER_BIN="apk"
	UPDATE_CMD="update"
	UPDATE_CMD_ARG="--no-progress"
	INSTALL_CMD="add"
	INSTALL_CMD_ARG="--no-progress --no-cache"
	INSTALL_AUTO_ARG=""
	INSTALL_QUIET_ARG="-q"
	BASE_OS_ALPINE=1
fi

#
# Local variables:
# tab-width: 4
# c-basic-offset: 4
# End:
# vim600: noexpandtab sw=4 ts=4 fdm=marker
# vim<600: noexpandtab sw=4 ts=4
#
