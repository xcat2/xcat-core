"""
pxe procedure for the xcat baremetal driver
use xcat to config dhcp and tftp
"""

import os
import time
import paramiko
import datetime
from oslo.config import cfg
from ironic.common import exception
from ironic.common import image_service as service
from ironic.common import keystone
from ironic.common import states
from ironic.common import utils
from ironic.conductor import task_manager
from ironic.conductor import utils as manager_utils
from ironic.drivers import base
from ironic.drivers import utils as driver_utils
from ironic.openstack.common import log as logging
from ironic.openstack.common import strutils
from ironic.drivers.modules import xcat_neutron
from ironic.drivers.modules import xcat_util
from ironic.openstack.common import loopingcall
from nova.openstack.common import timeutils
from ironic.openstack.common import lockutils
from ironic.drivers.modules import xcat_exception


pxe_opts = [
    cfg.StrOpt('pxe_append_params',
               default='nofb nomodeset vga=normal',
               help='Additional append parameters for baremetal PXE boot.'),
    cfg.StrOpt('default_ephemeral_format',
               default='ext4',
               help='Default file system format for ephemeral partition, '
                    'if one is created.'),
    ]
xcat_opts = [
    cfg.StrOpt('network_node_ip',
               default='127.0.0.1',
               help='IP address of neutron network node'),
    cfg.StrOpt('ssh_user',
               default='root',
               help='Username of neutron network node.'),
    cfg.StrOpt('ssh_password',
               default='cluster',
               help='Password of neutron network node'),
    cfg.IntOpt('ssh_port',
               default=22,
               help='ssh connection port for the neutron '),
    cfg.StrOpt('host_filepath',
               default='/etc/hosts',
               help='host file of server'),
    cfg.IntOpt('deploy_timeout',
               default=3600,
               help='max depolyment time(seconds) for the xcat driver'),
    cfg.IntOpt('deploy_checking_interval',
               default=30,
               help='interval time(seconds) to check the xcat deploy state'),
    ]

LOG = logging.getLogger(__name__)

CONF = cfg.CONF
CONF.register_opts(pxe_opts, group='pxe')
CONF.register_opts(xcat_opts, group='xcat')
CONF.import_opt('use_ipv6', 'ironic.netconf')

REQUIRED_PROPERTIES = {
    'pxe_deploy_kernel': _("UUID (from Glance) of the deployment kernel. "
                           "Required."),
    'pxe_deploy_ramdisk': _("UUID (from Glance) of the ramdisk that is "
                            "mounted at boot time. Required."),
}
COMMON_PROPERTIES = REQUIRED_PROPERTIES
EM_SEMAPHORE = 'xcat_pxe'

def _check_for_missing_params(info_dict, param_prefix=''):
    missing_info = []
    for label, value in info_dict.items():
        if not value:
            missing_info.append(param_prefix + label)

    if missing_info:
        raise exception.InvalidParameterValue(_(
                "Can not validate PXE bootloader. The following parameters "
                "were not passed to ironic: %s") % missing_info)

def _parse_driver_info(node):
    """Gets the driver specific Node deployment info.

    This method validates whether the 'driver_info' property of the
    supplied node contains the required information for this driver to
    deploy images to the node.

    :param node: a single Node.
    :returns: A dict with the driver_info values.
    """
    info = node.driver_info
    d_info = {}
    d_info['xcat_node'] = info.get('xcat_node')
    return d_info

def _parse_instance_info(node):
    """Gets the instance specific Node deployment info.

    This method validates whether the 'instance_info' property of the
    supplied node contains the required information for this driver to
    deploy images to the node.

    :param node: a single Node.
    :returns: A dict with the instance_info values.
    """

    info = node.instance_info
    i_info = {}
    i_info['image_source'] = info.get('image_source')
    i_info['root_gb'] = info.get('root_gb')
    i_info['image_file'] = i_info['image_source']

    _check_for_missing_params(i_info)

    # Internal use only
    i_info['deploy_key'] = info.get('deploy_key')

    i_info['swap_mb'] = info.get('swap_mb', 0)
    i_info['ephemeral_gb'] = info.get('ephemeral_gb', 0)
    i_info['ephemeral_format'] = info.get('ephemeral_format')

    err_msg_invalid = _("Can not validate PXE bootloader. Invalid parameter "
                        "%(param)s. Reason: %(reason)s")
    for param in ('root_gb', 'swap_mb', 'ephemeral_gb'):
        try:
            int(i_info[param])
        except ValueError:
            reason = _("'%s' is not an integer value.") % i_info[param]
            raise exception.InvalidParameterValue(err_msg_invalid %
                                            {'param': param, 'reason': reason})

    if i_info['ephemeral_gb'] and not i_info['ephemeral_format']:
        i_info['ephemeral_format'] = CONF.pxe.default_ephemeral_format

    preserve_ephemeral = info.get('preserve_ephemeral', False)
    try:
        i_info['preserve_ephemeral'] = strutils.bool_from_string(
                                            preserve_ephemeral, strict=True)
    except ValueError as e:
        raise exception.InvalidParameterValue(err_msg_invalid %
                                  {'param': 'preserve_ephemeral', 'reason': e})
    return i_info


def _parse_deploy_info(node):
    """Gets the instance and driver specific Node deployment info.

    This method validates whether the 'instance_info' and 'driver_info'
    property of the supplied node contains the required information for
    this driver to deploy images to the node.

    :param node: a single Node.
    :returns: A dict with the instance_info and driver_info values.
    """
    info = {}
    info.update(_parse_instance_info(node))
    info.update(_parse_driver_info(node))
    return info

def _validate_glance_image(ctx, deploy_info):
    """Validate the image in Glance.

    Check if the image exist in Glance and if it contains the
    'kernel_id' and 'ramdisk_id' properties.

    :raises: InvalidParameterValue.
    """
    image_id = deploy_info['image_source']
    if not image_id:
        raise exception.ImageNotFound

class PXEDeploy(base.DeployInterface):
    """PXE Deploy Interface: just a stub until the real driver is ported."""
    def get_properties(self):
        return COMMON_PROPERTIES

    def validate(self, task):
        """Validate the deployment information for the task's node.

        :param task: a TaskManager instance containing the node to act on.
        :raises: InvalidParameterValue.
        """
        node = task.node
        if not driver_utils.get_node_mac_addresses(task):
            raise exception.InvalidParameterValue(_("Node %s does not have "
                                "any port associated with it.") % node.uuid)

        d_info = _parse_deploy_info(node)
        # Try to get the URL of the Ironic API
        try:
            # TODO(lucasagomes): Validate the format of the URL
            CONF.conductor.api_url or keystone.get_service_url()
        except (exception.CatalogFailure,
                exception.CatalogNotFound,
                exception.CatalogUnauthorized):
            raise exception.InvalidParameterValue(_(
                "Couldn't get the URL of the Ironic API service from the "
                "configuration file or keystone catalog."))

        _validate_glance_image(task.context, d_info)

    @task_manager.require_exclusive_lock
    def deploy(self, task):
        """Start deployment of the task's node'.

        Config host file and xcat dhcp, generate image info for xcat
        and issues a  reboot request to the power driver.
        This causes the node to boot into the deployment ramdisk and triggers
        the next phase of PXE-based deployment via
        VendorPassthru._continue_deploy().

        :param task: a TaskManager instance containing the node to act on.
        :returns: deploy state DEPLOYDONE.
        """

        d_info = _parse_deploy_info(task.node)
        if not task.node.instance_info.get('fixed_ip_address') or not task.node.instance_info.get('image_name'):
            raise exception.InvalidParameterValue
        self._config_host_file(d_info,task.node.instance_info.get('fixed_ip_address'))
        self._make_dhcp()
        self._nodeset_osimage(d_info,task.node.instance_info.get('image_name'))
        manager_utils.node_set_boot_device(task, 'pxe', persistent=True)
        manager_utils.node_power_action(task, states.REBOOT)
        try:
            self._wait_for_node_deploy(task)
        except xcat_exception.xCATDeploymentFailure:
            LOG.info(_("xcat deployment failed"))
            return states.ERROR

        return states.DEPLOYDONE

    @task_manager.require_exclusive_lock
    def tear_down(self, task):
        """Tear down a previous deployment on the task's node.

        Power off the node. All actual clean-up is done in the clean_up()
        method which should be called separately.

        :param task: a TaskManager instance containing the node to act on.
        :returns: deploy state DELETED.
        """
        manager_utils.node_power_action(task, states.POWER_OFF)
        return states.DELETED

    def prepare(self, task):
        """Prepare the deployment environment for this task's node.
        Get the image info from glance, config the mac for the xcat
        use ssh and iptables to disable dhcp on network node
        :param task: a TaskManager instance containing the node to act on.
        """
        # TODO(deva): optimize this if rerun on existing files
        d_info = _parse_deploy_info(task.node)
        i_info = task.node.instance_info
        image_id = d_info['image_source']
        try:
            glance_service = service.Service(version=1, context=task.context)
            image_name = glance_service.show(image_id)['name']
            i_info['image_name'] = image_name
        except (exception.GlanceConnectionFailed,
                exception.ImageNotAuthorized,
                exception.Invalid):
            LOG.warning(_("Failed to connect to Glance to get the properties "
                "of the image %s") % image_id)

        node_mac_addresses = driver_utils.get_node_mac_addresses(task)
        vif_ports_info = xcat_neutron.get_ports_info_from_neutron(task)
        try:
            network_info = self._get_deploy_network_info(vif_ports_info, node_mac_addresses)
        except (xcat_exception.GetNetworkFixedIPFailure,xcat_exception.GetNetworkIdFailure):
            LOG.error(_("Failed to get network info"))
            return
        if not network_info:
            LOG.error(_("Failed to get network info"))
            return

        fixed_ip_address = network_info['fixed_ip_address']
        deploy_mac_address = network_info['mac_address']
        network_id = network_info['network_id']

        i_info['fixed_ip_address'] = fixed_ip_address
        i_info['network_id'] = network_id
        i_info['deploy_mac_address'] = deploy_mac_address

        # use iptables to drop the dhcp mac of baremetal machine
        self._ssh_append_dhcp_rule(CONF.xcat.network_node_ip,CONF.xcat.ssh_port,CONF.xcat.ssh_user,
                                     CONF.xcat.ssh_password,network_id,deploy_mac_address)
        self._chdef_node_mac_address(d_info,deploy_mac_address)

    def clean_up(self, task):
        """Clean up the deployment environment for the task's node.

        Unlinks TFTP and instance images and triggers image cache cleanup.
        Removes the TFTP configuration files for this node. As a precaution,
        this method also ensures the keystone auth token file was removed.

        :param task: a TaskManager instance containing the node to act on.
        """
        pass

    def take_over(self, task):
        pass

    def _get_deploy_network_info(self, vif_ports_info, valid_node_mac_addrsses):
        """Get network info from mac address of ironic node.
        :param vif_ports_info: info collection from neutron ports
        :param valid_node_mac_addrsses: mac address from ironic node
        :raises: GetNetworkFixedIpFailure if search the fixed ip from mac address failure
        :raises: GetNetworkIdFailure if search the network id from mac address failure
        """
        network_info = {}
        for port_info in vif_ports_info.values():
            if(port_info['port']['mac_address'] in valid_node_mac_addrsses ):
                network_info['fixed_ip_address'] = port_info['port']['fixed_ips'][0]['ip_address']
                if not network_info['fixed_ip_address']:
                    raise xcat_exception.GetNetworkFixedIPFailure(mac_address=port_info['port']['mac_address'])
                network_info['mac_address'] = port_info['port']['mac_address']
                network_info['network_id'] = port_info['port']['network_id']
                if not network_info['network_id']:
                    raise xcat_exception.GetNetworkIdFailure(mac_address=port_info['port']['mac_address'])
                network_info['port_id'] = port_info['port']['id']
                return network_info
        return network_info

    def _chdef_node_mac_address(self, driver_info, deploy_mac):
        """ run chdef command to set mac address"""
        cmd = 'chdef'
        args = 'mac='+ deploy_mac
        try:
            out_err = xcat_util.exec_xcatcmd(driver_info, cmd, args)
            LOG.info(_("xcat chdef cmd exetute output: %(out_err)s") % {'out_err':out_err})
        except xcat_exception.xCATCmdFailure as e:
            LOG.warning(_("xcat chdef failed for node %(xcat_node)s with "
                        "error: %(error)s.")
                        % {'xcat_node': driver_info['xcat_node'], 'error': e})
            raise exception.IPMIFailure(cmd=cmd)

    @lockutils.synchronized(EM_SEMAPHORE, 'xcat-hosts-')
    def _config_host_file(self, driver_info, deploy_ip):
        """ append node and ip infomation to host file"""
        with open(CONF.xcat.host_filepath,"r+") as f:
            lines = []
            for line in f:
                temp = line.split('#')
                if temp[0].strip():
                    host_name = xcat_util._tsplit(temp[0].strip(),(' ','\t'))[1]
                    if driver_info['xcat_node'] not in host_name:
                        lines.append(line)

            # append a new line to host file
            line = "%s\t%s\n" %(deploy_ip,driver_info['xcat_node'])
            lines.append(line)
            f.seek(0)
            f.truncate()
            for line in lines:
                f.write(line)

    def _nodeset_osimage(self, driver_info, image_name):
        """run nodeset command to config the image for the xcat node
        :param driver_info: xcat node deploy info
        :param image_name: image for the xcat deployment
        """
        cmd = 'nodeset'
        args = 'osimage='+ image_name
        try:
            xcat_util.exec_xcatcmd(driver_info, cmd, args)
        except xcat_exception.xCATCmdFailure as e:
            LOG.warning(_("xcat nodeset failed for node %(xcat_node)s with "
                        "error: %(error)s.")
                        % {'xcat_node': driver_info['xcat_node'], 'error': e})

    def _make_dhcp(self):
        """run makedhcp command to setup dhcp environment for the xcat node"""
        cmd = ['makedhcp',
            '-n'
            ]
        try:
            out, err = utils.execute(*cmd)
            LOG.info(_(" excute cmd: %(cmd)s \n output: %(out)s \n. Error: %(err)s \n"),
                      {'cmd':cmd,'out': out, 'err': err})
        except Exception as e:
            LOG.error(_("Unable to execute %(cmd)s. Exception: %(exception)s"),
                      {'cmd': cmd, 'exception': e})
        # makedhcp -a
        cmd = ['makedhcp',
            '-a'
            ]
        try:
            out, err = utils.execute(*cmd)
            LOG.info(_(" excute cmd: %(cmd)s \n output: %(out)s \n. Error: %(err)s \n"),
                      {'cmd':cmd,'out': out, 'err': err})
        except Exception as e:
            LOG.error(_("Unable to execute %(cmd)s. Exception: %(exception)s"),
                      {'cmd': cmd, 'exception': e})

    def _ssh_append_dhcp_rule(self,ip,port,username,password,network_id,mac_address):
        """ drop the dhcp package in network node to avoid of confilct of dhcp """
        netns = 'qdhcp-%s' %network_id
        append_cmd = 'sudo ip netns exec %s iptables -A INPUT -m mac --mac-source %s -j DROP' % \
               (netns,mac_address)
        cmd = [append_cmd]
        xcat_util.xcat_ssh(ip,port,username,password,cmd)

    def _ssh_delete_dhcp_rule(self,ip,port,username,password,network_id,mac_address):
        """ delete the iptable rule on network node to recover the environment"""
        netns = 'qdhcp-%s' %network_id
        cancel_cmd = 'sudo ip netns exec %s iptables -D INPUT -m mac --mac-source %s -j DROP' % \
               (netns,mac_address)
        cmd = [cancel_cmd]
        xcat_util.xcat_ssh(ip,port,username,password,cmd)

    def _wait_for_node_deploy(self, task):
        """Wait for xCAT node deployment to complete."""
        locals = {'errstr':''}
        driver_info = _parse_deploy_info(task.node)
        node_mac_addrsses = driver_utils.get_node_mac_addresses(task)
        i_info = task.node.instance_info

        def _wait_for_deploy():
            out,err = xcat_util.exec_xcatcmd(driver_info,'nodels','nodelist.status')
            if err:
                locals['errstr'] = _("Error returned when quering node status"
                           " for node %s:%s") % (driver_info['xcat_node'], err)
                LOG.warning(locals['errstr'])
                raise loopingcall.LoopingCallDone()

            if out:
                node,status = out.split(": ")
                status = status.strip()
                if status == "booted":
                    LOG.info(_("Deployment for node %s completed.")
                             % driver_info['xcat_node'])
                    raise loopingcall.LoopingCallDone()

            if (CONF.xcat.deploy_timeout and
                    timeutils.utcnow() > expiration):
                locals['errstr'] = _("Timeout while waiting for"
                           " deployment of node %s.") % driver_info['xcat_node']
                LOG.warning(locals['errstr'])
                raise loopingcall.LoopingCallDone()

        expiration = timeutils.utcnow() + datetime.timedelta(
                seconds=CONF.xcat.deploy_timeout)
        timer = loopingcall.FixedIntervalLoopingCall(_wait_for_deploy)
        # default check every 10 seconds
        timer.start(interval=CONF.xcat.deploy_checking_interval).wait()

        if locals['errstr']:
            raise xcat_exception.xCATDeploymentFailure(locals['errstr'])
        # deploy end, delete the dhcp rule for xcat
        self._ssh_delete_dhcp_rule(CONF.xcat.network_node_ip,CONF.xcat.ssh_port,CONF.xcat.ssh_user,
                                     CONF.xcat.ssh_password,i_info['network_id'],node_mac_addrsses[0])


