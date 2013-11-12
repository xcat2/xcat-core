#
# Cookbook Name:: erlang
# Recipe:: esl
#
# Author:: Christopher Maier (<cm@opscode.com>)
# Copyright 2013, Opscode, Inc.
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

# Install Erlang/OTP from Erlang Solutions

case node['platform_family']
when 'debian'

  include_recipe 'apt'

  apt_repository 'erlang_solutions_repo' do
    uri 'http://binaries.erlang-solutions.com/debian'
    distribution node['lsb']['codename']
    components ['contrib']
    key 'http://binaries.erlang-solutions.com/debian/erlang_solutions.asc'
    action :add
  end

when 'rhel'
  case node['platform']
  when 'centos', 'fedora'

    if platform?('centos') && node['platform_version'].to_i == 5
      Chef::Log.fatal("Erlang Solutions pacakge repositories are not available for Centos 5")
      raise
    else

      include_recipe 'yum'

      if platform?('centos')
        include_recipe "yum::repoforge"
      end

      yum_key "RPM-KEY-Erlang-Solutions" do
        # Yes, yes, I know the URL has 'debian' in it... that's the address
        url "http://binaries.erlang-solutions.com/debian/erlang_solutions.asc"
        action :add
      end

      # This replicates the files found at
      #   http://binaries.erlang-solutions.com/rpm/fedora/erlang_solutions.repo
      #   http://binaries.erlang-solutions.com/rpm/centos/erlang_solutions.repo
      yum_repository "erlang-solutions" do
        description "#{node['platform']} $releasever - $basearch - Erlang Solutions"
        url "http://binaries.erlang-solutions.com/rpm/#{node['platform']}/$releasever/$basearch"
        key "RPM-KEY-Erlang-Solutions"
        enabled 1
      end
    end
  else
    Chef::Log.fatal("Erlang Solutions pacakge repositories are currently not supported for RHEL family #{node['platform']} systems")
    raise
  end
else
  Chef::Log.fatal("Erlang Solutions pacakge repositories are currently not supported for #{node['platform_family']} systems")
  raise
end

package "esl-erlang" do
  version node['erlang']['esl']['version'] if node['erlang']['esl']['version']
end

# There's a small bug in the package for Ubuntu 10.04... this fixes
# it.  Solution found at
# https://github.com/davidcoallier/bigcouch/blob/f6a6daf7590ecbab4d9dc4747624573b3137dfad/README.md#ubuntu-1004-lts-potential-issues
if platform?("ubuntu") && node['platform_version'] == "10.04"
  bash "ubuntu-10.04-LTS-erlang-fix" do
    user "root"
    cwd "/usr/lib/erlang/man/man5"
    code <<-EOS
      rm modprobe.d.5
      ln -s modprobe.conf.5.gz modprobe.d.5
    EOS
  end
end
