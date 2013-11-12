#
# Cookbook Name:: openstack-image
# Recipe:: identity_registration
#
# Copyright 2013, AT&T Services, Inc.
# Copyright 2013, Craig Tracey <craigtracey@gmail.com>
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

token = secret "secrets", "openstack_identity_bootstrap_token"
auth_url = ::URI.decode identity_admin_endpoint.to_s

registry_endpoint = endpoint "image-registry"
api_endpoint = endpoint "image-api"

service_pass = service_password "openstack-image"
service_tenant_name = node["openstack"]["image"]["service_tenant_name"]
service_user = node["openstack"]["image"]["service_user"]
service_role = node["openstack"]["image"]["service_role"]
region = node["openstack"]["image"]["region"]

# Register Image Service
openstack_identity_register "Register Image Service" do
  auth_uri auth_url
  bootstrap_token token
  service_name "glance"
  service_type "image"
  service_description "Glance Image Service"

  action :create_service
end

# Register Image Endpoint
openstack_identity_register "Register Image Endpoint" do
  auth_uri auth_url
  bootstrap_token token
  service_type "image"
  endpoint_region region
  endpoint_adminurl api_endpoint.to_s
  endpoint_internalurl api_endpoint.to_s
  endpoint_publicurl api_endpoint.to_s

  action :create_endpoint
end

# Register Service Tenant
openstack_identity_register "Register Service Tenant" do
  auth_uri auth_url
  bootstrap_token token
  tenant_name service_tenant_name
  tenant_description "Service Tenant"
  tenant_enabled true # Not required as this is the default

  action :create_tenant
end

# Register Service User
openstack_identity_register "Register #{service_user} User" do
  auth_uri auth_url
  bootstrap_token token
  tenant_name service_tenant_name
  user_name service_user
  user_pass service_pass
  # String until https://review.openstack.org/#/c/29498/ merged
  user_enabled true

  action :create_user
end

## Grant Admin role to Service User for Service Tenant ##
openstack_identity_register "Grant '#{service_role}' Role to #{service_user} User for #{service_tenant_name} Tenant" do
  auth_uri auth_url
  bootstrap_token token
  tenant_name service_tenant_name
  user_name service_user
  role_name service_role

  action :grant_role
end
