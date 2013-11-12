require_relative "spec_helper"

describe "openstack-metering::api" do
  before { metering_stubs }
  describe "opensuse" do
    before do
      @chef_run = ::ChefSpec::ChefRunner.new ::OPENSUSE_OPTS
      @chef_run.converge "openstack-metering::api"
    end

    it "installs the api package" do
      expect(@chef_run).to install_package("openstack-ceilometer-api")
    end

    it "starts api service" do
      expect(@chef_run).to start_service("openstack-ceilometer-api")
    end
  end
end
