#
# Cookbook Name:: openstack-network
# Recipe:: balancer
#
# Copyright 2013, Mirantis IT
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

# This recipe should be placed in the run_list of the node that
# runs the network server or network controller server.

platform_options = node["openstack"]["network"]["platform"]

service "quantum-server" do
  service_name platform_options["quantum_server_service"]
  supports :status => true, :restart => true

  action :nothing
end

platform_options["quantum_lb_packages"].each do |pkg|
   package pkg do
     action :install
   end
end

directory node["openstack"]["network"]["lbaas_config_path"] do
  action :create
  owner node["openstack"]["network"]["platform"]["user"]
  group node["openstack"]["network"]["platform"]["group"]
  recursive true
end

template "#{node["openstack"]["network"]["lbaas_config_path"]}/lbaas_agent.ini" do
  source "lbaas_agent.ini.erb"
  notifies :restart, "service[quantum-server]", :immediately
end
