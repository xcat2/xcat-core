require_relative "spec_helper"

describe "openstack-ops-database::mysql-client" do
  before { ops_database_stubs }
  describe "ubuntu" do
    before do
      @chef_run = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS
      @chef_run.converge "openstack-ops-database::mysql-client"
    end

    it "includes mysql recipes" do
      expect(@chef_run).to include_recipe "mysql::ruby"
      expect(@chef_run).to include_recipe "mysql::client"
    end

    it "installs mysql packages" do
      expect(@chef_run).to install_package "python-mysqldb"
    end
  end
end
