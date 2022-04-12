#!/usr/bin/env python3
###############################################################################
# IBM(c) 2018 EPL license http://www.eclipse.org/legal/epl-v10.html
###############################################################################
# -*- coding: utf-8 -*-
#

class FlashInterface(object):
    """Interface for flash-related actions."""
    interface_type = 'flash'
    version = '1.0'

    def activate_firm(self, task, activate_arg):
        """Activate firmware.

        :param task: a Task instance containing the nodes to act on.
        :activate_arg: arg for activate
        """
        return task.run('activate_firm', activate_arg)

    def delete_firm(self, task, delete_id):
        """Delete firmware.

        :param task: a Task instance containing the nodes to act on.
        :param delete_id: firmware id want to delete
        """
        return task.run('delete_firm', delete_id)

    def flash_process(self, task, directory, no_host_reboot):
        """Upload and activate firmware

        :param task: a Task instance containing the nodes to act on.
        :directory: firmware directory
        """
        return task.run('flash_process', directory, no_host_reboot)

    def list_firm_info(self, task):
        """List firmware

        :param task: a Task instance containing the nodes to act on.
        """
        return task.run('list_firm_info')

    def upload_firm(self, task, upload_file):
        """Upload firmware file.

        :param task: a Task instance containing the nodes to act on.
        :param upload_file: the file want to upload
        """
        return task.run('upload_firm', upload_file)

class DefaultFlashManager(FlashInterface):
    """Interface for flash-related actions."""
    pass
