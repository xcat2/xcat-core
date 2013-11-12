Description
===========

This cookbook installs the OpenStack Compute service **Nova** as part of the OpenStack reference deployment Chef for OpenStack. The http://github.com/mattray/chef-openstack-repo contains documentation for using this cookbook in the context of a full OpenStack deployment. Nova is currently installed from packages.

http://nova.openstack.org

Requirements
============

Chef 0.10.0 or higher required (for Chef environment use).

Cookbooks
---------

The following cookbooks are dependencies:

* apache2
* openstack-common
* openstack-identity
* openstack-image
* selinux (Fedora)
* sysctl
* yum

Usage
=====

api-ec2
----
- Includes recipe `nova-common`
- Installs AWS EC2 compatible API and configures the service and endpoints in keystone

api-metadata
----
- Includes recipe `nova-common`
- Installs the nova metadata package

api-os-compute
----
- Includes recipe `nova-common`
- Installs OS API and configures the service and endpoints in keystone

compute
----
- Includes recipes `nova-common`, `api-metadata`, `network`
- Installs nova-compute service

libvirt
----
- Installs libvirt, used by nova compute for management of the virtual machine environment

network
----
- Includes recipe `nova-common`
- Installs nova network service

nova-cert
----
- Installs nova-cert service

nova-common
----
- May include recipe `selinux` (Fedora)
- Builds the basic nova.conf config file with details of the rabbitmq, mysql, glance and keystone servers
- Builds a openrc file for root with appropriate environment variables to interact with the nova client CLI

nova-setup
----
- Includes recipes `nova-common`
- Sets up the nova networks with `nova-manage`

scheduler
----
- Includes recipe `nova-common`
- Installs nova scheduler service

vncproxy
----
- Includes recipe `nova-common`
- Installs and configures the vncproxy service for console access to VMs

Attributes
==========

Openstack Compute attributes are in the attribute namespace ["openstack"]["compute"].

* `openstack["compute"]["identity_service_chef_role"]` - The name of the Chef role that sets up the Keystone Service API
* `openstack["compute"]["user"]` - User nova services run as
* `openstack["compute"]["group"]` - Group nova services run as
* `openstack["compute"]["db"]["username"]` - Username for nova database access
* `openstack["compute"]["rabbit"]["username"]` - Username for nova rabbit access
* `openstack["compute"]["rabbit"]["vhost"]` - The rabbit vhost to use
* `openstack["compute"]["rabbit"]["port"]` - The rabbit port to use
* `openstack["compute"]["rabbit"]["host"]` - The rabbit host to use (must set when `openstack["compute"]["rabbit"]["ha"]` false).
* `openstack["compute"]["rabbit"]["ha"]` - Whether or not to use rabbit ha
* `openstack["compute"]["service_tenant_name"]` - Tenant name used by nova when interacting with keystone
* `openstack["compute"]["service_user"]` - User name used by nova when interacting with keystone
* `openstack["compute"]["service_role"]` - User role used by nova when interacting with keystone
* `openstack["compute"]["floating_cmd"]` - Path to the `nova-manage floating create` wrapper script.
* `openstack["compute"]["config"]["volume_api_class"]` - API Class used for Volume support
* `openstack["compute"]["compute"]["api"]["protocol"]` - Protocol used for the OS API
* `openstack["compute"]["compute"]["api"]["port"]` - Port on which OS API runs
* `openstack["compute"]["compute"]["api"]["version"]` - Version of the OS API used
* `openstack["compute"]["compute"]["adminURL"]` - URL used to access the OS API for admin functions
* `openstack["compute"]["compute"]["internalURL"]` - URL used to access the OS API for user functions from an internal network
* `openstack["compute"]["compute"]["publicURL"]` - URL used to access the OS API for user functions from an external network
* `openstack["compute"]["config"]["availability_zone"]` - Nova availability zone.  Usually set at the node level to place a compute node in another az
* `openstack["compute"]["config"]["default_schedule_zone"]` - The availability zone to schedule instances in when no az is specified in the request
* `openstack["compute"]["config"]["force_raw_images"]` - Convert all images used as backing files for instances to raw (we default to false)
* `openstack["compute"]["config"]["allow_same_net_traffic"]` - Disable security groups for internal networks (we default to true)
* `openstack["compute"]["config"]["osapi_max_limit"]` - The maximum number of items returned in a single response from a collection resource (default is 1000)
* `openstack["compute"]["config"]["cpu_allocation_ratio"]` - Virtual CPU to Physical CPU allocation ratio (default 16.0)
* `openstack["compute"]["config"]["ram_allocation_ratio"]` - Virtual RAM to Physical RAM allocation ratio (default 1.5)
* `openstack["compute"]["config"]["snapshot_image_format"]` - Snapshot image format (valid options are : raw, qcow2, vmdk, vdi [we default to qcow2]).
* `openstack["compute"]["config"]["start_guests_on_host_boot"]` - Whether to restart guests when the host reboots
* `openstack["compute"]["config"]["resume_guests_state_on_host_boot"]` - Whether to start guests that were running before the host rebooted
* `openstack["compute"]["api"]["signing_dir"]` - Keystone PKI needs a location to hold the signed tokens
* `openstack["compute"]["api"]["signing_dir"]` - Keystone PKI needs a location to hold the signed tokens

Networking Attributes
---------------------

Basic networking configuration is controlled with the following attributes:

* `openstack["compute"]["network"]["network_manager"]` - Defaults to "nova.network.manager.FlatDHCPManager". Set to "nova.network.manager.VlanManager" to configure VLAN Networking.
* `openstack["compute"]["network"]["fixed_range"]` - The CIDR for the network that VMs will be assigned to. In the case of VLAN Networking, this should be the network in which all VLAN networks that tenants are assigned will fit.
* `openstack["compute"]["network"]["dmz_cidr"]` - A CIDR for the range of IP addresses that will NOT be SNAT'ed by the nova network controller
* `openstack["compute"]["network"]["public_interface"]` - Defaults to eth0. Refers to the network interface used for VM addresses in the `fixed_range`.
* `openstack["compute"]["network"]["vlan_interface"]` - Defaults to eth0. Refers to the network interface used for VM addresses when VMs are assigned in a VLAN subnet.

You can have the cookbook automatically create networks in Nova for you by adding a Hash to the `openstack["compute"]["networks"]` Array.
**Note**: The `openstack-compute::nova-setup` recipe contains the code that creates these pre-defined networks.

Each Hash must contain the following keys:

* `ipv4_cidr` - The CIDR representation of the subnet. Supplied to the nova-manage network create command as `--fixed_ipv4_range`
* `label` - A name for the network

In addition to the above required keys in the Hash, the below keys are optional:

* `num_networks` - Passed as-is to `nova-manage network create` as the `--num_networks` option. This overrides the default `num_networks` nova.conf value.
* `network_size` - Passed as-is to `nova-manage network create` as the `--network_size` option. This overrides the default `network_size` nova.conf value.
* `bridge` - Passed as-is to `nova-manage network create` as the `--bridge` option.
* `bridge_interface` -- Passed as-is to `nova-manage network create` as the `--bridge_interface` option. This overrides the default `vlan_interface` nova.conf value.
* `dns1` - Passed as-is to `nova-manage network create` as the `--dns1` option.
* `dns2` - Passed as-is to `nova-manage network create` as the `--dns2` option.
* `multi_host` - Passed as-is to `nova-manage network create` as the `--multi_host` option. Values should be either 'T' or 'F'
* `vlan` - Passed as-is to `nova-manage network create` as the `--vlan` option. Should be the VLAN tag ID.

By default, the `openstack["compute"]["networks"]` array has two networks:

* `openstack["compute"]["networks"]["public"]["label"]` - Network label to be assigned to the public network on creation
* `openstack["compute"]["networks"]["public"]["ipv4_cidr"]` - Network to be created (in CIDR notation, e.g., 192.168.100.0/24)
* `openstack["compute"]["networks"]["public"]["num_networks"]` - Number of networks to be created
* `openstack["compute"]["networks"]["public"]["network_size"]` - Number of IP addresses to be used in this network
* `openstack["compute"]["networks"]["public"]["bridge"]` - Bridge to be created for accessing the VM network (e.g., br100)
* `openstack["compute"]["networks"]["public"]["bridge_dev"]` - Physical device on which the bridge device should be attached (e.g., eth2)
* `openstack["compute"]["networks"]["public"]["dns1"]` - DNS server 1
* `openstack["compute"]["networks"]["public"]["dns2"]` - DNS server 2

* `openstack["compute"]["networks"]["private"]["label"]` - Network label to be assigned to the private network on creation
* `openstack["compute"]["networks"]["private"]["ipv4_cidr"]` - Network to be created (in CIDR notation e.g., 192.168.200.0/24)
* `openstack["compute"]["networks"]["private"]["num_networks"]` - Number of networks to be created
* `openstack["compute"]["networks"]["private"]["network_size"]` - Number of IP addresses to be used in this network
* `openstack["compute"]["networks"]["private"]["bridge"]` - Bridge to be created for accessing the VM network (e.g., br200)
* `openstack["compute"]["networks"]["private"]["bridge_dev"]` - Physical device on which the bridge device should be attached (e.g., eth3)

VNC Configuration Attributes
----------------------------

Requires [network_addr](https://gist.github.com/jtimberman/1040543) Ohai plugin.

* `openstack["compute"]["xvpvnc_proxy"]["service_port"]` - Port on which XvpVNC runs
* `openstack["compute"]["xvpvnc_proxy"]["bind_interface"]` - Determine the interface's IP address to bind to
* `openstack["compute"]["novnc_proxy"]["service_port"]` - Port on which NoVNC runs
* `openstack["compute"]["novnc_proxy"]["bind_interface"]` - Determine the interface's IP address to bind to

Libvirt Configuration Attributes
---------------------------------

* `openstack["compute"]["libvirt"]["virt_type"]` - What hypervisor software layer to use with libvirt (e.g., kvm, qemu)
* `openstack["compute"]["libvirt"]["bind_interface"]` - Determine the interface's IP address (used for VNC).  IP address on the hypervisor that libvirt listens for VNC requests on, and IP address on the hypervisor that libvirt exposes for VNC requests on.
* `openstack["compute"]["libvirt"]["auth_tcp"]` - Type of authentication your libvirt layer requires
* `openstack["compute"]["libvirt"]["ssh"]["private_key"]` - Private key to use if using SSH authentication to your libvirt layer
* `openstack["compute"]["libvirt"]["ssh"]["public_key"]` - Public key to use if using SSH authentication to your libvirt layer

Scheduler Configuration Attributes
----------------------------------

* `openstack["compute"]["scheduler"]["scheduler_driver"]` - the scheduler driver to use
NOTE: The filter scheduler currently does not work with ec2.
* `openstack["compute"]["scheduler"]["default_filters"]` - a list of filters enabled for schedulers that support them.

Syslog Configuration Attributes
-------------------------------

* `openstack["compute"]["syslog"]["use"]` - Should nova log to syslog?
* `openstack["compute"]["syslog"]["facility"]` - Which facility nova should use when logging in python style (for example, `LOG_LOCAL1`)
* `openstack["compute"]["syslog"]["config_facility"]` - Which facility nova should use when logging in rsyslog style (for example, local1)

OSAPI Compute Extentions
------------------------

* `openstack["compute"]["plugins"]` - Array of osapi compute exntesions to add to nova

Testing
=====

This cookbook uses [bundler](http://gembundler.com/), [berkshelf](http://berkshelf.com/), and [strainer](https://github.com/customink/strainer) to isolate dependencies and run tests.

Tests are defined in Strainerfile.

To run tests:

    $ bundle install # install gem dependencies
    $ bundle exec berks install # install cookbook dependencies
    $ bundle exec strainer test # run tests

License and Author
==================

|                      |                                                    |
|:---------------------|:---------------------------------------------------|
| **Author**           |  Justin Shepherd (<justin.shepherd@rackspace.com>) |
| **Author**           |  Jason Cannavale (<jason.cannavale@rackspace.com>) |
| **Author**           |  Ron Pedde (<ron.pedde@rackspace.com>)             |
| **Author**           |  Joseph Breu (<joseph.breu@rackspace.com>)         |
| **Author**           |  William Kelly (<william.kelly@rackspace.com>)     |
| **Author**           |  Darren Birkett (<darren.birkett@rackspace.co.uk>) |
| **Author**           |  Evan Callicoat (<evan.callicoat@rackspace.com>)   |
| **Author**           |  Matt Ray (<matt@opscode.com>)                     |
| **Author**           |  Jay Pipes (<jaypipes@att.com>)                    |
| **Author**           |  John Dewey (<jdewey@att.com>)                     |
| **Author**           |  Kevin Bringard (<kbringard@att.com>)                     |
| **Author**           |  Craig Tracey (<craigtracey@gmail.com>)            |
| **Author**           |  Sean Gallagher (<sean.gallagher@att.com>)         |
| **Author**           |  Ionut Artarisi (<iartarisi@suse.cz>)              |
|                      |                                                    |
| **Copyright**        |  Copyright (c) 2012-2013, Rackspace US, Inc.       |
| **Copyright**        |  Copyright (c) 2012-2013, Opscode, Inc.            |
| **Copyright**        |  Copyright (c) 2012-2013, AT&T Services, Inc.      |
| **Copyright**        |  Copyright (c) 2013, Craig Tracey                  |
| **Copyright**        |  Copyright (c) 2013, SUSE Linux GmbH               |

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
