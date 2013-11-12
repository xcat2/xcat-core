require_relative "spec_helper"

describe "openstack-image::identity_registration" do
  before do
    image_stubs
    @chef_run = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS
    @chef_run.converge "openstack-image::identity_registration"
  end

  it "registers image service" do
    resource = @chef_run.find_resource(
      "openstack-identity_register",
      "Register Image Service"
    ).to_hash

    expect(resource).to include(
      :auth_uri => "http://127.0.0.1:35357/v2.0",
      :bootstrap_token => "bootstrap-token",
      :service_type => "image",
      :service_description => "Glance Image Service",
      :action => [:create_service]
    )
  end

  it "registers image endpoint" do
    resource = @chef_run.find_resource(
      "openstack-identity_register",
      "Register Image Endpoint"
    ).to_hash

    expect(resource).to include(
      :auth_uri => "http://127.0.0.1:35357/v2.0",
      :bootstrap_token => "bootstrap-token",
      :service_type => "image",
      :endpoint_region => "RegionOne",
      :endpoint_adminurl => "http://127.0.0.1:9292/v2",
      :endpoint_internalurl => "http://127.0.0.1:9292/v2",
      :endpoint_publicurl => "http://127.0.0.1:9292/v2",
      :action => [:create_endpoint]
    )
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
      :tenant_enabled => true,
      :action => [:create_tenant]
    )
  end

  it "registers service user" do
    resource = @chef_run.find_resource(
      "openstack-identity_register",
      "Register glance User"
    ).to_hash

    expect(resource).to include(
      :auth_uri => "http://127.0.0.1:35357/v2.0",
      :bootstrap_token => "bootstrap-token",
      :tenant_name => "service",
      :user_name => "glance",
      :user_pass => "glance-pass",
      :user_enabled => true,
      :action => [:create_user]
    )
  end

  it "grants admin role to service user for service tenant" do
    resource = @chef_run.find_resource(
      "openstack-identity_register",
      "Grant 'admin' Role to glance User for service Tenant"
    ).to_hash

    expect(resource).to include(
      :auth_uri => "http://127.0.0.1:35357/v2.0",
      :bootstrap_token => "bootstrap-token",
      :tenant_name => "service",
      :role_name => "admin",
      :user_name => "glance",
      :action => [:grant_role]
    )
  end
end
