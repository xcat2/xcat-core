#
# Cookbook Name:: openstack-ops-database
# Recipe:: default
#
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

default["openstack"]["db"]["bind_interface"] = "lo"

# Platform defaults
case platform
when "fedora", "redhat", "centos" # :pragma-foodcritic: ~FC024 - won"t fix this
  default["openstack"]["db"]["platform"]["mysql_python_packages"] = [ "MySQL-python" ]
  default["openstack"]["db"]["platform"]["postgresql_python_packages"] = [ "python-psycopg2" ]
when "suse"
  default["openstack"]["db"]["platform"]["mysql_python_packages"] = [ "python-mysql" ]
  default["openstack"]["db"]["platform"]["postgresql_python_packages"] = [ "python-psycopg2" ]
when "ubuntu"
  default["openstack"]["db"]["platform"]["mysql_python_packages"] = [ "python-mysqldb" ]
  default["openstack"]["db"]["platform"]["postgresql_python_packages"] = [ "python-psycopg2" ]
end
