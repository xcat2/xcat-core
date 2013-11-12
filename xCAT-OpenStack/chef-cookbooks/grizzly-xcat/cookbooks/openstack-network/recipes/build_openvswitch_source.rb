#
# Cookbook Name:: openstack-network
# Recipe:: build_openvswitch_source
#
# Copyright 2013, AT&T
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

platform_options = node["openstack"]["network"]["platform"]

platform_options["quantum_openvswitch_build_packages"].each do |pkg|
  package pkg do
    action :install
  end
end

ovs_options = node['openstack']['network']['openvswitch']
src_filename = ovs_options['openvswitch_filename']
src_filepath = "#{Chef::Config['file_cache_path']}/#{src_filename}"
extract_path = "#{Chef::Config['file_cache_path']}/#{ovs_options['openvswitch_checksum']}"

remote_file src_filepath do
  source ovs_options['openvswitch_url']
  checksum ovs_options['openvswitch_checksum']
  owner 'root'
  group 'root'
  mode 00644
  not_if { ::File.exists?("#{Chef::Config['file_cache_path']}/#{ovs_options['openvswitch_filename']}") }
end

bash "disable_openvswitch_before_upgrade" do
  cwd '/tmp'
  not_if "dpkg -l | grep openvswitch-switch | grep #{ovs_options['openvswitch_dpkgversion']}"
  code <<-EOH
        # Politely stop OVS
        service openvswitch-switch stop || exit 0

        sleep 2;

        # After stopping it, ensure it's down
        killall -9 ovs-vswitchd || exit 0
        killall -9 ovsdb-server || exit 0
        fi
  EOH
end

bash 'extract_package' do
  cwd ::File.dirname(src_filepath)
  code <<-EOH
        rm -rf #{extract_path}
        mkdir -p #{extract_path}
        tar xzf #{src_filename} -C #{extract_path}
        cd #{extract_path}/#{ovs_options['openvswitch_base_filename']}
        DEB_BUILD_OPTIONS='parallel=8' fakeroot debian/rules binary
        EOH
        not_if "dpkg -l | grep openvswitch-switch | grep #{ovs_options['openvswitch_dpkgversion']}"
        notifies :install, "dpkg_package[openvswitch-common]", :immediately
        notifies :install, "dpkg_package[openvswitch-datapath-dkms]", :immediately
        notifies :install, "dpkg_package[openvswitch-pki]", :immediately
        notifies :install, "dpkg_package[openvswitch-switch]", :immediately
end

dpkg_package "openvswitch-common" do
  source "#{extract_path}/openvswitch-common_#{ovs_options['openvswitch_dpkgversion']}_#{ovs_options['openvswitch_architecture']}.deb"
  action :nothing
end
dpkg_package "openvswitch-common" do
  source "#{extract_path}/openvswitch-common_#{ovs_options['openvswitch_dpkgversion']}_#{ovs_options['openvswitch_architecture']}.deb"
  action :nothing
end

dpkg_package "openvswitch-datapath-dkms" do
  source "#{extract_path}/openvswitch-datapath-dkms_#{ovs_options['openvswitch_dpkgversion']}_all.deb"
  action :nothing
end

dpkg_package "openvswitch-pki" do
  source "#{extract_path}/openvswitch-pki_#{ovs_options['openvswitch_dpkgversion']}_all.deb"
  action :nothing
end

dpkg_package "openvswitch-switch" do
  source "#{extract_path}/openvswitch-switch_#{ovs_options['openvswitch_dpkgversion']}_#{ovs_options['openvswitch_architecture']}.deb"
  action :nothing
end
