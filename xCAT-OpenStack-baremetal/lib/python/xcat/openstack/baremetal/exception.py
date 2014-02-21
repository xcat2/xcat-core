# vim: tabstop=4 shiftwidth=4 softtabstop=4

"""xCAT baremtal exceptions.
"""

import functools
import sys

from oslo.config import cfg
import webob.exc

from nova.openstack.common import excutils
from nova.openstack.common.gettextutils import _
from nova.openstack.common import log as logging
from nova import safe_utils
from nova import exception as nova_exception

LOG = logging.getLogger(__name__)

class xCATException(Exception):
    errmsg = _("xCAT general exception")

    def __init__(self, errmsg=None, **kwargs):
        if not errmsg:
            errmsg = self.errmsg
            errmsg = errmsg % kwargs

        super(xCATException, self).__init__(errmsg)

class xCATCommandError(xCATException):
    errmsg =  _("Error returned when calling xCAT command %(cmd)s"
                " for node %(node)s:%(error)s")

class xCATInvalidImageError(xCATException):
    errmsg = _("The image %(image)s is not an xCAT image")

class xCATDeploymentFailure(xCATException):    
    errmsg = _("xCAT node deployment failed for node %(node)s:%(error)s")

class xCATRebootFailure(xCATException):    
    errmsg = _("xCAT node rebooting failed for node %(node)s:%(error)s")
