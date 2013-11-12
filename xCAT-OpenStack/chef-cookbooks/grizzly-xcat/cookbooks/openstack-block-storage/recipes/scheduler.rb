#
# Cookbook Name:: openstack-block-storage
# Recipe:: scheduler
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

include_recipe "openstack-block-storage::cinder-common"

platform_options = node["openstack"]["block-storage"]["platform"]

platform_options["cinder_scheduler_packages"].each do |pkg|
  package pkg do
    options platform_options["package_overrides"]

    action :upgrade
  end
end

# FIXME this can be removed if/when 1:2013.1-0ubuntu2 makes it into precise
if platform?("ubuntu") && (node["platform_version"].to_f == 12.04)
  include_recipe "python"
  python_pip "stevedore" do
    action :upgrade
  end
end

db_type = node['openstack']['db']['volume']['db_type']
platform_options["#{db_type}_python_packages"].each do |pkg|
  package pkg do
    action :upgrade
  end
end

service "cinder-scheduler" do
  service_name platform_options["cinder_scheduler_service"]
  supports :status => true, :restart => true

  action [ :enable, :start ]
  subscribes :restart, "template[/etc/cinder/cinder.conf]"
end

audit_bin_dir = platform?("ubuntu") ? "/usr/bin" : "/usr/local/bin"
audit_log = node["openstack"]["block-storage"]["cron"]["audit_logfile"]

if node["openstack"]["metering"]
  scheduler_role = node["openstack"]["block-storage"]["scheduler_role"]
  results = search(:node, "roles:#{scheduler_role}")
  cron_node = results.collect{|a| a.name}.sort[0]
  Chef::Log.debug("Volume audit cron node: #{cron_node}")

  cron "cinder-volume-usage-audit" do
    day node["openstack"]["block-storage"]["cron"]["day"] || '*'
    hour node["openstack"]["block-storage"]["cron"]["hour"] || '*'
    minute node["openstack"]["block-storage"]["cron"]["minute"]
    month node["openstack"]["block-storage"]["cron"]["month"] || '*'
    weekday node["openstack"]["block-storage"]["cron"]["weekday"] || '*'
    command "#{audit_bin_dir}/cinder-volume-usage-audit > #{audit_log} 2>&1"
    action cron_node == node.name ? :create : :delete
    user node["openstack"]["block-storage"]["user"]
  end
end
