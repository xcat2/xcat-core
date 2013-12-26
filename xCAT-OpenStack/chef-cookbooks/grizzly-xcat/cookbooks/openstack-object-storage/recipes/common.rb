#
# Cookbook Name:: swift
# Recipe:: swift-common
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

class Chef::Recipe
  include DriveUtils
end

include_recipe 'sysctl::default'


#-------------
# stats
#-------------

# optionally statsd daemon for stats collection
if node["swift"]["statistics"]["enabled"]
  node.set['statsd']['relay_server'] = true
  include_recipe 'statsd::server'
end

# find graphing server address
if Chef::Config[:solo] and not node['recipes'].include?("chef-solo-search")
  Chef::Log.warn("This recipe uses search. Chef Solo does not support search.")
  graphite_servers = []
else
  graphite_servers = search(:node, "roles:#{node['swift']['statistics']['graphing_role']} AND chef_environment:#{node.chef_environment}")
end
graphite_host = "127.0.0.1"
unless graphite_servers.empty?
  graphite_host = graphite_servers[0]['network']["ipaddress_#{node['swift']['statistics']['graphing_interface']}"]
end

if node['swift']['statistics']['graphing_ip'].nil?
  node.set['statsd']['graphite_host'] = graphite_host
else
  node.set['statsd']['graphite_host'] = node['swift']['statistics']['graphing_ip']
end

#--------------
# swift common
#--------------

platform_options = node["swift"]["platform"]

# update repository if requested with the ubuntu cloud
case node["platform"]
when "ubuntu"

  Chef::Log.info("Creating apt repository for http://ubuntu-cloud.archive.canonical.com/ubuntu")
  Chef::Log.info("chefspec: #{node['lsb']['codename']}-updates/#{node['swift']['release']}")
  apt_repository "ubuntu_cloud" do
    uri "http://ubuntu-cloud.archive.canonical.com/ubuntu"
    distribution "#{node['lsb']['codename']}-updates/#{node['swift']['release']}"
    components ["main"]
    key "5EDB1B62EC4926EA"
    action :add
  end
end


platform_options["swift_packages"].each do |pkg|
  package pkg do
    action :install
  end
end

directory "/etc/swift" do
  action :create
  owner "swift"
  group "swift"
  mode "0700"
  only_if "/usr/bin/id swift"
end

# determine hash
if node['swift']['swift_secret_databag_name'].nil?
  swifthash = node['swift']['swift_hash']
else
  swift_secrets = Chef::EncryptedDataBagItem.load "secrets", node['swift']['swift_secret_databag_name']
  swifthash = swift_secrets['swift_hash']
end


file "/etc/swift/swift.conf" do
  action :create
  owner "swift"
  group "swift"
  mode "0700"
  content "[swift-hash]\nswift_hash_path_suffix=#{swifthash}\n"
  only_if "/usr/bin/id swift"
end

# need a swift user
user "swift" do
  shell "/bin/bash"
  action :modify
  only_if "/usr/bin/id swift"
end

package "git" do
  action :install
end

# drop a ring puller script
# TODO: make this smarter
git_builder_ip = node["swift"]["git_builder_ip"]
template "/etc/swift/pull-rings.sh" do
  source "pull-rings.sh.erb"
  owner "swift"
  group "swift"
  mode "0700"
  variables({
              :builder_ip => git_builder_ip,
              :service_prefix => platform_options["service_prefix"]
            })
  only_if "/usr/bin/id swift"
end

execute "/etc/swift/pull-rings.sh" do
  cwd "/etc/swift"
  only_if "[ -x /etc/swift/pull-rings.sh ]"
end
