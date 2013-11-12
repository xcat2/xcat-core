#
# Cookbook Name:: openstack-network
# Recipe:: linuxbridge
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

platform_options["quantum_linuxbridge_agent_packages"].each do |pkg|
  package pkg do
    options platform_options["package_overrides"]
    action :install
  end
end

service "quantum-plugin-linuxbridge-agent" do
  service_name platform_options["quantum_linuxbridge_agent_service"]
  supports :status => true, :restart => true
  action :enable
end
