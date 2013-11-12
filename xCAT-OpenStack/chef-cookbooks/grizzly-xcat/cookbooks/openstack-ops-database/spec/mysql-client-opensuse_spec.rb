require_relative "spec_helper"

describe "openstack-ops-database::postgresql-client" do
  before { ops_database_stubs }
  describe "opensuse" do
    before do
      @chef_run = ::ChefSpec::ChefRunner.new ::OPENSUSE_OPTS
      @chef_run.converge "openstack-ops-database::mysql-client"
    end

    it "installs mysql packages" do
      expect(@chef_run).to install_package "python-mysql"
    end
  end
end
