require_relative "spec_helper"

describe "openstack-metering::collector" do
  before { metering_stubs }
  describe "opensuse" do
    before do
      @chef_run = ::ChefSpec::ChefRunner.new ::OPENSUSE_OPTS
      @chef_run.converge "openstack-metering::collector"
    end

    it "installs the collector package" do
      expect(@chef_run).to install_package "openstack-ceilometer-collector"
    end

    it "starts the collector service" do
      expect(@chef_run).to start_service "openstack-ceilometer-collector"
    end
  end
end
