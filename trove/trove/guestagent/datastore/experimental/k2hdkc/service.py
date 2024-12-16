# -*- coding: utf-8 -*-
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

import docker
import shlex
from oslo_log import log as logging
from trove.common import cfg
from trove.common import exception
from trove.instance import service_status
from trove.common import utils
from trove.common.stream_codecs import KeyValueCodec
from trove.guestagent.common.configuration import ConfigurationManager
from trove.guestagent.datastore import service
from trove.guestagent.common import guestagent_utils
from trove.guestagent.utils import docker as docker_util

CONF = cfg.CONF
LOG = logging.getLogger(__name__)
SERVER_INI = '/etc/antpickax/server.ini'
K2HDKC_TROVE_INI = '/etc/antpickax/k2hdkc-trove.cfg'
K2HDKC_SERVICE = ['k2hdkc-trove']
K2HDKC_DATA_DIR = '/var/lib/antpickax/k2hdkc'

# [TODO]
# At this time, the guest operating system only supports CentOS.
# Therefore, the values ??of the following variables are set,
# but if the supported OS expands in the future, please change
# the values ??variably.
#
OWNER = '1001'
GROUP = '1001'

class K2hdkcApp(service.BaseDbApp):
    """
    Handles installation and configuration of K2hdkc
    on a Trove instance.
    """
    def __init__(self, status, docker_client):
        LOG.debug("K2hdkcApp init")
        super().__init__(status, docker_client)

        self._status = status
        self.k2hdkc_owner = OWNER
        self.k2hdkc_group = GROUP
        self.configuration_manager = (ConfigurationManager(
            K2HDKC_TROVE_INI,
            OWNER,
            GROUP,
            KeyValueCodec(delimiter='=',
                          comment_marker='#',
                          line_terminator='\n'),
            requires_root=True))
        self.state_change_wait_time = CONF.state_change_wait_time

    def update_overrides(self, context, overrides, remove=False):
        """ invokes the configuration_manager.apply_user_override() """
        LOG.debug(
            "update_overrides - implement as like as others(but not test)")
        if overrides:
            LOG.debug("K2hdkcApp update_overrides")
            self.configuration_manager.apply_user_override(overrides)

    def remove_overrides(self):
        """ invokes the configuration_manager.remove_user_override() """
        self.configuration_manager.remove_user_override()

    def get_value(self, key):
        """ returns the k2hdkc configuration_manager """
        return self.configuration_manager.get_value(key)

    @property
    def k2hdkc_data_dir(self):
        """ returns the k2hdkc data directory """
        return guestagent_utils.build_file_path(CONF.k2hdkc.mount_point,
                                                'data')

    @property
    def service_candidates(self):
        """ returns the k2hdkc list """
        return ['k2hdkc-trove']

    def stop_db(self, update_db=False, do_not_start_on_reboot=False):
        """ stops k2hdkc database """
        cmd = '/bin/sh -c "/usr/libexec/k2hdkctrove.sh stop"'
        try:
            docker_util.run_command(self.docker_client, cmd)
        except Exception as exc:
            LOG.warning('Could not stop databse and unregister node.')

    def restore_backup_k2hdkc(self, context, restore_location, backup_info, overrides):
        LOG.debug("restore_backup - called")

        # 1. backup_id
        backup_id = backup_info.get('id')

        # 2. storage_driver
        qstr_storage_driver = shlex.quote(CONF.storage_strategy)

        # 3. backup_driver
        qstr_backup_driver = shlex.quote(cfg.get_configuration_property('backup_strategy'))

        # 4. os_cred
        qstr_auth_token = shlex.quote(context.auth_token)
        qstr_auth_url = shlex.quote(CONF.service_credentials.auth_url)
        qstr_project_id = shlex.quote(context.project_id)
        os_cred = (f"--os-token={qstr_auth_token} "
                   f"--os-auth-url={qstr_auth_url} "
                   f"--os-tenant-id={qstr_project_id}")

        # 5. backup_info_location
        qstr_backup_info_location = shlex.quote(backup_info["location"])

        # 6. backup_info_checksum
        qstr_backup_info_checksum = shlex.quote(backup_info["checksum"])

        # 7. db-datadir
        qstr_restore_location = shlex.quote(restore_location)

        # 8. backup_aes_cbc_key
        qstr_backup_aes_cbc_key = shlex.quote(CONF.backup_aes_cbc_key)

        # a. image
        image = cfg.get_configuration_property('backup_docker_image')

        # b. name
        name = 'db_restore'

        # c. network_mode
        network_mode = "host"

        # d. volumes
        volumes = {
            "/var/lib/cloud/data": {"bind": "/var/lib/cloud/data", "mode": "rw", "driver": "local"},
            "/var/lib/antpickax/k2hdkc": {"bind": "/var/lib/antpickax/k2hdkc", "mode": "rw", "driver": "local"},
        }
        ports = {}
        if network_mode == "bridge":
            tcp_ports = cfg.get_configuration_property('tcp_ports')
            for port_range in tcp_ports:
                for port in port_range:
                    ports[f'{port}/tcp'] = port

        # e. user
        # k2hdkc user and group exist in docker container.
        #
        user = "1001:1001"

        # f. command
        command = (
            f'/usr/bin/python3 main.py --nobackup '
            f'--storage-driver={qstr_storage_driver} --driver={qstr_backup_driver} '
            f'{os_cred} '
            f'--restore-from={qstr_backup_info_location} '
            f'--restore-checksum={qstr_backup_info_checksum} '
            f'--db-datadir {qstr_restore_location}'
        )
        if CONF.backup_aes_cbc_key:
            command = (f"{command} "
                       f"--backup-encryption-key={qstr_backup_aes_cbc_key}")

        sysctls = {}
        if CONF.docker_container_sysctls:
            sysctls = CONF.docker_container_sysctls

        try:
            container = self.docker_client.containers.get(name)
            LOG.debug(f'Removing existing container {name}')
            container.remove(force=True)
        except docker.errors.NotFound:
            pass

        # [NOTE]
        # The '-' character cannot be used in environment variable names,
        # so it is added replaced key name with the '_' character.
        #
        environment = overrides.copy()
        for env_key in list(overrides.keys()):
            replaced_key = env_key.replace('-', '_')
            if replaced_key != env_key:
                environment[replaced_key] = overrides[env_key]

        try:
            LOG.info(f"Creating docker container, image: {image}, name: {name}, "
                         f"volumes: {volumes}, ports: {ports}, user: {user}, "
                         f"network_mode: {network_mode}, environment: {environment}, "
                         f"command: {command}, sysctls: {sysctls}")
            output = self.docker_client.containers.run(
                image,
                name=name,
                restart_policy={"Name": "unless-stopped"},
                privileged=False,
                network_mode=network_mode,
                detach=True,
                volumes=volumes,
                remove=False,
                ports=ports,
                user=user,
                environment=environment,
                command=command,
                sysctls=sysctls
            )

        except docker.errors.ContainerError as err:
            output = err.container.logs()
            return output, False

        return output, True


class K2hdkcAppStatus(service.BaseDbStatus):  # pylint: disable=too-few-public-methods
    """
    Handles all of the status updating for the K2hdkc guest agent.
    """
    def __init__(self, docker_client):
        LOG.debug("K2hdkcAppStatus::__init__")
        super().__init__(docker_client)

    def get_actual_db_status(self):  # pylint: disable=no-self-use
        """ It is called from wait_for_real_status_to_change_to of BaseDbStatus class.
        """
        status = docker_util.get_container_status(self.docker_client)
        LOG.debug("K2hdkcAppStatus::_get_actual_db_status")
        if status == "running":
            cmd = '/bin/sh -c "/usr/libexec/k2hdkctrove.sh status"'
            container_status = docker_util.run_command(self.docker_client, cmd)
            LOG.debug("Get Container Status: {}".format(container_status.decode()))

            if "HEALTHY" in container_status.decode():
                LOG.debug('Container status result is HEALTHY, so status is HEALTHY')
                return service_status.ServiceStatuses.HEALTHY
            else:
                LOG.debug('Container status result is %s (not including HEALTHY), so status is RUNNING', container_status)
                return service_status.ServiceStatuses.RUNNING

        elif status == "not running":
            return service_status.ServiceStatuses.SHUTDOWN
        elif status == "paused":
            return service_status.ServiceStatuses.PAUSED
        elif status == "exited":
            return service_status.ServiceStatuses.SHUTDOWN
        elif status == "dead":
            return service_status.ServiceStatuses.CRASHED
        else:
            return service_status.ServiceStatuses.UNKNOWN

#
# Local variables:
# tab-width: 4
# c-basic-offset: 4
# End:
# vim600: expandtab sw=4 ts=4 fdm=marker
# vim<600: expandtab sw=4 ts=4
#
