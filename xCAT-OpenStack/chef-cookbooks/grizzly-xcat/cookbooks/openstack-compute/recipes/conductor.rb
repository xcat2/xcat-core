#
# Cookbook Name:: nova
# Recipe:: conductor
#
# Copyright 2012, Rackspace US, Inc.
# Copyright (c) 2013 SUSE LINUX Products GmbH, Nuernberg, Germany.
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

platform_options["compute_conductor_packages"].each do |pkg|
  package pkg do
    options platform_options["package_overrides"]
    action :upgrade
  end
end

service "nova-conductor" do
  service_name platform_options["compute_conductor_service"]
  supports :status => true, :restart => true
  subscribes :restart, resources("template[/etc/nova/nova.conf]")
  action [:enable, :start]
end
