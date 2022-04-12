#!/usr/bin/env python3
###############################################################################
# IBM(c) 2018 EPL license http://www.eclipse.org/legal/epl-v10.html
###############################################################################
# -*- coding: utf-8 -*-
#

class InventoryInterface(object):
    """Interface for inventory-related actions."""
    interface_type = 'inventory'
    version = '1.0'

    def get_inventory_info(self, task, inventory_type=[]):
        """Return the inventory info of the task's nodes.

        :param inventory_type: array of type of inventory info want to get.
        :param task: a Task instance containing the nodes to act on.
        :return inventory info list
        """
        return task.run('get_info', inventory_type)

    def get_firm_info(self, task, target_arg=None):
        """Return the firm info of the task's nodes.

        :param task: a Task instance containing the nodes to act on.
        :param check_arg: firmware file to check, for rflash check
        :return firm info list
        """
        return task.run('get_firm_info', target_arg)

class DefaultInventoryManager(InventoryInterface):
    """Interface for inventory-related actions."""
    pass
