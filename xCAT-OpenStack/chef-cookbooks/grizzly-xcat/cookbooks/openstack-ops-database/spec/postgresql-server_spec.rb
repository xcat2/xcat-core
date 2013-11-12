require_relative "spec_helper"

describe "openstack-ops-database::postgresql-server" do
  before { ops_database_stubs }
  describe "ubuntu" do
    before do
      @chef_run = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS
      # The postgresql cookbook will raise an "uninitialized constant
      # Chef::Application" error without this attribute when running
      # the tests
      @chef_run.node.set["postgresql"]["password"]["postgres"] = String.new
      @chef_run.converge "openstack-ops-database::postgresql-server"
    end

    it "includes postgresql recipes" do
      expect(@chef_run).to include_recipe(
        "openstack-ops-database::postgresql-client")
      expect(@chef_run).to include_recipe "postgresql::server"
    end
  end
end
