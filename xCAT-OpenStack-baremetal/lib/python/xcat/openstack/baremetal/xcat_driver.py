# vim: tabstop=4 shiftwidth=4 softtabstop=4
# coding=utf-8


"""
Baremetal xCAT power manager.
"""

import os
import sys
import stat
from oslo.config import cfg
import datetime

from nova import context as nova_context
from nova.virt.baremetal import baremetal_states
from nova.openstack.common.gettextutils import _
from nova.openstack.common import log as logging
from nova.openstack.common import loopingcall
from nova.openstack.common import timeutils
from nova import paths
from nova import utils
from xcat.openstack.baremetal import exception
from xcat.openstack.baremetal import power_states

LOG = logging.getLogger(__name__)

# register configuration options
xcat_opts = [
    cfg.IntOpt('deploy_timeout',
                help='Timeout for node deployment. Default: 0 second (unlimited)',
                default=0),
    cfg.IntOpt('reboot_timeout',
                help='Timeout for rebooting a node. Default: 0 second (unlimited)',
                default=0),    
    cfg.IntOpt('deploy_checking_interval',
                help='Checking interval for node deployment. Default: 10 seconds',
                default=10),
    cfg.IntOpt('reboot_checking_interval',
                help='Checking interval for rebooting a node. Default: 5 seconds',
                default=5),    
   ]
xcat_group = cfg.OptGroup(name='xcat',
                          title='xCAT Options')
CONF = cfg.CONF
CONF.register_group(xcat_group)
CONF.register_opts(xcat_opts, xcat_group)


class xCAT(object):
    """A driver that calls xCAT funcions"""

    def __init__(self):
        #setup the path for xCAT commands
        #xcatroot = os.getenv('XCATROOT', '/opt/xcat/')
        #sys.path.append("%s/bin" % xcatroot)
        #sys.path.append("%s/sbin" % xcatroot)
        pass

    def _exec_xcat_command(self, command):
        """Calls xCAT command."""
        args = command.split(" ")
        out, err = utils.execute(*args, run_as_root=True)
        LOG.debug(_("xCAT command stdout: '%(out)s', stderr: '%(err)s'"),
                  {'out': out, 'err': err})
        return out, err

    def get_xcat_node_name(self, macs):
        """Get the xcat node name given mac addressed.

        It uses the mac address to search for the node name in xCAT.
        """
        for mac in macs:
            out, err = self._exec_xcat_command("lsdef -w mac=%s" % mac)
            if out:
                return out.split(" ")[0]
        
        errstr='No node found in xCAT with the following mac address: ' \
            + ','.join(macs)
        LOG.warning(errstr)
        raise exception.xCATCommandError(errstr)

        
    def deploy_node(self, nodename, imagename, hostname, fixed_ip, netmask, gateway):
        """
        Install the node.

        It calls xCAT command deploy_ops_bmnode which prepares the node
        by adding the config_ops_bm_node postbootscript to the postscript
        table for the node, then call nodeset and then boot the node up.
        """
        out, err = self._exec_xcat_command(
            "deploy_ops_bm_node %(node)s --image %(image)s"
            " --host %(host)s --ip %(ip)s --mask %(mask)s" 
            % {'node': nodename,
               'image': imagename,
               'host': hostname,
               'ip': fixed_ip,
               'mask': netmask,
            })
        if err:
            errstr = _("Error returned when calling xCAT deploy_ops_bm_node"
                       " command for node %s:%s") % (nodename, err)
            LOG.warning(errstr)
            raise exception.xCATCommandError(errstr)
        self._wait_for_node_deploy(nodename)

    def cleanup_node(self, nodename, fixed_ip=None):
        """
        Undo all the changes made to the node by deploy_node function.

        It calls xCAT command cleanup_ops_bm_node which removes the
        config_ops_bm_node postbootscript from the postscript table
        for the node, removes the alias ip and then power the node off.
        """
        cmd = "cleanup_ops_bm_node %s" % nodename
        if fixed_ip:
            cmd += " --ip %s" % fixed_ip
        out, err = self._exec_xcat_command(cmd)

        if err:
            errstr = _("Error returned when calling xCAT cleanup_ops_bm_node"
                       " command for node %s:%s") % (nodename, err)
            LOG.warning(errstr)
            raise exception.xCATCommandError(errstr)

    def power_on_node(self, nodename):
        """Power on the node."""
        state = self.get_node_power_state(nodename)
        if state ==  power_states.ON:
            LOG.warning(_("Powring on node called, but the node %s "
                          "is already on") % nodename)
        out, err = self._exec_xcat_command("rpower %s on" % nodename)
        if err:
            errstr = _("Error returned when calling xCAT rpower on"
                    " for node %s:%s") % (nodename, err)
            LOG.warning(errstr)
            raise exception.xCATCommandError(errstr)
        else:
            self._wait_for_node_reboot(nodename)
            return power_states.ON
    
    def power_off_node(self, nodename):
        """Power off the node."""
        state = self.get_node_power_state(nodename)
        if state ==  power_states.OFF:
            LOG.warning(_("Powring off node called, but the node %s "
                          "is already off") % nodename)
        out, err = self._exec_xcat_command("rpower %s off" % nodename)
        if err:
            errstr = _("Error returned when calling xCAT rpower off"
                    " for node %s:%s") % (nodename, err)
            LOG.warning(errstr)
            raise exception.xCATCommandError(errstr)
        else:
            return power_states.OFF

    def reboot_node(self, nodename):
        """Reboot the node."""
        out, err = self._exec_xcat_command("rpower %s boot" % nodename)
        if err:
            errstr = _("Error returned when calling xCAT rpower boot"
                    " for node %s:%s") % (nodename, err)
            LOG.warning(errstr)
            raise exception.xCATCommandError(errstr)
        
        self._wait_for_node_reboot(nodename)
        return power_states.ON
        

    def get_node_power_state(self, nodename):
        out, err = self._exec_xcat_command("rpower %s stat" % nodename)
        if err:
            errstr = _("Error returned when calling xCAT rpower stat"
                    " for node %s:%s") % (nodename, err)
            LOG.warning(errstr)
            raise exception.xCATCommandError(errstr)
        else:
            state = out.split(":")[1]
            if state:
                state = state.strip()
                if state == 'on':
                    return power_states.ON
                elif state == 'off':
                    return power_states.OFF
            
            return power_states.ERROR
            
    def _wait_for_node_deploy(self, nodename):
        """Wait for xCAT node deployment to complete."""
        locals = {'errstr':''}

        def _wait_for_deploy():
            out,err = self._exec_xcat_command("nodels %s nodelist.status" % nodename)
            if err:
                locals['errstr'] = _("Error returned when quering node status"
                           " for node %s:%s") % (nodename, err)
                LOG.warning(locals['errstr'])
                raise loopingcall.LoopingCallDone()

            if out:
                node,status = out.split(": ")
                status = status.strip()
                if status == "booted":
                    LOG.info(_("Deployment for node %s completed.")
                             % nodename)
                    raise loopingcall.LoopingCallDone()

            if (CONF.xcat.deploy_timeout and
                    timeutils.utcnow() > expiration):
                locals['errstr'] = _("Timeout while waiting for"
                           " deployment of node %s.") % nodename
                LOG.warning(locals['errstr'])
                raise loopingcall.LoopingCallDone()

        expiration = timeutils.utcnow() + datetime.timedelta(
                seconds=CONF.xcat.deploy_timeout)
        timer = loopingcall.FixedIntervalLoopingCall(_wait_for_deploy)
        # default check every 10 seconds
        timer.start(interval=CONF.xcat.deploy_checking_interval).wait()

        if locals['errstr']:
            raise exception.xCATDeploymentFailure(locals['errstr'])


    def _wait_for_node_reboot(self, nodename):
        """Wait for xCAT node boot to complete."""
        locals = {'errstr':''}

        def _wait_for_reboot():
            out,err = self._exec_xcat_command("nodestat %s" % nodename)
            if err:
                locals['errstr'] = _("Error returned when quering node status"
                           " for node %s:%s") % (nodename, err)
                LOG.warning(locals['errstr'])
                raise loopingcall.LoopingCallDone()

            if out:
                node,status = out.split(": ")
                status = status.strip()
                if status == "sshd":
                    LOG.info(_("Rebooting node %s completed.")
                             % nodename)
                    raise loopingcall.LoopingCallDone()

            if (CONF.xcat.reboot_timeout and
                    timeutils.utcnow() > expiration):
                locals['errstr'] = _("Timeout while waiting for"
                           " rebooting node %s.") % nodename
                LOG.warning(locals['errstr'])
                raise loopingcall.LoopingCallDone()

        expiration = timeutils.utcnow() + datetime.timedelta(
                seconds=CONF.xcat.reboot_timeout)
        timer = loopingcall.FixedIntervalLoopingCall(_wait_for_reboot)
        # default check every 5 seconds
        timer.start(interval=CONF.xcat.reboot_checking_interval).wait()

        if locals['errstr']:
            raise exception.xCATRebootFailure(locals['errstr'])
