
"""
IPMI power manager driver.
"""

import contextlib
import os
import stat
import tempfile
import time

from oslo.config import cfg

from ironic.common import exception
from ironic.common import states
from ironic.common import utils
from ironic.conductor import task_manager
from ironic.drivers import base
from ironic.drivers.modules import console_utils
from ironic.openstack.common import excutils
from ironic.openstack.common import log as logging
from ironic.openstack.common import loopingcall
from ironic.openstack.common import processutils
from ironic.drivers.modules import xcat_exception
from ironic.drivers.modules import xcat_util

CONF = cfg.CONF
CONF.import_opt('retry_timeout',
                'ironic.drivers.modules.ipminative',
                group='ipmi')
CONF.import_opt('min_command_interval',
                'ironic.drivers.modules.ipminative',
                group='ipmi')

LOG = logging.getLogger(__name__)

VALID_PRIV_LEVELS = ['ADMINISTRATOR', 'CALLBACK', 'OPERATOR', 'USER']
REQUIRED_PROPERTIES = {
    'ipmi_address': _("IP address or hostname of the node. Required.")
}
OPTIONAL_PROPERTIES = {
    'ipmi_password': _("password. Optional."),
    'ipmi_priv_level': _("privilege level; default is ADMINISTRATOR. One of "
                         "%s. Optional.") % ', '.join(VALID_PRIV_LEVELS),
    'ipmi_username': _("username; default is NULL user. Optional.")
}
COMMON_PROPERTIES = REQUIRED_PROPERTIES.copy()
COMMON_PROPERTIES.update(OPTIONAL_PROPERTIES)
CONSOLE_PROPERTIES = {
    'ipmi_terminal_port': _("node's UDP port to connect to. Only required for "
                            "console access.")
}
TIMING_SUPPORT = None


def _is_timing_supported(is_supported=None):
    # shim to allow module variable to be mocked in unit tests
    global TIMING_SUPPORT

    if (TIMING_SUPPORT is None) and (is_supported is not None):
        TIMING_SUPPORT = is_supported
    return TIMING_SUPPORT


def check_timing_support():
    """Check the installed version of ipmitool for -N -R option support.

    Support was added in 1.8.12 for the -N -R options, which enable
    more precise control over timing of ipmi packets. Prior to this,
    the default behavior was to retry each command up to 18 times at
    1 to 5 second intervals.
    http://ipmitool.cvs.sourceforge.net/viewvc/ipmitool/ipmitool/ChangeLog?revision=1.37  # noqa

    This method updates the module-level TIMING_SUPPORT variable so that
    it is accessible by any driver interface class in this module. It is
    intended to be called from the __init__ method of such classes only.

    :returns: boolean indicating whether support for -N -R is present
    :raises: OSError
    """
    if _is_timing_supported() is None:
        # Directly check ipmitool for support of -N and -R options. Because
        # of the way ipmitool processes' command line options, if the local
        # ipmitool does not support setting the timing options, the command
        # below will fail.
        try:
            out, err = utils.execute(*['ipmitool', '-N', '0', '-R', '0', '-h'])
        except processutils.ProcessExecutionError:
            # the local ipmitool does not support the -N and -R options.
            _is_timing_supported(False)
        else:
            # looks like ipmitool supports timing options.
            _is_timing_supported(True)


def _console_pwfile_path(uuid):
    """Return the file path for storing the ipmi password for a console."""
    file_name = "%(uuid)s.pw" % {'uuid': uuid}
    return os.path.join(tempfile.gettempdir(), file_name)

def _parse_driver_info(node):
    """Gets the parameters required for ipmitool to access the node.

    :param node: the Node of interest.
    :returns: dictionary of parameters.
    :raises: InvalidParameterValue if any required parameters are missing.

    """
    info = node.driver_info or {}
    address = info.get('ipmi_address')
    username = info.get('ipmi_username')
    password = info.get('ipmi_password')
    port = info.get('ipmi_terminal_port')
    priv_level = info.get('ipmi_priv_level', 'ADMINISTRATOR')
    xcat_node = info.get('xcat_node')
    xcatmaster = info.get('xcatmaster')
    netboot = info.get('netboot')

    if port:
        try:
            port = int(port)
        except ValueError:
            raise exception.InvalidParameterValue(_(
                "IPMI terminal port is not an integer."))

    if not address:
        raise exception.InvalidParameterValue(_(
            "IPMI address not supplied to xcat driver."))

    if priv_level not in VALID_PRIV_LEVELS:
        valid_priv_lvls = ', '.join(VALID_PRIV_LEVELS)
        raise exception.InvalidParameterValue(_(
            "Invalid privilege level value:%(priv_level)s, the valid value"
            " can be one of %(valid_levels)s") %
            {'priv_level': priv_level, 'valid_levels': valid_priv_lvls})

    if not xcat_node:
        raise exception.InvalidParameterValue(_(
            "xcat node name not supplied to xcat driver"))

    if not xcatmaster:
        raise exception.InvalidParameterValue(_(
            "xcatmaster not supplied to xcat driver"))

    if not netboot:
        raise exception.InvalidParameterValue(_(
            "netboot not supplied to xcat driver"))

    return {
            'address': address,
            'username': username,
            'password': password,
            'port': port,
            'uuid': node.uuid,
            'priv_level': priv_level,
            'xcat_node': xcat_node,
            'xcatmaster': xcatmaster,
            'netboot': netboot
           }
def chdef_node(driver_info):
    """Run the chdef command in xcat, config the node
    :param driver_info: driver_info for the xcat node
    """
    cmd = 'chdef'
    args = 'mgt=ipmi' + \
           ' bmc=' + driver_info['address'] + \
           ' bmcusername=' + driver_info['username'] + \
           ' bmcpassword=' + driver_info['password'] + \
           ' xcatmaster='  + driver_info['xcatmaster']+ \
           ' netboot=' + driver_info['netboot']+ \
           ' primarynic=mac'+ \
           ' installnic=mac'+ \
           ' monserver=' + driver_info['xcatmaster'] + \
           ' nfsserver=' + driver_info['xcatmaster'] + \
           ' serialflow=hard'+ \
           ' serialspeed=115200' + \
           ' serialport=' + str(driver_info['port']);

    try:
        xcat_util.exec_xcatcmd(driver_info, cmd, args)
    except xcat_exception.xCATCmdFailure as e:
        LOG.warning(_("xcat chdef failed for node %(node_id)s with "
                    "error: %(error)s.")
                    % {'node_id': driver_info['uuid'], 'error': e})

def _sleep_time(iter):
    """Return the time-to-sleep for the n'th iteration of a retry loop.
    This implementation increases exponentially.

    :param iter: iteration number
    :returns: number of seconds to sleep

    """
    if iter <= 1:
        return 1
    return iter ** 2


def _set_and_wait(target_state, driver_info):
    """Helper function for DynamicLoopingCall.

    This method changes the power state and polls the BMCuntil the desired
    power state is reached, or CONF.ipmi.retry_timeout would be exceeded by the
    next iteration.

    This method assumes the caller knows the current power state and does not
    check it prior to changing the power state. Most BMCs should be fine, but
    if a driver is concerned, the state should be checked prior to calling this
    method.

    :param target_state: desired power state
    :param driver_info: the ipmitool parameters for accessing a node.
    :returns: one of ironic.common.states
    :raises: IPMIFailure on an error from ipmitool (from _power_status call).

    """
    if target_state == states.POWER_ON:
        state_name = "on"
    elif target_state == states.POWER_OFF:
        state_name = "off"

    def _wait(mutable):
        try:
            # Only issue power change command once
            if mutable['iter'] < 0:
                xcat_util.exec_xcatcmd(driver_info,'rpower',state_name)
            else:
                mutable['power'] = _power_status(driver_info)
        except Exception:
            # Log failures but keep trying
            LOG.warning(_("xcat rpower %(state)s failed for node %(node)s."),
                         {'state': state_name, 'node': driver_info['uuid']})
        finally:
            mutable['iter'] += 1

        if mutable['power'] == target_state:
            raise loopingcall.LoopingCallDone()

        sleep_time = _sleep_time(mutable['iter'])
        if (sleep_time + mutable['total_time']) > CONF.ipmi.retry_timeout:
            # Stop if the next loop would exceed maximum retry_timeout
            LOG.error(_('xcat rpower %(state)s timed out after '
                        '%(tries)s retries on node %(node_id)s.'),
                        {'state': state_name, 'tries': mutable['iter'],
                        'node_id': driver_info['uuid']})
            mutable['power'] = states.ERROR
            raise loopingcall.LoopingCallDone()
        else:
            mutable['total_time'] += sleep_time
            return sleep_time

    # Use mutable objects so the looped method can change them.
    # Start 'iter' from -1 so that the first two checks are one second apart.
    status = {'power': None, 'iter': -1, 'total_time': 0}

    timer = loopingcall.DynamicLoopingCall(_wait, status)
    timer.start().wait()
    return status['power']

def _power_on(driver_info):
    """Turn the power ON for this node.

    :param driver_info: the xcat parameters for accessing a node.
    :returns: one of ironic.common.states POWER_ON or ERROR.
    :raises: IPMIFailure on an error from ipmitool (from _power_status call).

    """
    return _set_and_wait(states.POWER_ON, driver_info)


def _power_off(driver_info):
    """Turn the power OFF for this node.

    :param driver_info: the xcat parameters for accessing a node.
    :returns: one of ironic.common.states POWER_OFF or ERROR.
    :raises: IPMIFailure on an error from ipmitool (from _power_status call).

    """
    return _set_and_wait(states.POWER_OFF, driver_info)

def _power_status(driver_info):
    """Get the power status for a node.

    :param driver_info: the xcat access parameters for a node.
    :returns: one of ironic.common.states POWER_OFF, POWER_ON or ERROR.
    :raises: IPMIFailure on an error from ipmitool.

    """
    cmd = "rpower"
    try:
        out_err = xcat_util.exec_xcatcmd(driver_info,cmd,'status')
    except Exception as e:
        LOG.warning(_("xcat rpower status failed for node %(node_id)s with "
                      "error: %(error)s.")
                    % {'node_id': driver_info['uuid'], 'error': e})

    if out_err[0].split(' ')[1].strip() == "on":
        return states.POWER_ON
    elif out_err[0].split(' ')[1].strip() == "off":
        return states.POWER_OFF
    else:
        return states.ERROR


class XcatPower(base.PowerInterface):

    def __init__(self):
        try:
            check_timing_support()
        except OSError:
            raise exception.DriverLoadError(
                    driver=self.__class__.__name__,
                    reason="Unable to locate usable xcat command in "
                           "the system path when checking xcat version")
    def get_properties(self):
        return COMMON_PROPERTIES

    def validate(self, task):
        """Validate driver_info for xcat driver.

        Check that node['driver_info'] contains IPMI credentials.

        :param task: a TaskManager instance containing the node to act on.
        :raises: InvalidParameterValue if required ipmi parameters are missing.

        """
        driver_info = _parse_driver_info(task.node)
        try:
            chdef_node(driver_info)
        except exception:
            LOG.error(_("chdef xcat info error!"))

    def get_power_state(self, task):
        """Get the current power state of the task's node.

        :param task: a TaskManager instance containing the node to act on.
        :returns: one of ironic.common.states POWER_OFF, POWER_ON or ERROR.

        """
        driver_info = _parse_driver_info(task.node)
        return _power_status(driver_info)

    @task_manager.require_exclusive_lock
    def set_power_state(self, task, pstate):
        """Turn the power on or off.

        :param task: a TaskManager instance containing the node to act on.
        :param pstate: The desired power state, one of ironic.common.states
            POWER_ON, POWER_OFF.
        :raises: InvalidParameterValue if required ipmi parameters are missing
            or if an invalid power state was specified.
        :raises: PowerStateFailure if the power couldn't be set to pstate.

        """
        driver_info = _parse_driver_info(task.node)

        if pstate == states.POWER_ON:
            state = _power_on(driver_info)
        elif pstate == states.POWER_OFF:
            state = _power_off(driver_info)
        else:
            raise exception.InvalidParameterValue(_("set_power_state called "
                    "with invalid power state %s.") % pstate)
        if state != pstate:
            raise exception.PowerStateFailure(pstate=pstate)

    @task_manager.require_exclusive_lock
    def reboot(self, task):
        """Cycles the power to the task's node.

        :param task: a TaskManager instance containing the node to act on.
        :raises: InvalidParameterValue if required ipmi parameters are missing.
        :raises: PowerStateFailure if the final state of the node is not
            POWER_ON.

        """
        driver_info = _parse_driver_info(task.node)
        _power_off(driver_info)
        state = _power_on(driver_info)

        if state != states.POWER_ON:
            raise exception.PowerStateFailure(pstate=states.POWER_ON)

class IPMIShellinaboxConsole(base.ConsoleInterface):
    """A ConsoleInterface that uses ipmitool and shellinabox."""

    def __init__(self):
        try:
            check_timing_support()
        except OSError:
            raise exception.DriverLoadError(
                    driver=self.__class__.__name__,
                    reason="Unable to locate usable xcat command in "
                           "the system path when checking xcat version")
    def get_properties(self):
        return COMMON_PROPERTIES

    def validate(self, task):
        """Validate the Node console info.

        :param task: a task from TaskManager.
        :raises: InvalidParameterValue
        """
        driver_info = _parse_driver_info(task.node)
        if not driver_info['xcat_node']:
            raise exception.InvalidParameterValue(_(
                "xcat node name not supplied to xcat baremetal driver."))
        if not driver_info['port']:
            raise exception.InvalidParameterValue(_(
                "IPMI terminal port not supplied to IPMI driver."))

    def start_console(self, task):
        """Start a remote console for the node."""
        driver_info = _parse_driver_info(task.node)

        path = _console_pwfile_path(driver_info['uuid'])
        pw_file = console_utils.make_persistent_password_file(
                path, driver_info['password'])

        ipmi_cmd = "/:%(uid)s:%(gid)s:HOME:ipmitool -H %(address)s" \
                   " -I lanplus -U %(user)s -f %(pwfile)s"  \
                   % {'uid': os.getuid(),
                      'gid': os.getgid(),
                      'address': driver_info['address'],
                      'user': driver_info['username'],
                      'pwfile': pw_file}
        if CONF.debug:
            ipmi_cmd += " -v"
        ipmi_cmd += " sol activate"
        console_utils.start_shellinabox_console(driver_info['uuid'],
                                                driver_info['port'],
                                                ipmi_cmd)

    def stop_console(self, task):
        """Stop the remote console session for the node."""
        driver_info = _parse_driver_info(task.node)
        console_utils.stop_shellinabox_console(driver_info['uuid'])
        utils.unlink_without_raise(_console_pwfile_path(driver_info['uuid']))

    def get_console(self, task):
        """Get the type and connection information about the console."""
        driver_info = _parse_driver_info(task.node)
        url = console_utils.get_shellinabox_console_url(driver_info['port'])
        return {'type': 'shellinabox', 'url': url}
