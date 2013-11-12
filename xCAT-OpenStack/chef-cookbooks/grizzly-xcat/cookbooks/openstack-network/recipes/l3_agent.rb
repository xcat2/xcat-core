#
# Cookbook Name:: openstack-network
# Recipe:: l3_agent
#
# Copyright 2013, AT&T
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

include_recipe "openstack-network::common"

platform_options = node["openstack"]["network"]["platform"]
driver_name = node["openstack"]["network"]["interface_driver"].split('.').last.downcase
main_plugin = node["openstack"]["network"]["interface_driver_map"][driver_name]

platform_options["quantum_l3_packages"].each do |pkg|
  package pkg do
    options platform_options["package_overrides"]
    action :install
    # The providers below do not use the generic L3 agent...
    not_if { ["nicira", "plumgrid", "bigswitch"].include?(main_plugin) }
  end
end

service "quantum-l3-agent" do
  service_name platform_options["quantum_l3_agent_service"]
  supports :status => true, :restart => true

  action :enable
end

execute "quantum-l3-setup --plugin #{main_plugin}" do
  only_if {
    platform?(%w(fedora redhat centos)) and not # :pragma-foodcritic: ~FC024 - won't fix this
    ["nicira", "plumgrid", "bigswitch"].include?(main_plugin)
  }
end

template "/etc/quantum/l3_agent.ini" do
  source "l3_agent.ini.erb"
  owner node["openstack"]["network"]["platform"]["user"]
  group node["openstack"]["network"]["platform"]["group"]
  mode   00644
  notifies :restart, "service[quantum-l3-agent]", :immediately
end

if not ["nicira", "plumgrid", "bigswitch", "linuxbridge"].include?(main_plugin)
  # See http://docs.openstack.org/trunk/openstack-network/admin/content/install_quantum-l3.html
  ext_bridge = node["openstack"]["network"]["l3"]["external_network_bridge"]
  ext_bridge_iface = node["openstack"]["network"]["l3"]["external_network_bridge_interface"]
  execute "create external network bridge" do
    command "ovs-vsctl add-br #{ext_bridge} && ovs-vsctl add-port #{ext_bridge} #{ext_bridge_iface}"
    action :run
    not_if "ovs-vsctl show | grep 'Bridge #{ext_bridge}'"
    only_if "ip link show #{ext_bridge_iface}"
  end
end
