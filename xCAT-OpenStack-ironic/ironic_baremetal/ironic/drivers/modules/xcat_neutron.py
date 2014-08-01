"""
Get the network from neutron
This is a xcat patch for the ironic/common/neutron.py
"""

from neutronclient.common import exceptions as neutron_client_exc
from ironic.common import exception
from ironic.openstack.common import log as logging
from ironic.common import neutron
from ironic.drivers.modules import xcat_exception

LOG = logging.getLogger(__name__)

def get_vif_port_info(task, port_id):
    """ Get  detail port info from neutron with a given port id """
    api = neutron.NeutronAPI(task.context)
    try:
        port_info = api.client.show_port(port_id)
    except neutron_client_exc.NeutronClientException:
        LOG.exception(_("Failed to get port info %s."), port_id)
        raise exception.FailedToGetInfoOnPort(port_id=port_id)
    return port_info


def get_ports_info_from_neutron(task):
    """  Get neutron port info from neutron about this task """
    vifs = neutron.get_node_vif_ids(task)
    if not vifs:
        LOG.warning(_("No VIFs found for node %(node)s when attempting to "
                      "update Neutron DHCP BOOT options."),
                      {'node': task.node.uuid})
        return
    failures = []
    vif_ports_info = {}
    for port_id, port_vif in vifs.iteritems():
        try:
            vif_ports_info[port_id] = get_vif_port_info(task,port_vif)
        except xcat_exception.FailedToGetInfoOnPort(port_id=port_vif):
            failures.append(port_vif)
    return vif_ports_info

