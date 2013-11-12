#
# Cookbook Name:: openssh
# Recipe:: default
#
# Copyright 2008-2009, Opscode, Inc.
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

def listen_addr_for interface, type
  interface_node = node['network']['interfaces'][interface]['addresses']

  interface_node.select { |address, data| data['family'] == type }[0][0]
end

node['openssh']['package_name'].each do |pkg|
  package pkg
end

service "ssh" do
  service_name node['openssh']['service_name']
  supports value_for_platform(
    "debian" => { "default" => [ :restart, :reload, :status ] },
    "ubuntu" => {
      "8.04" => [ :restart, :reload ],
      "default" => [ :restart, :reload, :status ]
    },
    "centos" => { "default" => [ :restart, :reload, :status ] },
    "redhat" => { "default" => [ :restart, :reload, :status ] },
    "fedora" => { "default" => [ :restart, :reload, :status ] },
    "scientific" => { "default" => [ :restart, :reload, :status ] },
    "arch" => { "default" => [ :restart ] },
    "default" => { "default" => [:restart, :reload ] }
  )
  action [ :enable, :start ]
end

template "/etc/ssh/ssh_config" do
  source "ssh_config.erb"
  mode '0644'
  owner 'root'
  group 'root'
  variables(:settings => node['openssh']['client'])
end

if node['openssh']['listen_interfaces']
  listen_addresses = Array.new.tap do |a|
    node['openssh']['listen_interfaces'].each_pair do |interface, type|
      a << listen_addr_for(interface, type)
    end
  end

  node.set['openssh']['server']['listen_address'] = listen_addresses
end

template "/etc/ssh/sshd_config" do
  source "sshd_config.erb"
  mode '0644'
  owner 'root'
  group 'root'
  variables(:settings => node['openssh']['server'])
  notifies :restart, "service[ssh]"
end
