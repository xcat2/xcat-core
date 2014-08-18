"""
XCATBaremetalDriver
use xcat to deploy a baremetal machine
"""


from ironic.drivers import base
from ironic.drivers.modules import ipmitool
from ironic.drivers.modules import pxe
from ironic.drivers.modules import xcat_pxe
from ironic.drivers import utils
from ironic.drivers.modules import xcat_rpower


class XCATBaremetalDriver(base.BaseDriver):
    """xCAT driver
    This driver implements the `core` functionality, combinding
    :class:`ironic.drivers.xcat_rpower.XcatPower` for power on/off and reboot with
    :class:`ironic.driver.xcat_pxe.PXEDeploy` for image deployment. Implementations are in
    those respective classes; this class is merely the glue between them.
    """
    def __init__(self):
        self.power = xcat_rpower.XcatPower()
        self.console = ipmitool.IPMIShellinaboxConsole()
        self.deploy = xcat_pxe.PXEDeploy()
        self.management = ipmitool.IPMIManagement()
        self.vendor = pxe.VendorPassthru()