#
# Cookbook Name:: statsd
# Recipe:: server
#
# Copyright 2013, Scott Lampert
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

include_recipe "build-essential"
include_recipe "git"

case node["platform"]
  when "ubuntu", "debian"

    package "nodejs"
    package "debhelper"

    statsd_version = node['statsd']['sha']

    git ::File.join(node['statsd']['tmp_dir'], "statsd") do
      repository node['statsd']['repo']
      reference statsd_version
      action :sync
      notifies :run, "execute[build debian package]"
    end

    # Fix the debian changelog file of the repo
    template ::File.join(node['statsd']['tmp_dir'], "statsd/debian/changelog") do
      source "changelog.erb"
    end

    execute "build debian package" do
      command "dpkg-buildpackage -us -uc"
      cwd ::File.join(node['statsd']['tmp_dir'], "statsd")
      creates ::File.join(node['statsd']['tmp_dir'], "statsd_#{node['statsd']['package_version']}_all.deb")
    end

    dpkg_package "statsd" do
      action :install
      source ::File.join(node['statsd']['tmp_dir'], "statsd_#{node['statsd']['package_version']}_all.deb")
    end

  when "redhat", "centos"
    raise "No support for RedHat or CentOS (yet)."
end

template "/etc/statsd/localConfig.js" do
  source "localConfig.js.erb"
  mode 00644
  notifies :restart, "service[statsd]"
end

cookbook_file "/usr/share/statsd/scripts/start" do
  source "upstart.start"
  owner "root"
  group "root"
  mode 00755
end

cookbook_file "/etc/init/statsd.conf" do
  source "upstart.conf"
  owner "root"
  group "root"
  mode 00644
end

user node['statsd']['user'] do
  comment "statsd"
  system true
  shell "/bin/false"
end

service "statsd" do
  provider Chef::Provider::Service::Upstart
  action [ :enable, :start ]
end
