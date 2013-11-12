#
# Cookbook Name:: openstack-image
# Recipe:: registry
#
# Copyright 2012, Rackspace US, Inc.
# Copyright 2013, Opscode, Inc.
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

if node["openstack"]["image"]["syslog"]["use"]
  include_recipe "openstack-common::logging"
end

platform_options = node["openstack"]["image"]["platform"]

package "python-keystone" do
  action :install
end

db_user = node["openstack"]["image"]["db"]["username"]
db_pass = db_password "glance"
sql_connection = db_uri("image", db_user, db_pass)

identity_endpoint = endpoint "identity-admin"
registry_endpoint = endpoint "image-registry"
service_pass = service_password "openstack-image"

package "curl" do
  action :install
end

db_type = node['openstack']['db']['identity']['db_type']
platform_options["#{db_type}_python_packages"].each do |pkg|
  package pkg do
    action :install
  end
end

platform_options["image_packages"].each do |pkg|
  package pkg do
    action :upgrade
  end
end

directory ::File.dirname(node["openstack"]["image"]["registry"]["auth"]["cache_dir"]) do
  owner node["openstack"]["image"]["user"]
  group node["openstack"]["image"]["group"]
  mode 00700
end

service "image-registry" do
  service_name platform_options["image_registry_service"]
  supports :status => true, :restart => true

  action :enable
end

# Having to manually version the database because of Ubuntu bug
# https://bugs.launchpad.net/ubuntu/+source/glance/+bug/981111
execute "glance-manage version_control 0" do
  not_if "glance-manage db_version"
  only_if { platform?(%w{ubuntu debian}) }
end

file "/var/lib/glance/glance.sqlite" do
  action :delete
end

directory "/etc/glance" do
  owner node["openstack"]["image"]["user"]
  group node["openstack"]["image"]["group"]
  mode  00700
end

if node["openstack"]["image"]["registry"]["bind_interface"].nil?
  bind_address = registry_endpoint.host
else
  bind_address = address_for node["openstack"]["image"]["registry"]["bind_interface"]
end

template "/etc/glance/glance-registry.conf" do
  source "glance-registry.conf.erb"
  owner  "root"
  group  "root"
  mode   00644
  variables(
    :registry_bind_address => bind_address,
    :registry_port => registry_endpoint.port,
    :sql_connection => sql_connection,
    "identity_endpoint" => identity_endpoint,
    "service_pass" => service_pass
  )

  notifies :restart, "service[image-registry]", :immediately
end

execute "glance-manage db_sync" do
  only_if { node["openstack"]["image"]["db"]["migrate"] }
end

template "/etc/glance/glance-registry-paste.ini" do
  source "glance-registry-paste.ini.erb"
  owner  "root"
  group  "root"
  mode   00644

  notifies :restart, "service[image-registry]", :immediately
end
