#
# Cookbook Name:: openstack-metering
# Recipe:: identity_registration
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

require "uri"

class ::Chef::Recipe
  include ::Openstack
end

api_endpoint = endpoint "metering-api"
identity_admin_endpoint = endpoint "identity-admin"
bootstrap_token = secret "secrets", "openstack_identity_bootstrap_token"
auth_uri = ::URI.decode identity_admin_endpoint.to_s

openstack_identity_register "Register Metering Service" do
  auth_uri auth_uri
  bootstrap_token bootstrap_token
  service_name "ceilometer"
  service_type "metering"
  service_description "Ceilometer Service"

  action :create_service
end

openstack_identity_register "Register Metering Endpoint" do
  auth_uri auth_uri
  bootstrap_token bootstrap_token
  service_type "metering"
  endpoint_region node["openstack"]["metering"]["region"]
  endpoint_adminurl ::URI.decode api_endpoint.to_s
  endpoint_internalurl ::URI.decode api_endpoint.to_s
  endpoint_publicurl ::URI.decode api_endpoint.to_s

  action :create_endpoint
end
