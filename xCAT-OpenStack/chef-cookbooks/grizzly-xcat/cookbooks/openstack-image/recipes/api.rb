#
# Cookbook Name:: openstack-image
# Recipe:: api
#
# Copyright 2012, Rackspace US, Inc.
# Copyright 2012-2013, Opscode, Inc.
# Copyright 2012-2013, AT&T Services, Inc.
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

require "uri"

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

package "curl" do
  action :install
end

platform_options["image_packages"].each do |pkg|
  package pkg do
    action :upgrade
  end
end

service "image-api" do
  service_name platform_options["image_api_service"]
  supports :status => true, :restart => true

  action :enable
end

directory "/etc/glance" do
  owner node["openstack"]["image"]["user"]
  group node["openstack"]["image"]["group"]
  mode  00700
end

directory ::File.dirname node["openstack"]["image"]["api"]["auth"]["cache_dir"] do
  owner node["openstack"]["image"]["user"]
  group node["openstack"]["image"]["group"]
  mode 00700
end

template "/etc/glance/policy.json" do
  source "policy.json.erb"
  owner node["openstack"]["image"]["user"]
  group node["openstack"]["image"]["group"]
  mode   00644

  notifies :restart, "service[image-api]", :immediately
end

glance = node["openstack"]["image"]

identity_endpoint = endpoint "identity-api"
identity_admin_endpoint = endpoint "identity-admin"
service_pass = service_password "openstack-image"

#TODO(jaypipes): Move this logic and stuff into the openstack-common
# library cookbook.
auth_uri = identity_endpoint.to_s
if node["openstack"]["image"]["api"]["auth"]["version"] != "v2.0"
  # The auth_uri should contain /v2.0 in most cases, but if the
  # auth_version is v3.0, we leave it off. This is only necessary
  # for environments that need to support V3 non-default-domain
  # tokens, which is really the only reason to set version to
  # something other than v2.0 (the default)
  auth_uri = auth_uri.gsub('/v2.0', '')
end

db_user = node["openstack"]["image"]["db"]["username"]
db_pass = db_password "glance"
sql_connection = db_uri("image", db_user, db_pass)

registry_endpoint = endpoint "image-registry"
api_endpoint = endpoint "image-api"
service_pass = service_password "openstack-image"
service_tenant_name = node["openstack"]["image"]["service_tenant_name"]
service_user = node["openstack"]["image"]["service_user"]

# Possible combinations of options here
# - default_store=file
#     * no other options required
# - default_store=swift
#     * if swift_store_auth_address is not defined
#         - default to local swift
#     * else if swift_store_auth_address is defined
#         - get swift_store_auth_address, swift_store_user, swift_store_key, and
#           swift_store_auth_version from the node attributes and use them to connect
#           to the swift compatible API service running elsewhere - possibly
#           Rackspace Cloud Files.
if glance["api"]["swift_store_auth_address"].nil?
  swift_store_auth_address = auth_uri
  swift_store_user="#{service_tenant_name}:#{service_user}"
  swift_user_tenant = nil
  swift_store_key = service_pass
  swift_store_auth_version=2
else
  swift_store_auth_address=glance["api"]["swift_store_auth_address"]
  swift_user_tenant = glance["api"]["swift_user_tenant"]
  swift_store_user=glance["api"]["swift_store_user"]
  swift_store_key = service_password swift_store_user
  swift_store_auth_version=glance["api"]["swift_store_auth_version"]
end

glance_flavor = "keystone"
if glance["api"]["cache_management"]
  glance_flavor += "+cachemanagement"
elsif glance["api"]["caching"]
  glance_flavor += "+caching"
end

if node["openstack"]["image"]["api"]["bind_interface"].nil?
  bind_address = api_endpoint.host
else
  bind_address = address_for node["openstack"]["image"]["api"]["bind_interface"]
end

template "/etc/glance/glance-api.conf" do
  source "glance-api.conf.erb"
  owner node["openstack"]["image"]["user"]
  group node["openstack"]["image"]["group"]
  mode   00644
  variables(
    :api_bind_address => bind_address,
    :api_bind_port => api_endpoint.port,
    :registry_ip_address => registry_endpoint.host,
    :registry_port => registry_endpoint.port,
    :sql_connection => sql_connection,
    :glance_flavor => glance_flavor,
    :auth_uri => auth_uri,
    :identity_admin_endpoint => identity_admin_endpoint,
    :service_pass => service_pass,
    :swift_store_key => swift_store_key,
    :swift_user_tenant => swift_user_tenant,
    :swift_store_user => swift_store_user,
    :swift_store_auth_address => swift_store_auth_address,
    :swift_store_auth_version => swift_store_auth_version
  )

  notifies :restart, "service[image-api]", :immediately
end

template "/etc/glance/glance-api-paste.ini" do
  source "glance-api-paste.ini.erb"
  owner node["openstack"]["image"]["user"]
  group node["openstack"]["image"]["group"]
  mode   00644

  notifies :restart, "service[image-api]", :immediately
end

template "/etc/glance/glance-cache.conf" do
  source "glance-cache.conf.erb"
  owner node["openstack"]["image"]["user"]
  group node["openstack"]["image"]["group"]
  mode   00644
  variables(
    :registry_ip_address => registry_endpoint.host,
    :registry_port => registry_endpoint.port
  )

  notifies :restart, "service[image-api]"
end

#TODO(jaypipes) I don't think this even exists or at least isn't
# used, since the Glance cache middleware goes in the api-paste.ini...
template "/etc/glance/glance-cache-paste.ini" do
  source "glance-cache-paste.ini.erb"
  owner node["openstack"]["image"]["user"]
  group node["openstack"]["image"]["group"]
  mode   00644

  notifies :restart, "service[image-api]"
end

template "/etc/glance/glance-scrubber.conf" do
  source "glance-scrubber.conf.erb"
  owner node["openstack"]["image"]["user"]
  group node["openstack"]["image"]["group"]
  mode   00644
  variables(
    :registry_ip_address => registry_endpoint.host,
    :registry_port => registry_endpoint.port
  )
end

# Configure glance-cache-pruner to run every 30 minutes
cron "glance-cache-pruner" do
  minute "*/30"
  command "/usr/bin/glance-cache-pruner > /dev/null 2>&1"
end

# Configure glance-cache-cleaner to run at 00:01 everyday
cron "glance-cache-cleaner" do
  minute  "01"
  hour    "00"
  command "/usr/bin/glance-cache-cleaner > /dev/null 2>&1"
end

template "/etc/glance/glance-scrubber-paste.ini" do
  source "glance-scrubber-paste.ini.erb"
  owner node["openstack"]["image"]["user"]
  group node["openstack"]["image"]["group"]
  mode   00644
end

if node["openstack"]["image"]["image_upload"]
  node["openstack"]["image"]["upload_images"].each do |img|
    openstack_image_image "Image setup for #{img.to_s}" do
      image_url node["openstack"]["image"]["upload_image"][img.to_sym]
      image_name img
      identity_user service_user
      identity_pass service_pass
      identity_tenant service_tenant_name
      identity_uri auth_uri
      action :upload
    end
  end
end
