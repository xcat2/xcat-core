#
# Cookbook Name:: openstack-dashboard
# Recipe:: server
#
# Copyright 2012, Rackspace US, Inc.
# Copyright 2012-2013, AT&T Services, Inc.
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

require "uri"

class ::Chef::Recipe
  include ::Openstack
end

#
# Workaround to install apache2 on a fedora machine with selinux set to enforcing
# TODO(breu): this should move to a subscription of the template from the apache2 recipe
#             and it should simply be a restorecon on the configuration file(s) and not
#             change the selinux mode
#
execute "set-selinux-permissive" do
  command "/sbin/setenforce Permissive"
  action :run

  only_if "[ ! -e /etc/httpd/conf/httpd.conf ] && [ -e /etc/redhat-release ] && [ $(/sbin/sestatus | grep -c '^Current mode:.*enforcing') -eq 1 ]"
end

platform_options = node["openstack"]["dashboard"]["platform"]

include_recipe "apache2"
include_recipe "apache2::mod_wsgi"
include_recipe "apache2::mod_rewrite"
include_recipe "apache2::mod_ssl"

#
# Workaround to re-enable selinux after installing apache on a fedora machine that has
# selinux enabled and is currently permissive and the configuration set to enforcing.
# TODO(breu): get the other one working and this won't be necessary
#
execute "set-selinux-enforcing" do
  command "/sbin/setenforce Enforcing ; restorecon -R /etc/httpd"
  action :run

  only_if "[ -e /etc/httpd/conf/httpd.conf ] && [ -e /etc/redhat-release ] && [ $(/sbin/sestatus | grep -c '^Current mode:.*permissive') -eq 1 ] && [ $(/sbin/sestatus | grep -c '^Mode from config file:.*enforcing') -eq 1 ]"
end

identity_admin_endpoint = endpoint "identity-admin"
auth_admin_uri = ::URI.decode identity_admin_endpoint.to_s
identity_endpoint = endpoint "identity-api"
auth_uri = ::URI.decode identity_endpoint.to_s

db_pass = db_password "horizon"
db_info = db "dashboard"

python_packages = platform_options["#{db_info['db_type']}_python_packages"]
(platform_options["horizon_packages"] + python_packages).each do |pkg|
  package pkg do
    action :upgrade
    options platform_options["package_overrides"]
  end
end

if node["openstack"]["dashboard"]["session_backend"] == "memcached"
  platform_options["memcache_python_packages"].each do |pkg|
    package pkg
  end
end

memcached = memcached_servers

template node["openstack"]["dashboard"]["local_settings_path"] do
  source "local_settings.py.erb"
  owner  "root"
  group  "root"
  mode   00644

  variables(
    :db_pass => db_pass,
    :db_info => db_info,
    :auth_uri => auth_uri,
    :auth_admin_uri => auth_admin_uri,
    :memcached_servers => memcached
  )

  notifies :restart, "service[apache2]"
end

# FIXME: this shouldn't run every chef run
execute "openstack-dashboard syncdb" do
  cwd "/usr/share/openstack-dashboard"
  environment ({'PYTHONPATH' => '/etc/openstack-dashboard:/usr/share/openstack-dashboard:$PYTHONPATH'})
  command "python manage.py syncdb --noinput"
  action :run
  # not_if "/usr/bin/mysql -u root -e 'describe #{node["dash"]["db"]}.django_content_type'"
end

cookbook_file "#{node["openstack"]["dashboard"]["ssl"]["dir"]}/certs/#{node["openstack"]["dashboard"]["ssl"]["cert"]}" do
  source "horizon.pem"
  mode   00644
  owner  "root"
  group  "root"

  notifies :run, "execute[restore-selinux-context]", :immediately
end

case node["platform"]
when "ubuntu","debian"
  grp = "ssl-cert"
else
  grp = "root"
end

cookbook_file "#{node["openstack"]["dashboard"]["ssl"]["dir"]}/private/#{node["openstack"]["dashboard"]["ssl"]["key"]}" do
  source "horizon.key"
  mode   00640
  owner  "root"
  group  grp # Don't know about fedora

  notifies :run, "execute[restore-selinux-context]", :immediately
end

# stop apache bitching
directory "#{node["openstack"]["dashboard"]["dash_path"]}/.blackhole" do
  owner "root"
  action :create
end

template node["openstack"]["dashboard"]["apache"]["sites-path"] do
  source "dash-site.erb"
  owner  "root"
  group  "root"
  mode   00644

  variables(
    :ssl_cert_file => "#{node["openstack"]["dashboard"]["ssl"]["dir"]}/certs/#{node["openstack"]["dashboard"]["ssl"]["cert"]}",
    :ssl_key_file => "#{node["openstack"]["dashboard"]["ssl"]["dir"]}/private/#{node["openstack"]["dashboard"]["ssl"]["key"]}"
  )

  notifies :run, "execute[restore-selinux-context]", :immediately
end

file "#{node["apache"]["dir"]}/conf.d/openstack-dashboard.conf" do
  action :delete
  backup false

  only_if { platform?("fedora", "redhat", "centos") } # :pragma-foodcritic: ~FC024 - won't fix this
end

# ubuntu includes their own branding - we need to delete this until ubuntu makes this a
# configurable paramter
package "openstack-dashboard-ubuntu-theme" do
  action :purge

  only_if { platform?("ubuntu")}
end

# The `apache_site` provided by the apache2 cookbook
# is not an LWRP. Guards do not apply to definitions.
# http://tickets.opscode.com/browse/CHEF-778
if platform?("debian","ubuntu") then
  apache_site "000-default" do
    enable false
  end
elsif platform?("fedora") then
  apache_site "default" do
    enable false

    notifies :run, "execute[restore-selinux-context]", :immediately
  end
end

apache_site "openstack-dashboard" do
  enable true

  notifies :run, "execute[restore-selinux-context]", :immediately
  notifies :reload, "service[apache2]", :immediately
end

execute "restore-selinux-context" do
  command "restorecon -Rv /etc/httpd /etc/pki; chcon -R -t httpd_sys_content_t /usr/share/openstack-dashboard || :"
  action :nothing

  only_if { platform?("fedora") }
end

# TODO(shep)
# Horizon has a forced dependency on there being a volume service endpoint in your keystone catalog
# https://answers.launchpad.net/horizon/+question/189551
