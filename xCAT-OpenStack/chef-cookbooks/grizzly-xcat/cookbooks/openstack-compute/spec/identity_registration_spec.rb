require_relative "spec_helper"

describe "openstack-compute::identity_registration" do
  before do
    compute_stubs
    @chef_run = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS
    @chef_run.converge "openstack-compute::identity_registration"
  end

  it "registers service tenant" do
    resource = @chef_run.find_resource(
      "openstack-identity_register",
      "Register Service Tenant"
    ).to_hash

    expect(resource).to include(
      :auth_uri => "http://127.0.0.1:35357/v2.0",
      :bootstrap_token => "bootstrap-token",
      :tenant_name => "service",
      :tenant_description => "Service Tenant",
      :action => [:create_tenant]
    )
  end

  it "registers service user" do
    resource = @chef_run.find_resource(
      "openstack-identity_register",
      "Register Service User"
    ).to_hash

    expect(resource).to include(
      :auth_uri => "http://127.0.0.1:35357/v2.0",
      :bootstrap_token => "bootstrap-token",
      :tenant_name => "service",
      :user_name => "nova",
      :user_pass => "nova-pass",
      :action => [:create_user]
    )
  end

  it "grants admin role to service user for service tenant" do
    resource = @chef_run.find_resource(
      "openstack-identity_register",
      "Grant 'admin' Role to Service User for Service Tenant"
    ).to_hash

    expect(resource).to include(
      :auth_uri => "http://127.0.0.1:35357/v2.0",
      :bootstrap_token => "bootstrap-token",
      :tenant_name => "service",
      :user_name => "nova",
      :role_name => "admin",
      :action => [:grant_role]
    )
  end

  it "registers compute service" do
    resource = @chef_run.find_resource(
      "openstack-identity_register",
      "Register Compute Service"
    ).to_hash

    expect(resource).to include(
      :auth_uri => "http://127.0.0.1:35357/v2.0",
      :bootstrap_token => "bootstrap-token",
      :service_name => "nova",
      :service_type => "compute",
      :service_description => "Nova Compute Service",
      :action => [:create_service]
    )
  end

  it "registers compute endpoint" do
    resource = @chef_run.find_resource(
      "openstack-identity_register",
      "Register Compute Endpoint"
    ).to_hash

    expect(resource).to include(
      :auth_uri => "http://127.0.0.1:35357/v2.0",
      :bootstrap_token => "bootstrap-token",
      :service_type => "compute",
      :endpoint_region => "RegionOne",
      :endpoint_adminurl => "http://127.0.0.1:8774/v2/%(tenant_id)s",
      :endpoint_internalurl => "http://127.0.0.1:8774/v2/%(tenant_id)s",
      :endpoint_publicurl => "http://127.0.0.1:8774/v2/%(tenant_id)s",
      :action => [:create_endpoint]
    )
  end

  it "registers ec2 service" do
    resource = @chef_run.find_resource(
      "openstack-identity_register",
      "Register EC2 Service"
    ).to_hash

    expect(resource).to include(
      :auth_uri => "http://127.0.0.1:35357/v2.0",
      :bootstrap_token => "bootstrap-token",
      :service_name => "ec2",
      :service_type => "ec2",
      :service_description => "EC2 Compatibility Layer",
      :action => [:create_service]
    )
  end

  it "registers ec2 endpoint" do
    resource = @chef_run.find_resource(
      "openstack-identity_register",
      "Register EC2 Endpoint"
    ).to_hash

    expect(resource).to include(
      :auth_uri => "http://127.0.0.1:35357/v2.0",
      :bootstrap_token => "bootstrap-token",
      :service_type => "ec2",
      :endpoint_region => "RegionOne",
      :endpoint_adminurl => "http://127.0.0.1:8773/services/Admin",
      :endpoint_internalurl => "http://127.0.0.1:8773/services/Cloud",
      :endpoint_publicurl => "http://127.0.0.1:8773/services/Cloud",
      :action => [:create_endpoint]
    )
  end
end
