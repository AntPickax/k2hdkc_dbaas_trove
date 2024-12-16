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
# AUTHOR:   Hirotaka Wakabayashi
# CREATE:   Tue, Mar 7 2024
# REVISION:
#
from backup.drivers import base
from oslo_log import log as logging
import subprocess
import shlex

LOG = logging.getLogger(__name__)
BACKUP_COMMAND = "/usr/libexec/k2hdkctrove.sh"
SNAPSHOT_NAME = "trovebackup"

class K2hdkcBackup(base.BaseRunner):
    """Backup and Restore Implementation"""
    def __init__(self, *args, **kwargs):
        LOG.info("args:{} kwargs:{}".format(args, kwargs))
        self.datadir = kwargs.pop('db-datadir', '/var/lib/antpickax/k2hdkc')
        super(K2hdkcBackup, self).__init__(*args, **kwargs)
        self.restore_command = '/bin/tar xzpPf - -C /'
        self.backup_log = '/var/log/antpickax/k2hdkcbackup.log'
        self._gzip = True
        self.timeout = 60

    @property
    def cmd(self):
        cmd = (f"/bin/tar -zcpPf - {self.datadir}/snapshots/trovebackup")
        return cmd + self.encrypt_cmd

    def _run_command(self, command, timeout):
        if not command:
            return False
        command_args = shlex.split(command)
        LOG.info("command_args:{} timeout:{}".format(command_args, timeout))
        # Create new Popen instance.
        proc = subprocess.Popen(
                command_args,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE)
        with proc:
            # communicate() returns a tuple (stdout_data, stderr_data)
            try:
                stdout, stderr = proc.communicate(input=None, timeout=timeout)
                LOG.info("stdout:{} stderr:{}".format(stdout.decode(), stderr.decode()))
                LOG.info("proc.pid:{} proc.returncode:{}".format(proc.pid, proc.returncode))
                print("True")
            except TimeoutExpired:
                proc.kill()
                _, stderr = proc.communicate()
                LOG.error("TimeoutExpired stderr:{}".format(stderr.decode()))
            return False
        LOG.info("True")   # code doesn't come here. why???
        return True

    """pre_backup"""
    def pre_backup(self):
        LOG.info("pre_backup")
        command = '{} backup {} {}'.format(BACKUP_COMMAND, self.datadir, SNAPSHOT_NAME)
        self._run_command(command, self.timeout)

    """post_backup"""
    def post_backup(self):
        LOG.info("post_backup")
        command = '{} delete {} {}'.format(BACKUP_COMMAND, self.datadir, SNAPSHOT_NAME)
        self._run_command(command, self.timeout)

    """post_restore"""
    def post_restore(self):
        LOG.info("post_restore")
        command = '{} restore {} {}'.format(BACKUP_COMMAND, self.datadir, SNAPSHOT_NAME)
        self._run_command(command, self.timeout)

    def check_process(self):
        return True

#
# Local variables:
# tab-width: 4
# c-basic-offset: 4
# End:
# vim600: expandtab sw=4 ts=4 fdm=marker
# vim<600: expandtab sw=4 ts=4
#
