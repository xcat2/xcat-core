#
# Cookbook Name:: openstack-block-storage
# Recipe:: identity_registration
#
# Copyright 2012, Rackspace US, Inc.
# Copyright 2012-2013, AT&T Services, Inc.
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

require "uri"

class ::Chef::Recipe
  include ::Openstack
end

identity_admin_endpoint = endpoint "identity-admin"
bootstrap_token = secret "secrets", "openstack_identity_bootstrap_token"
auth_uri = ::URI.decode identity_admin_endpoint.to_s
cinder_api_endpoint = endpoint "volume-api"
service_pass = service_password "openstack-block-storage"
region = node["openstack"]["block-storage"]["region"]
service_tenant_name = node["openstack"]["block-storage"]["service_tenant_name"]
service_user = node["openstack"]["block-storage"]["service_user"]
service_role = node["openstack"]["block-storage"]["service_role"]

openstack_identity_register "Register Cinder Volume Service" do
  auth_uri auth_uri
  bootstrap_token bootstrap_token
  service_name "cinder"
  service_type "volume"
  service_description "Cinder Volume Service"
  endpoint_region region
  endpoint_adminurl ::URI.decode cinder_api_endpoint.to_s
  endpoint_internalurl ::URI.decode cinder_api_endpoint.to_s
  endpoint_publicurl ::URI.decode cinder_api_endpoint.to_s

  action :create_service
end

openstack_identity_register "Register Cinder Volume Endpoint" do
  auth_uri auth_uri
  bootstrap_token bootstrap_token
  service_name "cinder"
  service_type "volume"
  service_description "Cinder Volume Service"
  endpoint_region region
  endpoint_adminurl ::URI.decode cinder_api_endpoint.to_s
  endpoint_internalurl ::URI.decode cinder_api_endpoint.to_s
  endpoint_publicurl ::URI.decode cinder_api_endpoint.to_s

  action :create_endpoint
end

openstack_identity_register "Register Cinder Service User" do
  auth_uri auth_uri
  bootstrap_token bootstrap_token
  tenant_name service_tenant_name
  user_name service_user
  user_pass service_pass
  user_enabled true # Not required as this is the default

  action :create_user
end

openstack_identity_register "Grant service Role to Cinder Service User for Cinder Service Tenant" do
  auth_uri auth_uri
  bootstrap_token bootstrap_token
  tenant_name service_tenant_name
  user_name service_user
  role_name service_role

  action :grant_role
end
