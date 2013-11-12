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

class ::Chef::Recipe
  include ::Openstack
end

if node["openstack"]["block-storage"]["syslog"]["use"]
  include_recipe "openstack-common::logging"
end

platform_options = node["openstack"]["block-storage"]["platform"]

platform_options["cinder_common_packages"].each do |pkg|
  package pkg do
    options platform_options["package_overrides"]

    action :upgrade
  end
end

db_user = node["openstack"]["block-storage"]["db"]["username"]
db_pass = db_password "cinder"
sql_connection = db_uri("volume", db_user, db_pass)

if node["openstack"]["block-storage"]["rabbit"]["ha"]
  rabbit_hosts = rabbit_servers
end
rabbit_pass = user_password node["openstack"]["block-storage"]["rabbit"]["username"]

glance_api_endpoint = endpoint "image-api"

directory "/etc/cinder" do
  group  node["openstack"]["block-storage"]["group"]
  owner  node["openstack"]["block-storage"]["user"]
  mode 00750
  action :create
end

template "/etc/cinder/cinder.conf" do
  source "cinder.conf.erb"
  group  node["openstack"]["block-storage"]["group"]
  owner  node["openstack"]["block-storage"]["user"]
  mode   00644
  variables(
    :sql_connection => sql_connection,
    :rabbit_password => rabbit_pass,
    :rabbit_hosts => rabbit_hosts,
    :glance_host => glance_api_endpoint.host,
    :glance_port => glance_api_endpoint.port
  )
end
