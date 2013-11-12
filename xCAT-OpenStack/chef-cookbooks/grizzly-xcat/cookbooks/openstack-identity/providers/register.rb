#
# Cookbook Name:: openstack-identity
# Provider:: register
#
# Copyright 2012, Rackspace US, Inc.
# Copyright 2012-2013, AT&T Services, Inc.
# Copyright 2013, Opscode, Inc.
# Copyright 2013, Craig Tracey <craigtracey@gmail.com>
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

require 'chef/mixin/shell_out'
include Chef::Mixin::ShellOut
include ::Openstack

private
def generate_creds resource
  {
    'OS_SERVICE_ENDPOINT' => resource.auth_uri,
    'OS_SERVICE_TOKEN' => resource.bootstrap_token
  }
end

private
def identity_command resource, cmd, args={}
  keystonecmd = ['keystone'] << cmd
  args.each { |key, val|
    keystonecmd << "--#{key}" << val.to_s
  }
  Chef::Log.debug("Running identity command: #{keystonecmd}")
  rc = shell_out(keystonecmd, :env => generate_creds(resource))
  if rc.exitstatus != 0
    raise RuntimeError, "#{rc.stderr} (#{rc.exitstatus})"
  end
  rc.stdout
end

private
def identity_uuid resource, type, key, value, args={}, uuid_field='id'
  begin
    output = identity_command resource, "#{type}-list", args
    output = prettytable_to_array(output)
    output.each { |obj|
     if obj.has_key?(uuid_field) and obj[key] == value
       return obj[uuid_field]
     end
    }
  rescue RuntimeError => e
    raise RuntimeError, "Could not lookup uuid for #{type}:#{key}=>#{value}. Error was #{e.message}"
  end
  nil
end

action :create_service do
  if node["openstack"]["identity"]["catalog"]["backend"] == "templated"
    Chef::Log.info("Skipping service creation - templated catalog backend in use.")
    new_resource.updated_by_last_action(false)
  else
    begin
      service_uuid = identity_uuid new_resource, "service", "type", new_resource.service_type

      unless service_uuid
        identity_command new_resource, "service-create",
          { 'type' => new_resource.service_type,
            'name' => new_resource.service_name,
            'description' => new_resource.service_description }
        Chef::Log.info("Created service '#{new_resource.service_name}'")
        new_resource.updated_by_last_action(true)
      else
        Chef::Log.info("Service Type '#{new_resource.service_type}' already exists.. Not creating.")
        Chef::Log.info("Service UUID: #{service_uuid}")
        new_resource.updated_by_last_action(false)
      end
    rescue Exception => e
      Chef::Log.error("Unable to create service '#{new_resource.service_name}'")
      Chef::Log.error("Error was: #{e.message}")
      new_resource.updated_by_last_action(false)
    end
  end
end

action :create_endpoint do
  if node["openstack"]["identity"]["catalog"]["backend"] == "templated"
    Chef::Log.info("Skipping endpoint creation - templated catalog backend in use.")
    new_resource.updated_by_last_action(false)
  else
    begin
      service_uuid = identity_uuid new_resource, "service", "type", new_resource.service_type
      unless service_uuid
        Chef::Log.error("Unable to find service type '#{new_resource.service_type}'")
        new_resource.updated_by_last_action(false)
        next
      end

      endpoint_uuid = identity_uuid new_resource, "endpoint", "service_id", service_uuid
      unless endpoint_uuid
        identity_command new_resource, "endpoint-create",
          { 'region' => new_resource.endpoint_region,
            'service_id' => service_uuid,
            'publicurl' => new_resource.endpoint_publicurl,
            'internalurl' => new_resource.endpoint_internalurl,
            'adminurl' => new_resource.endpoint_adminurl }
        Chef::Log.info("Created endpoint for service type '#{new_resource.service_type}'")
        new_resource.updated_by_last_action(true)
      else
        Chef::Log.info("Endpoint already exists for Service Type '#{new_resource.service_type}' already exists.. Not creating.")
        new_resource.updated_by_last_action(false)
      end
    rescue Exception => e
      Chef::Log.error("Unable to create endpoint for service type '#{new_resource.service_type}'")
      Chef::Log.error("Error was: #{e.message}")
      new_resource.updated_by_last_action(false)
    end
  end
end

action :create_tenant do
  begin
    tenant_uuid = identity_uuid new_resource, "tenant", "name", new_resource.tenant_name

    unless tenant_uuid
      identity_command new_resource, "tenant-create",
        { 'name' => new_resource.tenant_name,
          'description' => new_resource.tenant_description,
          'enabled' => new_resource.tenant_enabled }
      Chef::Log.info("Created tenant '#{new_resource.tenant_name}'")
      new_resource.updated_by_last_action(true)
    else
      Chef::Log.info("Tenant '#{new_resource.tenant_name}' already exists.. Not creating.")
      Chef::Log.info("Tenant UUID: #{tenant_uuid}") if tenant_uuid
      new_resource.updated_by_last_action(false)
    end
  rescue Exception => e
    Chef::Log.error("Unable to create tenant '#{new_resource.tenant_name}'")
    Chef::Log.error("Error was: #{e.message}")
    new_resource.updated_by_last_action(false)
  end
end

action :create_role do
  begin
    role_uuid = identity_uuid new_resource, "role", "name", new_resource.role_name

    unless role_uuid
      identity_command new_resource, "role-create",
        { 'name' => new_resource.role_name }
      Chef::Log.info("Created Role '#{new_resource.role_name}'")
      new_resource.updated_by_last_action(true)
    else
      Chef::Log.info("Role '#{new_resource.role_name}' already exists.. Not creating.")
      Chef::Log.info("Role UUID: #{role_uuid}")
      new_resource.updated_by_last_action(false)
    end
  rescue Exception => e
    Chef::Log.error("Unable to create role '#{new_resource.role_name}'")
    Chef::Log.error("Error was: #{e.message}")
    new_resource.updated_by_last_action(false)
  end
end

action :create_user do
  begin
    tenant_uuid = identity_uuid new_resource, "tenant", "name", new_resource.tenant_name
    unless tenant_uuid
      Chef::Log.error("Unable to find tenant '#{new_resource.tenant_name}'")
      new_resource.updated_by_last_action(false)
      next
    end

    output = identity_command new_resource, "user-list", {'tenant-id' => tenant_uuid}
    users = prettytable_to_array output
    user_found = false
    users.each { |user|
      if user['name'] == new_resource.user_name
        user_found = true
      end
    }

    if user_found
      Chef::Log.info("User '#{new_resource.user_name}' already exists for tenant '#{new_resource.tenant_name}'")
      new_resource.updated_by_last_action(false)
      next
    end

    identity_command new_resource, "user-create",
      { 'name' => new_resource.user_name,
        'tenant-id' => tenant_uuid,
        'pass' => new_resource.user_pass,
        'enabled' => new_resource.user_enabled }
    Chef::Log.info("Created user '#{new_resource.user_name}' for tenant '#{new_resource.tenant_name}'")
    new_resource.updated_by_last_action(true)
  rescue Exception => e
    Chef::Log.error("Unable to create user '#{new_resource.user_name}' for tenant '#{new_resource.tenant_name}'")
    Chef::Log.error("Error was: #{e.message}")
    new_resource.updated_by_last_action(false)
  end
end

action :grant_role do
  begin
    tenant_uuid = identity_uuid new_resource, "tenant", "name", new_resource.tenant_name
    unless tenant_uuid
      Chef::Log.error("Unable to find tenant '#{new_resource.tenant_name}'")
      new_resource.updated_by_last_action(false)
      next
    end

    user_uuid = identity_uuid new_resource, "user", "name", new_resource.user_name
    unless tenant_uuid
      Chef::Log.error("Unable to find user '#{new_resource.user_name}'")
      new_resource.updated_by_last_action(false)
      next
    end

    role_uuid = identity_uuid new_resource, "role", "name", new_resource.role_name
    unless tenant_uuid
      Chef::Log.error("Unable to find role '#{new_resource.role_name}'")
      new_resource.updated_by_last_action(false)
      next
    end

    assigned_role_uuid = identity_uuid new_resource, "user-role", "name", new_resource.role_name,
      { 'tenant-id' => tenant_uuid,
        'user-id' => user_uuid }
    unless role_uuid == assigned_role_uuid
      identity_command new_resource, "user-role-add",
        { 'tenant-id' => tenant_uuid,
          'role-id' => role_uuid,
          'user-id' => user_uuid }
      Chef::Log.info("Granted Role '#{new_resource.role_name}' to User '#{new_resource.user_name}' in Tenant '#{new_resource.tenant_name}'")
      new_resource.updated_by_last_action(true)
    else
      Chef::Log.info("Role '#{new_resource.role_name}' already granted to User '#{new_resource.user_name}' in Tenant '#{new_resource.tenant_name}'")
      new_resource.updated_by_last_action(false)
    end
  rescue Exception => e
    Chef::Log.error("Unable to grant role '#{new_resource.role_name}' to user '#{new_resource.user_name}'")
    Chef::Log.error("Error was: #{e.message}")
    new_resource.updated_by_last_action(false)
  end
end

action :create_ec2_credentials do
  begin
    tenant_uuid = identity_uuid new_resource, "tenant", "name", new_resource.tenant_name
    unless tenant_uuid
      Chef::Log.error("Unable to find tenant '#{new_resource.tenant_name}'")
      new_resource.updated_by_last_action(false)
      next
    end

    user_uuid = identity_uuid new_resource, "user", "name", new_resource.user_name, {'tenant-id' => tenant_uuid}
    unless tenant_uuid
      Chef::Log.error("Unable to find user '#{new_resource.user_name}'")
      new_resource.updated_by_last_action(false)
      next
    end

    # this is not really a uuid, but this will work nonetheless
    access = identity_uuid new_resource, "ec2-credentials", "tenant", new_resource.tenant_name, {'user-id' => user_uuid}, "access"
    unless access
     output = identity_command new_resource, "ec2-credentials-create",
        { 'user-id' => user_uuid,
          'tenant-id' => tenant_uuid }
      Chef::Log.info("Created EC2 Credentials for User '#{new_resource.user_name}' in Tenant '#{new_resource.tenant_name}'")
      data = prettytable_to_array(output)

      if data.length != 1
        Chef::Log.error("Got bad data when creating ec2 credentials for #{new_resource.user_name}")
        Chef::Log.error("Data: #{data}")
      else
        # Update node attributes
        node.set['credentials']['EC2'][new_resource.user_name]['access'] = data[0]['access']
        node.set['credentials']['EC2'][new_resource.user_name]['secret'] = data[0]['secret']
        node.save unless Chef::Config[:solo]
        new_resource.updated_by_last_action(true)
      end
    else
      Chef::Log.info("EC2 credentials already exist for '#{new_resource.user_name}' in tenant '#{new_resource.tenant_name}'")
      new_resource.updated_by_last_action(false)
    end
  rescue Exception => e
    Chef::Log.error("Unable to create EC2 Credentials for User '#{new_resource.user_name}' in Tenant '#{new_resource.tenant_name}'")
    Chef::Log.error("Error was: #{e.message}")
    new_resource.updated_by_last_action(false)
  end
end



