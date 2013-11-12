#
# Cookbook Name:: openstack-ops-database
# Recipe:: mysql-server
#
# Copyright 2013, Opscode, Inc.
# Copyright 2012-2013, Rackspace US, Inc.
# Copyright 2013, AT&T Services, Inc.
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

listen_address = address_for node["openstack"]["db"]["bind_interface"]

node.override["mysql"]["bind_address"] = listen_address
node.override["mysql"]["tunable"]["innodb_thread_concurrency"] = "0"
node.override["mysql"]["tunable"]["innodb_commit_concurrency"] = "0"
node.override["mysql"]["tunable"]["innodb_read_io_threads"] = "4"
node.override["mysql"]["tunable"]["innodb_flush_log_at_trx_commit"] = "2"

include_recipe "openstack-ops-database::mysql-client"
include_recipe "mysql::server"

mysql_connection_info = {
  :host => "localhost",
  :username => "root",
  :password => node["mysql"]["server_root_password"]
}

mysql_database "FLUSH PRIVILEGES" do
  connection mysql_connection_info
  sql "FLUSH PRIVILEGES"
  action :query
end

# Unfortunately, this is needed to get around a MySQL bug
# that repeatedly shows its face when running this in Vagabond
# containers:
#
# http://bugs.mysql.com/bug.php?id=69644
mysql_database "drop empty localhost user" do
  sql "DELETE FROM mysql.user WHERE User = '' OR Password = ''"
  connection mysql_connection_info
  action :query
end

mysql_database "test" do
  connection mysql_connection_info
  action :drop
end

mysql_database "FLUSH PRIVILEGES" do
  connection mysql_connection_info
  sql "FLUSH PRIVILEGES"
  action :query
end
