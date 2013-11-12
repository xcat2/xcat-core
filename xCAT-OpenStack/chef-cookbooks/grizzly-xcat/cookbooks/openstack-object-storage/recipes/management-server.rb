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
  platform_options["swauth_packages"].each.each do |pkg|
    package pkg do
      action :install
      options platform_options["override_options"] # retain configs
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

template "/etc/swift/dispersion.conf" do
  source "dispersion.conf.erb"
  owner "swift"
  group "swift"
  mode "0600"
  variables("auth_url" => node["swift"]["auth_url"],
            "auth_user" => auth_user,
            "auth_key" => auth_key)
end
