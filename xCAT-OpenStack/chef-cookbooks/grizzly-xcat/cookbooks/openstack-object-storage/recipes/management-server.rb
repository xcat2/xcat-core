#
# Cookbook Name:: swift
# Recipe:: management-server
#
# Copyright 2012, Rackspace US, Inc.
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

include_recipe "openstack-object-storage::common"

# FIXME: This should probably be a role (ring-builder?), so you don't end up
# with multiple repos!
include_recipe "openstack-object-storage::ring-repo"

platform_options = node["swift"]["platform"]

if node["swift"]["authmode"] == "swauth"
  case node["swift"]["swauth_source"]
  when "package"
    platform_options["swauth_packages"].each do |pkg|
      package pkg do
        action :install
        options platform_options["override_options"]
      end
    end
  when "git"
    git "#{Chef::Config[:file_cache_path]}/swauth" do
      repository node["swift"]["swauth_repository"]
      revision   node["swift"]["swauth_version"]
      action :sync
    end

    bash "install_swauth" do
      cwd "#{Chef::Config[:file_cache_path]}/swauth"
      user "root"
      group "root"
      code <<-EOH
        python setup.py install
      EOH
      environment 'PREFIX' => "/usr/local"
    end
  end
end

# determine where to find dispersion login information
if node['swift']['swift_secret_databag_name'].nil?
 auth_user = node["swift"]["dispersion"]["auth_user"]
 auth_key  = node["swift"]["dispersion"]["auth_key"]
else
  swift_secrets = Chef::EncryptedDataBagItem.load "secrets", node['swift']['swift_secret_databag_name']
  auth_user = swift_secrets['dispersion_auth_user']
  auth_key = swift_secrets['dispersion_auth_key']
end

if node['swift']['statistics']['enabled']
  template platform_options["swift_statsd_publish"] do
    source "swift-statsd-publish.py.erb"
    owner "root"
    group "root"
    mode "0755"
  end
  cron "cron_swift_statsd_publish" do
    command "#{platform_options['swift_statsd_publish']} > /dev/null 2>&1"
    minute "*/#{node["swift"]["statistics"]["report_frequency"]}"
  end
end

template "/etc/swift/dispersion.conf" do
  source "dispersion.conf.erb"
  owner "swift"
  group "swift"
  mode "0600"
  variables("auth_url" => node["swift"]["auth_url"],
            "auth_user" => auth_user,
            "auth_key" => auth_key)
end
