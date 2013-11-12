require_relative "spec_helper"

describe Chef::Provider::Execute do
  before do
    @chef_run = ::ChefSpec::ChefRunner.new ::OPENSUSE_OPTS
    @chef_run.converge "openstack-identity::default"
    @node = @chef_run.node
    @node.set["openstack"] = {
      "identity" => {
        "catalog" => {
          "backend" => "sql"
        }
      }
    }
    @cookbook_collection = Chef::CookbookCollection.new([])
    @events = Chef::EventDispatch::Dispatcher.new
    @run_context = Chef::RunContext.new(@node, @cookbook_collection, @events)

    @tenant_resource = Chef::Resource::OpenstackIdentityRegister.new("tenant1", @run_context)
    @tenant_resource.tenant_name "tenant1"
    @tenant_resource.tenant_description "tenant1 Tenant"

    @service_resource = Chef::Resource::OpenstackIdentityRegister.new("service1", @run_context)
    @service_resource.service_type "compute"
    @service_resource.service_name "service1"
    @service_resource.service_description "service1 Service"

    @endpoint_resource = Chef::Resource::OpenstackIdentityRegister.new("endpoint1", @run_context)
    @endpoint_resource.endpoint_region "Region One"
    @endpoint_resource.service_type "compute"
    @endpoint_resource.endpoint_publicurl "http://public"
    @endpoint_resource.endpoint_internalurl "http://internal"
    @endpoint_resource.endpoint_adminurl "http://admin"

    @role_resource = Chef::Resource::OpenstackIdentityRegister.new("role1", @run_context)
    @role_resource.role_name "role1"

    @user_resource = Chef::Resource::OpenstackIdentityRegister.new("user1", @run_context)
    @user_resource.user_name "user1"
    @user_resource.tenant_name "tenant1"
    @user_resource.user_pass "password"

    @grant_resource = Chef::Resource::OpenstackIdentityRegister.new("grant1", @run_context)
    @grant_resource.user_name "user1"
    @grant_resource.tenant_name "tenant1"
    @grant_resource.role_name "role1"

    @ec2_resource = Chef::Resource::OpenstackIdentityRegister.new("ec2", @run_context)
    @ec2_resource.user_name "user1"
    @ec2_resource.tenant_name "tenant1"
  end

  it "should create a tenant" do
    provider = Chef::Provider::OpenstackIdentityRegister.new(@tenant_resource, @run_context)
    provider.stub!(:identity_uuid).with(@tenant_resource, "tenant", "name", "tenant1")
    provider.stub!(:identity_command).with(@tenant_resource, "tenant-create",
      {"name" => "tenant1", "description" => "tenant1 Tenant", "enabled" => true})
    provider.run_action(:create_tenant)
    @tenant_resource.should be_updated
  end
  it "should not create a new tenant if already exists" do
    provider = Chef::Provider::OpenstackIdentityRegister.new(@tenant_resource, @run_context)
    provider.stub!(:identity_uuid).with(@tenant_resource, "tenant", "name", "tenant1").and_return("1234567890ABCDEFGH")
    provider.run_action(:create_tenant)
    @tenant_resource.should_not be_updated
  end
  it "should create a service" do
    provider = Chef::Provider::OpenstackIdentityRegister.new(@service_resource, @run_context)
    provider.stub!(:identity_uuid).with(@service_resource, "service", "type", "compute")
    provider.stub!(:identity_command).with(@service_resource, "service-create",
      {"type" => "compute", "name" => "service1", "description" => "service1 Service"})
    provider.run_action(:create_service)
    @service_resource.should be_updated
  end
  it "should not create a service if already exists" do
    provider = Chef::Provider::OpenstackIdentityRegister.new(@service_resource, @run_context)
    provider.stub!(:identity_uuid).with(@service_resource, "service", "type", "compute").and_return("1234567890ABCDEFGH")
    provider.run_action(:create_service)
    @service_resource.should_not be_updated
  end
  it "should not create a service if using a templated backend" do
    node = Chef::Node.new
    node.set["openstack"] = {"identity" => {"catalog" => { "backend" => "templated" }} }
    cookbook_collection = Chef::CookbookCollection.new([])
    events = Chef::EventDispatch::Dispatcher.new
    run_context = Chef::RunContext.new(node, cookbook_collection, events)
    provider = Chef::Provider::OpenstackIdentityRegister.new(@service_resource, run_context)
    provider.run_action(:create_service)
    @service_resource.should_not be_updated
  end
  it "should create an endpoint" do
    provider = Chef::Provider::OpenstackIdentityRegister.new(@endpoint_resource, @run_context)
    provider.stub!(:identity_uuid).with(@endpoint_resource, "service", "type", "compute").and_return("1234567890ABCDEFGH")
    provider.stub!(:identity_uuid).with(@endpoint_resource, "endpoint", "service_id", "1234567890ABCDEFGH")
    provider.stub!(:identity_command).with(@endpoint_resource, "endpoint-create", {
      "region" => "Region One", "service_id" => "1234567890ABCDEFGH", "publicurl" => "http://public",
      "internalurl" => "http://internal", "adminurl" => "http://admin"})
    provider.run_action(:create_endpoint)
    @endpoint_resource.should be_updated
  end
  it "should not create a endpoint if already exists" do
    provider = Chef::Provider::OpenstackIdentityRegister.new(@endpoint_resource, @run_context)
    provider.stub!(:identity_uuid).with(@endpoint_resource, "service", "type", "compute").and_return("1234567890ABCDEFGH")
    provider.stub!(:identity_uuid).with(@endpoint_resource, "endpoint", "service_id", "1234567890ABCDEFGH").and_return("0987654321HGFEDCBA")
    provider.run_action(:create_endpoint)
    @endpoint_resource.should_not be_updated
  end
  it "should not create an endpoint if using a templated backend" do
    node = Chef::Node.new
    node.set["openstack"] = {"identity" => {"catalog" => { "backend" => "templated" }} }
    cookbook_collection = Chef::CookbookCollection.new([])
    events = Chef::EventDispatch::Dispatcher.new
    run_context = Chef::RunContext.new(node, cookbook_collection, events)
    provider = Chef::Provider::OpenstackIdentityRegister.new(@endpoint_resource, run_context)
    provider.run_action(:create_endpoint)
    @endpoint_resource.should_not be_updated
  end
  it "should create a role" do
    provider = Chef::Provider::OpenstackIdentityRegister.new(@role_resource, @run_context)
    provider.stub!(:identity_uuid).with(@role_resource, "role", "name", "role1")
    provider.stub!(:identity_command).with(@role_resource, "role-create", {"name" => "role1"})
    provider.run_action(:create_role)
    @role_resource.should be_updated
  end
  it "should not create a role if already exists" do
    provider = Chef::Provider::OpenstackIdentityRegister.new(@role_resource, @run_context)
    provider.stub!(:identity_uuid).with(@role_resource, "role", "name", "role1").and_return("1234567890ABCDEFGH")
    provider.run_action(:create_role)
    @role_resource.should_not be_updated
  end
  it "should create a user" do
    provider = Chef::Provider::OpenstackIdentityRegister.new(@user_resource, @run_context)
    provider.stub!(:identity_uuid).with(@user_resource, "tenant", "name", "tenant1").and_return("1234567890ABCDEFGH")
    provider.stub!(:identity_command).with(@user_resource, "user-list", {"tenant-id" => "1234567890ABCDEFGH"})
    provider.stub!(:identity_command).with(@user_resource, "user-create",
      {"name" => "user1", "tenant-id" => "1234567890ABCDEFGH", "pass" => "password", "enabled" => true})
    provider.stub!(:prettytable_to_array).and_return([])
    provider.run_action(:create_user)
    @user_resource.should be_updated
  end
  it "should not create a user if already exists" do
    provider = Chef::Provider::OpenstackIdentityRegister.new(@user_resource, @run_context)
    provider.stub!(:identity_uuid).with(@user_resource, "tenant", "name", "tenant1").and_return("1234567890ABCDEFGH")
    provider.stub!(:identity_command).with(@user_resource, "user-list", {"tenant-id" => "1234567890ABCDEFGH"})
    provider.stub!(:prettytable_to_array).and_return([{"name" => "user1"}])
    provider.stub!(:identity_uuid).with(@user_resource, "user", "name", "user1").and_return("HGFEDCBA0987654321")
    provider.run_action(:create_user)
    @user_resource.should_not be_updated
  end
  it "should grant a role" do
    provider = Chef::Provider::OpenstackIdentityRegister.new(@grant_resource, @run_context)
    provider.stub!(:identity_uuid).with(@grant_resource, "tenant", "name", "tenant1").and_return("1234567890ABCDEFGH")
    provider.stub!(:identity_uuid).with(@grant_resource, "user", "name", "user1").and_return("HGFEDCBA0987654321")
    provider.stub!(:identity_uuid).with(@grant_resource, "role", "name", "role1").and_return("ABC1234567890DEF")
    provider.stub!(:identity_uuid).with(@grant_resource, "user-role", "name", "role1",
      { "tenant-id" => "1234567890ABCDEFGH", "user-id" => "HGFEDCBA0987654321" }).and_return("ABCD1234567890EFGH")
    provider.stub!(:identity_command).with(@grant_resource, "user-role-add",
      {"tenant-id" => "1234567890ABCDEFGH", "role-id" => "ABC1234567890DEF", "user-id" => "HGFEDCBA0987654321"})
    provider.run_action(:grant_role)
    @grant_resource.should be_updated
  end
  it "should not grant a role if already granted" do
    provider = Chef::Provider::OpenstackIdentityRegister.new(@grant_resource, @run_context)
    provider.stub!(:identity_uuid).with(@grant_resource, "tenant", "name", "tenant1").and_return("1234567890ABCDEFGH")
    provider.stub!(:identity_uuid).with(@grant_resource, "user", "name", "user1").and_return("HGFEDCBA0987654321")
    provider.stub!(:identity_uuid).with(@grant_resource, "role", "name", "role1").and_return("ABC1234567890DEF")
    provider.stub!(:identity_uuid).with(@grant_resource, "user-role", "name", "role1",
      {"tenant-id" => "1234567890ABCDEFGH", "user-id" => "HGFEDCBA0987654321" }).and_return("ABC1234567890DEF")
    provider.stub!(:identity_command).with(@grant_resource, "user-role-add",
      {"tenant-id" => "1234567890ABCDEFGH", "role-id" => "ABC1234567890DEF", "user-id" => "HGFEDCBA0987654321"})
    provider.run_action(:grant_role)
    @grant_resource.should_not be_updated
  end
  it "should grant ec2 creds" do
    provider = Chef::Provider::OpenstackIdentityRegister.new(@ec2_resource, @run_context)
    provider.stub!(:identity_uuid).with(@ec2_resource, "tenant", "name", "tenant1").and_return("1234567890ABCDEFGH")
    provider.stub!(:identity_uuid).with(@ec2_resource, "user", "name", "user1",
      {"tenant-id" => "1234567890ABCDEFGH"}).and_return("HGFEDCBA0987654321")
    provider.stub!(:identity_uuid).with(@ec2_resource, "ec2-credentials", "tenant", "tenant1",
      {"user-id" => "HGFEDCBA0987654321"}, "access")
    provider.stub!(:identity_command).with(@ec2_resource, "ec2-credentials-create",
      {"user-id" => "HGFEDCBA0987654321", "tenant-id" => "1234567890ABCDEFGH"})
    provider.stub!(:prettytable_to_array).and_return([{"access" => "access", "secret" => "secret"}])
    provider.run_action(:create_ec2_credentials)
    @ec2_resource.should be_updated
  end
  it "should grant ec2 creds if they already exist" do
    provider = Chef::Provider::OpenstackIdentityRegister.new(@ec2_resource, @run_context)
    provider.stub!(:identity_uuid).with(@ec2_resource, "tenant", "name", "tenant1").and_return("1234567890ABCDEFGH")
    provider.stub!(:identity_uuid).with(@ec2_resource, "user", "name", "user1",
      {"tenant-id" => "1234567890ABCDEFGH"}).and_return("HGFEDCBA0987654321")
    provider.stub!(:identity_uuid).with(@ec2_resource, "ec2-credentials", "tenant", "tenant1",
      {"user-id" => "HGFEDCBA0987654321"}, "access").and_return("ABC1234567890DEF")
    provider.run_action(:create_ec2_credentials)
    @ec2_resource.should_not be_updated
  end

  describe "#identity_command" do
    it "should handle false values and long descriptions" do
      provider = Chef::Provider::OpenstackIdentityRegister.new(
        @user_resource, @run_context)

      provider.stub!(:shell_out).with(
        ["keystone", "user-create", "--enabled", "false",
          "--description", "more than one word"],
        {:env => {"OS_SERVICE_ENDPOINT" => nil, "OS_SERVICE_TOKEN" => nil}}
        ).and_return double("shell_out", :exitstatus => 0, :stdout => "good")

      provider.send(
        :identity_command, @user_resource, "user-create",
        {"enabled" => false, "description" => "more than one word"}
        ).should eq "good"
    end
  end
end
