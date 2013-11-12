#
# Cookbook Name:: postgresql
# Recipe::yum_pgdg_postgresql
#
# Copyright 2013, DonorsChoose.org
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

######################################
# The PostgreSQL RPM Building Project built repository RPMs for easy
# access to the PGDG yum repositories. Links to RPMs for installation
# are in an attribute so that new versions/platforms can be more
# easily added. (See attributes/default.rb)

repo_rpm_url = node['postgresql']['pgdg']['repo_rpm_url'].
  fetch(node['postgresql']['version']).            # e.g., fetch for "9.1"
  fetch(node['platform']).                         # e.g., fetch for "centos"
  fetch(node['platform_version'].to_f.to_i.to_s).  # e.g., fetch for "5" (truncated "5.7")
  fetch(node['kernel']['machine'])                 # e.g., fetch for "i386" or "x86_64"

# Extract the filename portion from the URL for the PGDG repository RPM.
# E.g., repo_rpm_filename = "pgdg-centos92-9.2-6.noarch.rpm"
repo_rpm_filename = File.basename(repo_rpm_url)

# Extract the package name from the URL for the PGDG repository RPM.
# E.g., repo_rpm_package = "pgdg-centos92"
repo_rpm_package = repo_rpm_filename.split(/-/,3)[0..1].join('-')

######################################
# Install the "PostgreSQL RPM Building Project - Yum Repository" through
# the repo_rpm_url determined above. The /etc/yum.repos.d/pgdg-*.repo
# will provide postgresql9X packages, but you may need to exclude
# postgresql packages from the repository of the distro in order to use
# PGDG repository properly. Conflicts will arise if postgresql9X does
# appear in your distro's repo and you want a more recent patch level.

# Download the PGDG repository RPM as a local file
remote_file "#{Chef::Config[:file_cache_path]}/#{repo_rpm_filename}" do
  source repo_rpm_url
  mode "0644"
end

# Install the PGDG repository RPM from the local file
# E.g., /etc/yum.repos.d/pgdg-91-centos.repo
package repo_rpm_package do
  provider Chef::Provider::Package::Rpm
  source "#{Chef::Config[:file_cache_path]}/#{repo_rpm_filename}"
  action :install
end
