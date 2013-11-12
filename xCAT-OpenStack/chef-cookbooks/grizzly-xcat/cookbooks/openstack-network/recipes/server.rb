#
# Cookbook Name:: openstack-network
# Recipe:: server
#
# Copyright 2013, AT&T
# Copyright 2013, SUSE Linux GmbH
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

class ::Chef::Recipe
  include ::Openstack
end

include_recipe "openstack-network::common"

platform_options = node["openstack"]["network"]["platform"]
driver_name = node["openstack"]["network"]["interface_driver"].split('.').last.downcase
main_plugin = node["openstack"]["network"]["interface_driver_map"][driver_name]
core_plugin = node["openstack"]["network"]["core_plugin"]

platform_options = node["openstack"]["network"]["platform"]

platform_options["quantum_server_packages"].each do |pkg|
  package pkg do
    options platform_options["package_overrides"]
    action :install
  end
end

service "quantum-server" do
  service_name platform_options["quantum_server_service"]
  supports :status => true, :restart => true
  action :enable
end

cookbook_file "quantum-ha-tool" do
  source "quantum-ha-tool.py"
  path node["openstack"]["network"]["quantum_ha_cmd"]
  owner "root"
  group "root"
  mode 00755
end

if node["openstack"]["network"]["quantum_ha_cmd_cron"]
  # ensure period checks are offset between multiple l3 agent nodes
  # and assumes splay will remain constant (i.e. based on hostname)
  # Generate a uniformly distributed unique number to sleep.
  checksum   = Digest::MD5.hexdigest(node['fqdn'] || 'unknown-hostname')
  splay = node['chef_client']['splay'].to_i || 3000
  sleep_time = checksum.to_s.hex % splay

  cron "quantum-ha-healthcheck" do
    minute node["openstack"]["network"]["cron_l3_healthcheck"]
    command "sleep #{sleep_time} ; . /root/openrc && #{node["openstack"]["network"]["quantum_ha_cmd"]} --l3-agent-migrate > /dev/null 2>&1"
  end

  cron "quantum-ha-replicate-dhcp" do
    minute node["openstack"]["network"]["cron_replicate_dhcp"]
    command "sleep #{sleep_time} ; . /root/openrc && #{node["openstack"]["network"]["quantum_ha_cmd"]} --replicate-dhcp > /dev/null 2>&1"
  end
end

# the default SUSE initfile uses this sysconfig file to determine the
# quantum plugin to use
template "/etc/sysconfig/quantum" do
  only_if { platform? "suse" }
  source "quantum.sysconfig.erb"
  owner "root"
  group "root"
  mode 00644
  variables(
    :plugin_conf => node["openstack"]["network"]["plugin_conf_map"][driver_name]
  )
  notifies :restart, "service[quantum-server]"
end
