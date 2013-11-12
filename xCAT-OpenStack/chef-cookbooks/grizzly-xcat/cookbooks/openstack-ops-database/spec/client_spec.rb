require_relative "spec_helper"

describe "openstack-ops-database::client" do
  before { ops_database_stubs }
  describe "ubuntu" do

    it "uses mysql database client recipe by default" do
      chef_run = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS
      chef_run.converge "openstack-ops-database::client"

      expect(chef_run).to include_recipe "openstack-ops-database::mysql-client"
    end

    it "uses postgresql database client recipe when configured" do
      chef_run = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS
      node = chef_run.node
      node.set["openstack"]["db"]["service_type"] = "postgresql"

      chef_run.converge "openstack-ops-database::client"

      expect(chef_run).to include_recipe "openstack-ops-database::postgresql-client"
    end
  end
end
