#
# Cookbook Name:: openstack-identity
# Recipe:: server
#
# Copyright 2012, Rackspace US, Inc.
# Copyright 2012-2013, Opscode, Inc.
# Copyright 2013 SUSE LINUX Products GmbH.
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

require "uri"

class ::Chef::Recipe
  include ::Openstack
end

if node["openstack"]["identity"]["syslog"]["use"]
  include_recipe "openstack-common::logging"
end

platform_options = node["openstack"]["identity"]["platform"]

db_type = node['openstack']['db']['identity']['db_type']
platform_options["#{db_type}_python_packages"].each do |pkg|
  package pkg do
    action :install
  end
end

platform_options["memcache_python_packages"].each do |pkg|
  package pkg do
    action :install
  end
end

platform_options["keystone_packages"].each do |pkg|
  package pkg do
    options platform_options["package_options"]

    action :upgrade
  end
end

execute "Keystone: sleep" do
  command "sleep 10s"

  action :nothing
end

service "keystone" do
  service_name platform_options["keystone_service"]
  supports :status => true, :restart => true

  action [ :enable ]

  notifies :run, "execute[Keystone: sleep]", :immediately
end

directory "/etc/keystone" do
  owner node["openstack"]["identity"]["user"]
  group node["openstack"]["identity"]["group"]
  mode  00700
end

directory node["openstack"]["identity"]["signing"]["basedir"] do
  owner node["openstack"]["identity"]["user"]
  group node["openstack"]["identity"]["group"]
  mode  00700

  only_if { node["openstack"]["auth"]["strategy"] == "pki" }
end

file "/var/lib/keystone/keystone.db" do
  action :delete
end

execute "keystone-manage pki_setup" do
  user node["openstack"]["identity"]["user"]

  only_if { node["openstack"]["auth"]["strategy"] == "pki" }
  not_if { ::FileTest.exists? node["openstack"]["identity"]["signing"]["keyfile"] }
end

identity_admin_endpoint = endpoint "identity-admin"
identity_endpoint = endpoint "identity-api"
compute_endpoint = endpoint "compute-api"
ec2_endpoint = endpoint "compute-ec2-api"
image_endpoint = endpoint "image-api"
network_endpoint = endpoint "network-api"
volume_endpoint = endpoint "volume-api"

db_user = node["openstack"]["identity"]["db"]["username"]
db_pass = db_password "keystone"
sql_connection = db_uri("identity", db_user, db_pass)

bootstrap_token = secret "secrets", "openstack_identity_bootstrap_token"

ip_address = address_for node["openstack"]["identity"]["bind_interface"]

# If the search role is set, we search for memcache
# servers via a Chef search. If not, we look at the
# memcache.servers attribute.
memcache_servers = memcached_servers.join ","  # from openstack-common lib

uris = {
  'identity-admin' => identity_admin_endpoint.to_s.gsub('%25','%'),
  'identity' => identity_endpoint.to_s.gsub('%25','%'),
  'image' => image_endpoint.to_s.gsub('%25','%'),
  'compute' => compute_endpoint.to_s.gsub('%25','%'),
  'ec2' => ec2_endpoint.to_s.gsub('%25','%'),
  'network' => network_endpoint.to_s.gsub('%25','%'),
  'volume' => volume_endpoint.to_s.gsub('%25','%')
}

# These configuration endpoints must not have the path (v2.0, etc)
# added to them, as these values are used in returning the version
# listing information from the root / endpoint.
ie = identity_endpoint
public_endpoint = "#{ie.scheme}://#{ie.host}:#{ie.port}/"
ae = identity_admin_endpoint
admin_endpoint = "#{ae.scheme}://#{ae.host}:#{ae.port}/"

template "/etc/keystone/keystone.conf" do
  source "keystone.conf.erb"
  owner node["openstack"]["identity"]["user"]
  group node["openstack"]["identity"]["group"]
  mode   00644
  variables(
    :sql_connection => sql_connection,
    :ip_address => ip_address,
    "bootstrap_token" => bootstrap_token,
    "memcache_servers" => memcache_servers,
    "uris" => uris,
    "public_endpoint" => public_endpoint,
    "admin_endpoint" => admin_endpoint,
    "ldap" => node["openstack"]["identity"]["ldap"]
  )

  notifies :restart, "service[keystone]", :immediately
end

template "/etc/keystone/default_catalog.templates" do
  source "default_catalog.templates.erb"
  owner node["openstack"]["identity"]["user"]
  group node["openstack"]["identity"]["group"]
  mode   00644
  variables(
    "uris" => uris
  )

  notifies :restart, "service[keystone]", :immediately
  only_if { node["openstack"]["identity"]["catalog"]["backend"] == "templated" }
end

# sync db after keystone.conf is generated
execute "keystone-manage db_sync" do
  only_if { node["openstack"]["identity"]["db"]["migrate"] }
end
