#
# Cookbook Name:: openstack-compute
# Recipe:: compute
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

class ::Chef::Recipe
  include ::Openstack
end

include_recipe "openstack-compute::nova-common"
include_recipe "openstack-compute::api-metadata"
unless node.run_list.include? "openstack-network::server"
  include_recipe "openstack-compute::network"
end

platform_options = node["openstack"]["compute"]["platform"]
# Note(maoy): Make sure compute_compute_packages is not a node object.
# so that this is compatible with chef 11 when being changed later.
compute_compute_packages = Array.new(platform_options["compute_compute_packages"])

if platform?(%w(ubuntu))
  if node["openstack"]["compute"]["libvirt"]["virt_type"] == "kvm"
    compute_compute_packages << "nova-compute-kvm"
  elsif node["openstack"]["compute"]["libvirt"]["virt_type"] == "qemu"
    compute_compute_packages << "nova-compute-qemu"
  end
end

compute_compute_packages.each do |pkg|
  package pkg do
    options platform_options["package_overrides"]

    action :upgrade
  end
end

# Installing nfs client packages because in grizzly, cinder nfs is supported
# Never had to install iscsi packages because nova-compute package depends it
# So volume-attach 'just worked' before - alop
platform_options["nfs_packages"].each do |pkg|
  package pkg do
    options platform_options["package_overrides"]

    action :upgrade
  end
end

cookbook_file "/etc/nova/nova-compute.conf" do
  source "nova-compute.conf"
  mode   00644

  action :create
end

service "nova-compute" do
  service_name platform_options["compute_compute_service"]
  supports :status => true, :restart => true
  subscribes :restart, resources("template[/etc/nova/nova.conf]")

  action [:enable, :start]
end

include_recipe "openstack-compute::libvirt"
