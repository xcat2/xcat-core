#
# Cookbook Name:: openstack-block-storage
# Recipe:: api
#
# Copyright 2012, Rackspace US, Inc.
# Copyright 2012-2013, AT&T Services, Inc.
# Copyright 2013, Opscode, Inc.
# Copyright 2013, SUSE Linux Gmbh.
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

include_recipe "openstack-block-storage::cinder-common"

platform_options = node["openstack"]["block-storage"]["platform"]

platform_options["cinder_api_packages"].each do |pkg|
  package pkg do
    options platform_options["package_overrides"]

    action :upgrade
  end
end

db_type = node['openstack']['db']['volume']['db_type']
platform_options["#{db_type}_python_packages"].each do |pkg|
  package pkg do
    action :upgrade
  end
end

directory ::File.dirname(node["openstack"]["block-storage"]["api"]["auth"]["cache_dir"]) do
  owner node["openstack"]["block-storage"]["user"]
  group node["openstack"]["block-storage"]["group"]
  mode 00700
end

service "cinder-api" do
  service_name platform_options["cinder_api_service"]
  supports :status => true, :restart => true

  action :enable
  subscribes :restart, "template[/etc/cinder/cinder.conf]"
end

identity_admin_endpoint = endpoint "identity-admin"
service_pass = service_password "openstack-block-storage"

execute "cinder-manage db sync"

template "/etc/cinder/api-paste.ini" do
  source "api-paste.ini.erb"
  group  node["openstack"]["block-storage"]["group"]
  owner  node["openstack"]["block-storage"]["user"]
  mode   00644
  variables(
    :identity_admin_endpoint => identity_admin_endpoint,
    :service_pass => service_pass
  )

  notifies :restart, "service[cinder-api]", :immediately
end

template "/etc/cinder/policy.json" do
  source "policy.json.erb"
  owner  node["openstack"]["block-storage"]["user"]
  group  node["openstack"]["block-storage"]["group"]
  mode   00644
  notifies :restart, "service[cinder-api]"
end
