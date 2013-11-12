#
# Cookbook Name:: openstack-ops-database
# Recipe:: openstack-db
#
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

class ::Chef::Recipe
  include ::Openstack
end

db_create_with_user(
  "compute",
  node["openstack"]["compute"]["db"]["username"],
  db_password("nova")
)

db_create_with_user(
  "dashboard",
  node["openstack"]["dashboard"]["db"]["username"],
  db_password("horizon")
)

db_create_with_user(
  "identity",
  node["openstack"]["identity"]["db"]["username"],
  db_password("keystone")
)

db_create_with_user(
  "image",
  node["openstack"]["image"]["db"]["username"],
  db_password("glance")
)

db_create_with_user(
  "metering",
  node["openstack"]["metering"]["db"]["username"],
  db_password("ceilometer")
)

db_create_with_user(
  "network",
  node["openstack"]["network"]["db"]["username"],
  db_password("quantum")
)

db_create_with_user(
  "volume",
  node["openstack"]["block-storage"]["db"]["username"],
  db_password("cinder")
)
