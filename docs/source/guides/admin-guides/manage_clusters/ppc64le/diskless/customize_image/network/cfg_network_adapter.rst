Configure Additional Network Interfaces - confignetwork
-------------------------------------------------------

The ``confignetwork`` postscript can be used to configure the network interfaces on the compute nodes to support Ethernet adapters, VLAN, BONDs, and BRIDGES. ``confignetwork`` can be used in postscripts during OS privision, it can also be executed in ``updatenode``. The way the ``confignetwork`` postscript decides what IP address to give the secondary adapter is by checking the ``nics`` table, in which the nic configuration information is stored. In order for the ``confignetwork`` postscript to run successfully, the following attributes must be configured for the node in the ``nics`` table:

    * ``nicips``
    * ``nictypes``
    * ``nicnetworks``

If configuring VLAN, BOND, or BRIDGES, ``nicdevices`` in ``nics`` table must be configured. VLAN, BOND or BRIDGES is only supported on RHEL.

    * ``nicdevices`` - resolves the relationship among the physical network interface devices

The following scenarios are examples to configure Ethernet adapters/BOND/VLAN/Bridge.

    #. Configure static install or application Ethernet adapters:

        * Scenario 1: :doc:`Configure Ethernet Network Interface <../../../../common/deployment/network/cfg_network_ethernet_nic>`

    #. Configure BOND **[RHEL]**:

        * Scenario 2: :doc:`Configure Bond using two Ethernet Adapters <../../../../common/deployment/network/cfg_network_bond>`

    #. Configure VLAN **[RHEL]**:

        * Scenario 3: :doc:`Configure VLAN Based on Ethernet Adapter <../../../../common/deployment/network/cfg_network_vlan>`
        * Scenario 4: :doc:`Configure VLAN Based on Bond Adapters <../../../../common/deployment/network/cfg_network_bond_vlan>`

    #. Configure Bridge **[RHEL]**:

        * Scenario 5: :doc:`Configure Bridge Based On Ethernet NIC <../../../../common/deployment/network/cfg_network_bridge>`
        * Scenario 6: :doc:`Configure Bridge Based on Bond Adapters <../../../../common/deployment/network/cfg_network_bond_bridge>`
        * Scenario 7: :doc:`Configure Bridge Based on VLAN <../../../../common/deployment/network/cfg_network_vlan_bridge>`

        * Scenario 8: :doc:`Configure Bridge Based on VLAN,VLAN use BOND adapter <../../../../common/deployment/network/cfg_network_bond_vlan_bridge>`

    #. Advanced topics:

        * :doc:`Use Customized Scripts To Configure NIC <../../../../common/deployment/network/cfg_network_custom_scripts>`
        * :doc:`Use Extra Parameters In NIC Configuration File <../../../../common/deployment/network/cfg_network_extra_param>`
        * :doc:`Configure Aliases <../../../../common/deployment/network/cfg_network_aliases>`
