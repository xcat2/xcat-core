"""
util for xcat baremetal driver
exec_xcatcmd
xcat_ssh  to excute remote cmd
"""
import paramiko
import time
import socket
from ironic.openstack.common import log as logging
from oslo.config import cfg
from ironic.drivers.modules import xcat_exception
from ironic.common import utils

xcat_opts = [
    cfg.IntOpt('ssh_session_timeout',
               default=10,
               help='ssh session time'),
    cfg.FloatOpt('ssh_shell_wait',
               default=0.5,
               help='wait time for the ssh cmd excute'),
    cfg.IntOpt('ssh_buf_size',
               default=65535,
               help='Maximum size (in charactor) of cache for ssh, '
               'including those in use'),
    cfg.StrOpt('ssh_key',
               default=None,
               help='ssh private key to login '),
    cfg.StrOpt('ssh_key_pass',
               default=None,
               help='Maximum size (in charactor) of cache for ssh, '
               'including those in use'),
    ]

LOG = logging.getLogger(__name__)

CONF = cfg.CONF
CONF.register_opts(xcat_opts, group='xcat')

LAST_CMD_TIME = {}

def xcat_ssh(ip,port,username,password,cmd):
    """ exec remote command with ssh  """
    key =None
    if CONF.xcat.ssh_key:
        try:
            key=paramiko.RSAKey.from_private_key_file(CONF.xcat.ssh_key)
        except paramiko.PasswordRequiredException:
            if not CONF.ssh_key_pass:
                raise Exception.message("no pubkey password")
            key = paramiko.RSAKey.from_private_key_file(
                CONF.xcat.ssh_key, CONF.xcat.ssh_key.ssh_key_pass)
    s = paramiko.SSHClient()
    s.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        s.connect(ip,port,username=username,password=password,pkey=key,
                  timeout=CONF.xcat.ssh_session_timeout)
    except socket.timeout as e:
        LOG.error(_("Unable to connect to the ssh server Exception: %(exception)s"),
                      {'exception': e})
    chan = s.invoke_shell()
    output = chan.recv(CONF.xcat.ssh_buf_size)
    while not output.rstrip().endswith('#') and not output.rstrip().endswith('$'):
        output = chan.recv(CONF.xcat.ssh_buf_size)
    for  c in cmd :
        _xcat_ssh_exec(chan,c,password)

def _xcat_ssh_exec(chan,cmd,password):
    """ exec ssh command """
    chan.send(cmd + '\n')
    time.sleep(CONF.xcat.ssh_shell_wait)
    ret = chan.recv(CONF.xcat.ssh_buf_size)
    if 'password' in ret and ret.rstrip().endswith(':'):
        chan.send(password + '\n')
        output = chan.recv(CONF.xcat.ssh_buf_size)
        while not output.rstrip().endswith('#') and not output.rstrip().endswith('$'):
            output = chan.recv(CONF.xcat.ssh_buf_size)
    return output

def _tsplit(string, delimiters):
    """ Behaves str.split but supports multiple delimiters. """
    delimiters = tuple(delimiters)
    stack = [string,]
    for delimiter in delimiters:
        for i, substring in enumerate(stack):
            substack = substring.split(delimiter)
            stack.pop(i)
            for j, _substring in enumerate(substack):
                stack.insert(i+j, _substring)
    return stack

def exec_xcatcmd(driver_info, command, args):
    """ excute xcat cmd """
    cmd = [command,
            driver_info['xcat_node']
            ]
    cmd.extend(args.split(" "))
        # NOTE: ensure that no communications are excuted more
        #             often than once every min_command_interval seconds.
    time_till_next_poll = CONF.ipmi.min_command_interval - (
                time.time() - LAST_CMD_TIME.get(driver_info['xcat_node'], 0))
    if time_till_next_poll > 0:
        time.sleep(time_till_next_poll)
    try:
        out, err = utils.execute(*cmd)
        if err:
            raise xcat_exception.xCATCmdFailure(cmd=cmd,node=driver_info['xcat_node'],
                                            args=args)
    finally:
        LAST_CMD_TIME[driver_info['xcat_node']] = time.time()
    return out, err