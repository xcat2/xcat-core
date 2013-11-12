require_relative "spec_helper"

describe "openstack-metering::collector" do
  before { metering_stubs }
  describe "ubuntu" do
    before do
      @chef_run = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS
      @chef_run.converge "openstack-metering::collector"
    end

    expect_runs_common_recipe

    it "executes ceilometer dbsync" do
      command = "ceilometer-dbsync --config-file /etc/ceilometer/ceilometer.conf"
      expect(@chef_run).to execute_command command
    end

    it "installs python-mysqldb", :A => true do
      expect(@chef_run).to install_package "python-mysqldb"
    end

    it "starts collector service" do
      expect(@chef_run).to start_service("ceilometer-collector")
    end
  end
end
