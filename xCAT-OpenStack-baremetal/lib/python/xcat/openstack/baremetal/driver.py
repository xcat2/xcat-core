# vim: tabstop=4 shiftwidth=4 softtabstop=4
# coding=utf-8

"""
A driver for Bare-metal platform.
"""

from oslo.config import cfg

from nova.compute import power_state
from nova import context as nova_context
from nova import exception
from nova.openstack.common import excutils
from nova.openstack.common.gettextutils import _
from nova.openstack.common import importutils
from nova.openstack.common import jsonutils
from nova.openstack.common import log as logging
from nova.virt.baremetal import baremetal_states
from nova.virt.baremetal import db
from nova.virt.baremetal import driver as bm_driver
from nova.virt.baremetal import utils as bm_utils
from nova.virt import driver
from nova.virt import firewall
from nova.virt.libvirt import imagecache
from xcat.openstack.baremetal import xcat_driver
from xcat.openstack.baremetal import exception as xcat_exception
from xcat.openstack.baremetal import power_states


LOG = logging.getLogger(__name__)
CONF = cfg.CONF
CONF.import_opt('use_ipv6', 'nova.netconf')


class xCATBareMetalDriver(bm_driver.BareMetalDriver):
    """BareMetal hypervisor driver."""

    def __init__(self, virtapi, read_only=False):
        super(xCATBareMetalDriver, self).__init__(virtapi)
        self.xcat = xcat_driver.xCAT()

    def _get_xCAT_image_name(self, image_meta):
        prop = image_meta.get('properties')
        xcat_image_name = prop.get('xcat_image_name')
        if xcat_image_name:
            return xcat_image_name
        else:
            raise xcat_exception.xCATInvalidImageError(image=image_meta.get('name'))

    def spawn(self, context, instance, image_meta, injected_files,
              admin_password, network_info=None, block_device_info=None):
        """
        Create a new instance/VM/domain on the virtualization platform.

        Once this successfully completes, the instance should be
        running (power_state.RUNNING).

        If this fails, any partial instance should be completely
        cleaned up, and the virtualization platform should be in the state
        that it was before this call began.

        :param context: security context
        :param instance: Instance object as returned by DB layer.
                         This function should use the data there to guide
                         the creation of the new instance.
        :param image_meta: image object returned by nova.image.glance that
                           defines the image from which to boot this instance
        :param injected_files: User files to inject into instance.
        :param admin_password: Administrator password to set in instance.
        :param network_info:
           :py:meth:`~nova.network.manager.NetworkManager.get_instance_nw_info`
        :param block_device_info: Information about block devices to be
                                  attached to the instance.
        """
 	import pdb
	pdb.set_trace()
        node_uuid = self._require_node(instance)
        node = db.bm_node_associate_and_update(context, node_uuid,
                    {'instance_uuid': instance['uuid'],
                     'instance_name': instance['hostname'],
                     'task_state': baremetal_states.BUILDING})

        try:
            self._plug_vifs(instance, network_info, context=context)
            self._attach_block_devices(instance, block_device_info)
            self._start_firewall(instance, network_info)

            macs = self.macs_for_instance(instance)
            nodename = self.xcat.get_xcat_node_name(macs)
            imagename = self._get_xCAT_image_name(image_meta)
            hostname = instance.get('hostname')
            
            #get the network information for the new node
            interfaces = bm_utils.map_network_interfaces(network_info, CONF.use_ipv6)
            if CONF.use_ipv6:
                fixed_ip = interfaces[0].get('address_v6')
                netmask = interfaces[0].get('netmask_v6')
                gateway = interfaces[0].get('gateway_v6')
            else:
                fixed_ip = interfaces[0].get('address')
                netmask = interfaces[0].get('netmask')
                gateway = interfaces[0].get('gateway')
            #convert netmask from IPAddress to unicode string
            if netmask:
                netmask = unicode(netmask)

            #let xCAT install it
            bm_driver._update_state(context, node, instance, baremetal_states.DEPLOYING)
            self.xcat.deploy_node(nodename, imagename, hostname, fixed_ip, netmask, gateway)
            bm_driver._update_state(context, node, instance, baremetal_states.ACTIVE)
        except Exception as e: 
            with excutils.save_and_reraise_exception():
                LOG.error(_("Error occured while deploying instance %(instance)s "
                            "on baremetal node %(node)s: %(error)s") %
                          {'instance': instance['uuid'],
                           'node': node['uuid'],
                           'error':str(e)})
                bm_driver._update_state(context, node, instance, baremetal_states.ERROR)

    def reboot(self, context, instance, network_info, reboot_type,
               block_device_info=None, bad_volumes_callback=None):
        """Reboot the specified instance.

        After this is called successfully, the instance's state
        goes back to power_state.RUNNING. The virtualization
        platform should ensure that the reboot action has completed
        successfully even in cases in which the underlying domain/vm
        is paused or halted/stopped.

        :param instance: Instance object as returned by DB layer.
        :param network_info:
           :py:meth:`~nova.network.manager.NetworkManager.get_instance_nw_info`
        :param reboot_type: Either a HARD or SOFT reboot
        :param block_device_info: Info pertaining to attached volumes
        :param bad_volumes_callback: Function to handle any bad volumes
            encountered
        """
        try: 
            node = bm_driver._get_baremetal_node_by_instance_uuid(instance['uuid'])
            macs = self.macs_for_instance(instance)
            nodename = self.xcat.get_xcat_node_name(macs)
            self.xcat.reboot_node(nodename)
            bm_driver._update_state(context, node, instance, baremetal_states.RUNNING)
        except xcat_exception.xCATCommandError as e: 
            with excutils.save_and_reraise_exception():
                LOG.error(_("Error occured while rebooting instance %(instance)s "
                            "on baremetal node %(node)s: %(error)s") %
                            {'instance': instance['uuid'],
                             'node': node['uuid'],
                             'error':str(e)})
                bm_driver._update_state(context, node, instance, baremetal_states.ERROR)

    def destroy(self, context, instance, network_info, block_device_info=None,
                destroy_disks=True):
        """Destroy (shutdown and delete) the specified instance.

        If the instance is not found (for example if networking failed), this
        function should still succeed.  It's probably a good idea to log a
        warning in that case.

        :param context: security context
        :param instance: Instance object as returned by DB layer.
        :param network_info:
           :py:meth:`~nova.network.manager.NetworkManager.get_instance_nw_info`
        :param block_device_info: Information about block devices that should
                                  be detached from the instance.
        :param destroy_disks: Indicates if disks should be destroyed
        """
 	#import pdb
	#pdb.set_trace()
        try:
            node = bm_driver._get_baremetal_node_by_instance_uuid(instance['uuid'])
            
        except exception.InstanceNotFound:
            LOG.warning(_("Destroy function called on a non-existing instance %s")
                        % instance['uuid'])
            return

        try:
            macs = self.macs_for_instance(instance)
            nodename = self.xcat.get_xcat_node_name(macs)
            interfaces = bm_utils.map_network_interfaces(network_info, CONF.use_ipv6)
            fixed_ip=None
            if interfaces and interfaces[0]: 
                if CONF.use_ipv6:
                    fixed_ip = interfaces[0].get('address_v6')
                else:
                    fixed_ip = interfaces[0].get('address')
            if fixed_ip:
                self.xcat.cleanup_node(nodename, fixed_ip)
            else:
                self.xcat.cleanup_node(nodename)
        except Exception as e:
            #just log it and move on
            LOG.warning(_("Destroy called with xCAT error:" + str(e)))

        try:
            self._detach_block_devices(instance, block_device_info)
            self._stop_firewall(instance, network_info)
            self._unplug_vifs(instance, network_info)
            
            bm_driver._update_state(context, node, None, baremetal_states.DELETED)
        except Exception as e:
            with excutils.save_and_reraise_exception():
                LOG.error(_("Error occurred while destroying instance %s: %s") 
                          % (instance['uuid'], str(e)))
                bm_driver._update_state(context, node, instance,
                                        baremetal_states.ERROR)

    def power_off(self, instance, node=None):
        """Power off the specified instance."""
        macs = self.macs_for_instance(instance)
        nodename = self.xcat.get_xcat_node_name(macs)
        self.xcat.power_off_node(nodename)
            

    def power_on(self, context, instance, network_info, block_device_info=None,
                 node=None):
        """Power on the specified instance."""
        macs = self.macs_for_instance(instance)
        nodename = self.xcat.get_xcat_node_name(macs)
        self.xcat.power_on_node(nodename)


    def get_console_output(self, instance):
        pass

    def get_info(self, instance):
        """Get the current status of an instance, by name (not ID!)

        Returns a dict containing:
        :state:           the running state, one of the power_state codes
        :max_mem:         (int) the maximum memory in KBytes allowed
        :mem:             (int) the memory in KBytes used by the domain
        :num_cpu:         (int) the number of virtual CPUs for the domain
        :cpu_time:        (int) the CPU time used in nanoseconds
        """

        node = bm_driver._get_baremetal_node_by_instance_uuid(instance['uuid'])
        macs = self.macs_for_instance(instance)
        nodename = self.xcat.get_xcat_node_name(macs)

        ps = self.xcat.get_node_power_state(nodename)
        if ps == power_states.ON:
            pstate = power_state.RUNNING
        elif ps == power_states.OFF:
            pstate = power_state.SHUTDOWN
        else:
            pstate = power_state.NOSTATE

        return {'state': pstate,
                'max_mem': node['memory_mb'],
                'mem': node['memory_mb'],
                'num_cpu': node['cpus'],
                'cpu_time': 0}
