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
"""OpenStack Clusters API guestagent client implementation."""

from oslo_log import log as logging
from trove.common import cfg
from trove.common import exception
from trove.common import utils
#from trove.guestagent import backup
from trove.guestagent.datastore import manager
from trove.guestagent.datastore.experimental.k2hdkc import service
from trove.guestagent.common import operating_system
from trove.guestagent.utils import docker as docker_util
from trove.guestagent import volume
from trove.instance import service_status
from trove.instance.service_status import ServiceStatuses
from trove.common.notification import EndNotification
import os.path
from pathlib import Path

CONF = cfg.CONF
K2HDKC_MANAGER = 'k2hdkc'
LOG = logging.getLogger(__name__)
SERVICE_STATUS_TIMEOUT = 60
K2HDKC_CONFIG_PARAM_DIR = '/etc/antpickax'


class Manager(manager.Manager):
    """OpenStack Clusters API guest-agent server implementation."""
    def __init__(self):
        """MUST be implemented."""
        super().__init__(K2HDKC_MANAGER)
        self._service_status_timeout = SERVICE_STATUS_TIMEOUT
        conf_dir = Path(K2HDKC_CONFIG_PARAM_DIR)
        if not conf_dir.exists():
            try:
                utils.execute_with_timeout(
                    "/bin/sudo mkdir -p {}".format(K2HDKC_CONFIG_PARAM_DIR),
                    shell=True)
            except exception.ProcessExecutionError:
                LOG.warning("Failure: sudo mkdir -p {}".format(
                    K2HDKC_CONFIG_PARAM_DIR))
        try:
            utils.execute_with_timeout(
                "/bin/sudo chmod 0777 {}".format(K2HDKC_CONFIG_PARAM_DIR),
                shell=True)
        except exception.ProcessExecutionError:
            LOG.warning(
                "Failure: sudo chmod 0777 {}".format(K2HDKC_CONFIG_PARAM_DIR))
        self.status = service.K2hdkcAppStatus(self.docker_client)
        self.app = service.K2hdkcApp(self.status, self.docker_client)


    #################
    # Instance related
    #################
    def do_prepare(self, context, packages, databases, memory_mb, users,
                   device_path, mount_point, backup_info, config_contents,
                   root_password, overrides, cluster_config, snapshot, ds_version=None):
        # pylint: disable=too-many-arguments
        """MUST be implemented. trove.guestagent.datastore.
        trove.guestagent.datastore.manager calls self.do_prepare in
        trove.guestagent.datastore.manager.prepare()
        """
        LOG.debug("Starting initial configuration.")
        if overrides:
            LOG.info("overrides")
            LOG.info("overrides:{}, backup_info:{}".format(overrides, backup_info))
            docker_image = CONF.get(CONF.datastore_manager).docker_image
            image = (f'{docker_image}')
            volumes = {
                "/var/lib/cloud/data": {"bind": "/var/lib/cloud/data", "mode": "rw", "driver": "local"},
                "/var/lib/antpickax/k2hdkc": {"bind": "/var/lib/antpickax/k2hdkc", "mode": "rw", "driver": "local"},
            }

            # we don't use ports in 'host' network_mode.
            network_mode = "host"
            ports = {}
            if network_mode == "bridge":
                tcp_ports = cfg.get_configuration_property('tcp_ports')
                for port_range in tcp_ports:
                    for port in port_range:
                        ports[f'{port}/tcp'] = port

            #
            # k2hdkc user and group exist in docker container.
            #
            # [NOTE]
            # The '-' character cannot be used in environment variable names,
            # so it is added replaced key name with the '_' character.
            #
            user = "1001:1001"
            command = ''
            environment = overrides.copy()
            for env_key in list(overrides.keys()):
                replaced_key = env_key.replace('-', '_')
                if replaced_key != env_key:
                    environment[replaced_key] = overrides[env_key]

            # sysctls
            sysctls = {}
            if CONF.docker_container_sysctls:
                sysctls = CONF.docker_container_sysctls

            LOG.info(f"Creating docker container, image: {image}, "
                         f"volumes: {volumes}, ports: {ports}, user: {user}, "
                         f"network_mode: {network_mode}, environment: {environment}, "
                         f"command: {command}, sysctls: {sysctls}")
            try:
                docker_util.start_container(
                    self.docker_client,
                    image,
                    volumes=volumes,
                    network_mode=network_mode,
                    ports=ports,
                    user=user,
                    environment=environment,
                    command=command,
                    sysctls=sysctls
                )   
            except Exception:
                LOG.exception("Failed to start k2hdkc")
                raise exception.TroveError("Failed to start k2hdkc")

            if not self.status.wait_for_status(
                service_status.ServiceStatuses.HEALTHY,
                CONF.state_change_wait_time, False
            ):
                raise exception.TroveError("Failed to start k2hdkc")

            # Restore data from backup
            if backup_info:
                restore_location = mount_point
                # NOTE
                # original implementation calls perform_backup in the base class, but
                # we call self.app.restore_backup directly so that we can create 
                # configuration files.
                self.app.restore_backup_k2hdkc(context, restore_location, backup_info, overrides)
        else:
            LOG.info("no overrides")


    def update_overrides(self, context, overrides, remove=False):
        # pylint: disable=arguments-differ
        """trove.guestagent.datastore.manager invokes this method
        only if overrides defined.
        """
        LOG.debug("k2hdkc update_overrides %(overrides)s",
                  {'overrides': overrides})
        if remove:
            self.app.remove_overrides()
        else:
            self.app.update_overrides(context, overrides, remove)

        self._create_k2hdkc_overrides_files()

    def apply_overrides(self, context, overrides):
        """Configuration changes are made in the config YAML file and
        require restart, so this is a no-op.
        """

    def _create_k2hdkc_key_files(self, key, empty_is_changed=False):
        """Detects the key from the overrides.
        Returns true if the key exists in the overrides. false otherwise.
        Returns true if the empty_is_changed is true and the key is null.
        """
        result = False
        file_path = K2HDKC_CONFIG_PARAM_DIR + '/' + key
        value = self.app.get_value(key)

        current_param_value = None
        file_exist = False
        if os.path.isfile(file_path):
            file_exist = True
            with open(file_path, 'r') as override_param_file:
                current_param_value = override_param_file.read().replace(
                    '\n', '')
                if not current_param_value or len(current_param_value) == 0:
                    current_param_value = None

        if not value:
            if not current_param_value:
                if empty_is_changed:
                    result = True
            else:
                result = True

            # Remove file
            if file_exist:
                os.remove(file_path)

        else:
            if value != current_param_value:
                result = True

            # Update file
            with open(file_path, 'w') as override_param_file:
                override_param_file.write(str(value))

        return result

    #
    # Here, the parameters are output to a file.
    # Therefore, Docker should mount the directory of this file, so you shouldn't have to do anything!
    #
    def _create_k2hdkc_overrides_files(self):
        """puts values to files in /etc/antpickax.
        """
        is_changed = False

        if self._create_k2hdkc_key_files('cluster-name', True):
            is_changed = True

        if self._create_k2hdkc_key_files('extdata-url', True):
            is_changed = True

        if self._create_k2hdkc_key_files('chmpx-server-port', True):
            is_changed = True

        if self._create_k2hdkc_key_files('chmpx-server-ctlport', True):
            is_changed = True

        if self._create_k2hdkc_key_files('chmpx-slave-ctlport', True):
            is_changed = True

        if is_changed:
            try:
                utils.execute_with_timeout(
                    "/bin/sudo /usr/bin/systemctl restart k2hdkc-trove",
                    shell=True,
                    timeout=60)
            except exception.ProcessExecutionError:
                LOG.warning("Failed to restart k2hdkc.")

    def post_prepare(self, context, packages, databases, memory_mb, users,
                     device_path, mount_point, backup_info, config_contents,
                     root_password, overrides, cluster_config, snapshot):
        """Be invoked after successful prepare.
        """
        self.status.set_ready()

    #################
    # Service related
    #################
    def restart(self, context):
        """MUST be implemented."""
        self.status.restart_db_service(service.K2HDKC_SERVICE,
                                       self._service_status_timeout)

    def stop_db(self, context, do_not_start_on_reboot=False):
        """Stop the database server.

        This function is called at:
        https://github.com/openstack/trove/blob/master/trove/guestagent/api.py#L412
        """
        LOG.debug("do_not_start_on_reboot %(do_not_start_on_reboot)s",
                  {'do_not_start_on_reboot': do_not_start_on_reboot})

        self.app.stop_db(do_not_start_on_reboot=do_not_start_on_reboot)

    ######################
    # Backup
    ######################
    def _perform_restore(self, backup_info, context, restore_location):
        #try:
        #    backup.restore(context, backup_info, restore_location)
        #    if self.appstatus.is_running:
        #        raise RuntimeError("Cannot reset the cluster name."
        #                           "The service is still running.")
        #    self.app.stop_db()
        #except Exception as exp:
        #    LOG.error("backup_info[id] = %s.", backup_info['id'])
        #    self.app.status.set_status(ServiceStatuses.FAILED)
        #    raise exp
        LOG.info("Restored database successfully.")

    # pylint: disable=no-self-use
    def create_backup(self, context, backup_info):
        """ invokes the k2hdkc backup implementation
        """
        with EndNotification(context):
            LOG.info("EndNotification")

            volumes = {
                "/var/lib/cloud/data": {"bind": "/var/lib/cloud/data", "mode": "rw", "driver": "local"},
                "/var/lib/antpickax/k2hdkc": {"bind": "/var/lib/antpickax/k2hdkc", "mode": "rw", "driver": "local"},
            }

            extra_params = ""
            self.app.create_backup(context, backup_info,
                volumes_mapping=volumes, need_dbuser=False,
                extra_params=extra_params)

#
# Local variables:
# tab-width: 4
# c-basic-offset: 4
# End:
# vim600: expandtab sw=4 ts=4 fdm=marker
# vim<600: expandtab sw=4 ts=4
#
