#
# Cookbook Name:: openstack-network
# Recipe:: metadata_agent
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

identity_endpoint = endpoint "identity-api"
service_pass = service_password "openstack-network"
metadata_secret = secret "secrets", node["openstack"]["network"]["metadata"]["secret_name"]

template "/etc/quantum/metadata_agent.ini" do
  source "metadata_agent.ini.erb"
  owner node["openstack"]["network"]["platform"]["user"]
  group node["openstack"]["network"]["platform"]["group"]
  mode   00644
  variables(
    :identity_endpoint => identity_endpoint,
    :metadata_secret => metadata_secret,
    :service_pass => service_pass
  )
  notifies :restart, "service[quantum-metadata-agent]", :immediately
  action :create
end

platform_options["quantum_metadata_agent_packages"].each do |pkg|
  package pkg do
    action :install
    options platform_options["package_overrides"]
  end
end

service "quantum-metadata-agent" do
  service_name platform_options["quantum_metadata_agent_service"]
  supports :status => true, :restart => true
  action :enable
end
