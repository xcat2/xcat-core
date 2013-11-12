#
# Cookbook Name:: openstack-compute
# Recipe:: network
#
# Copyright 2012, Rackspace US, Inc.
# Copyright 2013, Craig Tracey <craigtracey@gmail.com>
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

include_recipe "openstack-compute::nova-common"

platform_options = node["openstack"]["compute"]["platform"]

# the only type of network we process here is nova, otherwise for
# quantum, the network will be setup by the inclusion of
# openstack-network recipes

if node["openstack"]["compute"]["network"]["service_type"] == "nova"

  platform_options["compute_network_packages"].each do |pkg|
    package pkg do
      options platform_options["package_overrides"]

      action :upgrade
    end
  end

  service "nova-network" do
    service_name platform_options["compute_network_service"]
    supports :status => true, :restart => true
    subscribes :restart, resources("template[/etc/nova/nova.conf]")
    action :enable
  end

else

  node["openstack"]["compute"]["network"]["plugins"].each do |plugin|
    include_recipe "openstack-network::#{plugin}"
  end

end
