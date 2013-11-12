#
# Cookbook Name:: swift
# Recipe:: setup
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

include_recipe "openstack-object-storage::common"

# make sure we die if there are multiple swift-setups
if Chef::Config[:solo]
  Chef::Application.fatal! "This recipe uses search. Chef Solo does not support search."
else
  setup_role_count = search(:node, "chef_environment:#{node.chef_environment} AND roles:swift-setup").length
  if setup_role_count > 1
    Chef::Application.fatal! "You can only have one node with the swift-setup role"
  end
end

unless node["swift"]["service_pass"]
  Chef::Log.info("Running swift setup - setting swift passwords")
end

platform_options = node["swift"]["platform"]

# install platform-specific packages
platform_options["proxy_packages"].each do |pkg|
  package pkg do
    action :upgrade
    options platform_options["override_options"]
  end
end

package "python-swauth" do
  action :upgrade
  only_if { node["swift"]["authmode"] == "swauth" }
end

package "python-swift-informant" do
  action :upgrade
  only_if { node["swift"]["use_informant"] }
end

package "python-keystone" do
  action :upgrade
  only_if { node["swift"]["authmode"] == "keystone" }
end
