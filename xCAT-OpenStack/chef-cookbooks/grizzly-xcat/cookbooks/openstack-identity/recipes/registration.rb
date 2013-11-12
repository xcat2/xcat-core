#
# Cookbook Name:: openstack-identity
# Recipe:: setup
#
# Copyright 2012, Rackspace US, Inc.
# Copyright 2012-2013, Opscode, Inc.
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
identity_endpoint = endpoint "identity-api"

admin_tenant_name = node["openstack"]["identity"]["admin_tenant_name"]
admin_user = node["openstack"]["identity"]["admin_user"]
admin_pass = user_password node["openstack"]["identity"]["admin_user"]
auth_uri = ::URI.decode identity_admin_endpoint.to_s

bootstrap_token = secret "secrets", "openstack_identity_bootstrap_token"

# We need to bootstrap the keystone admin user so that calls
# to keystone_register will succeed, since those provider calls
# use the admin tenant/user/pass to get an admin token.
bash "bootstrap-keystone-admin" do
  # A shortcut bootstrap command was added to python-keystoneclient
  # in early Grizzly timeframe... but we need to do all the commands
  # here manually since the python-keystoneclient package included
  # in CloudArchive (for now) doesn't have it...
  insecure = node["openstack"]["auth"]["validate_certs"] ? "" : " --insecure"
  base_ks_cmd = "keystone#{insecure} --endpoint=#{auth_uri} --token=#{bootstrap_token}"
  code <<-EOF
set -x
function get_id () {
    echo `"$@" | grep ' id ' | awk '{print $4}'`
}
#{base_ks_cmd} tenant-list | grep #{admin_tenant_name}
if [[ $? -eq 1 ]]; then
  ADMIN_TENANT=$(get_id #{base_ks_cmd} tenant-create --name=#{admin_tenant_name})
else
  ADMIN_TENANT=$(#{base_ks_cmd} tenant-list | grep #{admin_tenant_name} | awk '{print $2}')
fi
#{base_ks_cmd} role-list | grep admin
if [[ $? -eq 1 ]]; then
  ADMIN_ROLE=$(get_id #{base_ks_cmd} role-create --name=admin)
else
  ADMIN_ROLE=$(#{base_ks_cmd} role-list | grep admin | awk '{print $2}')
fi
#{base_ks_cmd} user-list | grep #{admin_user}
if [[ $? -eq 1 ]]; then
  ADMIN_USER=$(get_id #{base_ks_cmd} user-create --name=#{admin_user} --pass="#{admin_pass}" --email=#{admin_user}@example.com)
else
  ADMIN_USER=$(#{base_ks_cmd} user-list | grep #{admin_user} | awk '{print $2}')
fi
#{base_ks_cmd} user-role-list --user-id=$ADMIN_USER --tenant-id=$ADMIN_TENANT | grep admin
if [[ $? -eq 1 ]]; then
  #{base_ks_cmd} user-role-add --user-id $ADMIN_USER --role-id $ADMIN_ROLE --tenant-id $ADMIN_TENANT
fi
exit 0
EOF
end

# Register all the tenants specified in the users hash
node["openstack"]["identity"]["users"].values.map do |user_info|
  user_info["roles"].values.push(user_info["default_tenant"])
end.flatten.uniq.each do |tenant_name|
  openstack_identity_register "Register '#{tenant_name}' Tenant" do
    auth_uri auth_uri
    bootstrap_token bootstrap_token
    tenant_name tenant_name
    tenant_description "#{tenant_name} Tenant"

    action :create_tenant
  end
end

# Register all the roles from the users hash
node["openstack"]["identity"]["users"].values.map do |user_info|
  user_info["roles"].keys
end.flatten.uniq.each do |role_name|
  openstack_identity_register "Register '#{role_name.to_s}' Role" do
    auth_uri auth_uri
    bootstrap_token bootstrap_token
    role_name role_name

    action :create_role
  end
end

node["openstack"]["identity"]["users"].each do |username, user_info|
  openstack_identity_register "Register '#{username}' User" do
    auth_uri auth_uri
    bootstrap_token bootstrap_token
    user_name username
    user_pass user_info["password"]
    tenant_name user_info["default_tenant"]
    user_enabled true # Not required as this is the default

    action :create_user
  end

  user_info["roles"].each do |rolename, tenant_list|
    tenant_list.each do |tenantname|
      openstack_identity_register "Grant '#{rolename}' Role to '#{username}' User in '#{tenantname}' Tenant" do
        auth_uri auth_uri
        bootstrap_token bootstrap_token
        user_name username
        role_name rolename
        tenant_name tenantname

        action :grant_role
      end
    end
  end
end

openstack_identity_register "Register Identity Service" do
  auth_uri auth_uri
  bootstrap_token bootstrap_token
  service_name "keystone"
  service_type "identity"
  service_description "Keystone Identity Service"

  action :create_service
end

node.set["openstack"]["identity"]["adminURL"] = identity_admin_endpoint.to_s
node.set["openstack"]["identity"]["internalURL"] = identity_endpoint.to_s
node.set["openstack"]["identity"]["publicURL"] = identity_endpoint.to_s

Chef::Log.info "Keystone AdminURL: #{identity_admin_endpoint.to_s}"
Chef::Log.info "Keystone InternalURL: #{identity_endpoint.to_s}"
Chef::Log.info "Keystone PublicURL: #{identity_endpoint.to_s}"

openstack_identity_register "Register Identity Endpoint" do
  auth_uri auth_uri
  bootstrap_token bootstrap_token
  service_type "identity"
  endpoint_region node["openstack"]["identity"]["region"]
  endpoint_adminurl node["openstack"]["identity"]["adminURL"]
  endpoint_internalurl node["openstack"]["identity"]["adminURL"]
  endpoint_publicurl node["openstack"]["identity"]["publicURL"]

  action :create_endpoint
end

node["openstack"]["identity"]["users"].each do |username, user_info|
  openstack_identity_register "Create EC2 credentials for '#{username}' user" do
    auth_uri auth_uri
    bootstrap_token bootstrap_token
    user_name username
    tenant_name user_info["default_tenant"]

    action :create_ec2_credentials
  end
end
