#
# Cookbook Name:: openstack-metering
# Recipe:: common
#
# Copyright 2013, AT&T Services, Inc.
# Copyright 2013, Craig Tracey <craigtracey@gmail.com>
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

if node["openstack"]["metering"]["syslog"]["use"]
  include_recipe "openstack-common::logging"
end

platform = node["openstack"]["metering"]["platform"]
platform["common_packages"].each do |pkg|
  package pkg
end

rabbit_pass = user_password node["openstack"]["metering"]["rabbit"]["username"]

db_info = db "metering"
db_user = node["openstack"]["metering"]["db"]["username"]
db_pass = db_password "ceilometer"
db_query = db_info["db_type"] == "mysql" ? "?charset=utf8" : ""
db_uri = db_uri("metering", db_user, db_pass).to_s + db_query

service_user = node["openstack"]["metering"]["service_user"]
service_pass = service_password "openstack-compute"
service_tenant = node["openstack"]["metering"]["service_tenant_name"]

identity_endpoint = endpoint "identity-api"
image_endpoint = endpoint "image-api"

Chef::Log.debug("openstack-metering::common:service_user|#{service_user}")
Chef::Log.debug("openstack-metering::common:service_tenant|#{service_tenant}")
Chef::Log.debug("openstack-metering::common:identity_endpoint|#{identity_endpoint.to_s}")

directory node["openstack"]["metering"]["conf_dir"] do
  owner node["openstack"]["metering"]["user"]
  group node["openstack"]["metering"]["group"]
  mode  00750

  action :create
end

template node["openstack"]["metering"]["conf"] do
  source "ceilometer.conf.erb"
  owner  node["openstack"]["metering"]["user"]
  group  node["openstack"]["metering"]["group"]
  mode   00640

  variables(
    :auth_uri => ::URI.decode(identity_endpoint.to_s),
    :database_connection => db_uri,
    :image_endpoint => image_endpoint,
    :identity_endpoint => identity_endpoint,
    :rabbit_pass => rabbit_pass,
    :service_pass => service_pass,
    :service_tenant_name => service_tenant,
    :service_user => service_user
  )
end

cookbook_file "/etc/ceilometer/policy.json" do
  source "policy.json"
  mode   00640
  owner  node["openstack"]["metering"]["user"]
  group  node["openstack"]["metering"]["group"]
end
