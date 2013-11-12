require_relative "spec_helper"

describe "openstack-metering::common" do
  before { metering_stubs }
  describe "opensuse" do
    before do
      @chef_run = ::ChefSpec::ChefRunner.new ::OPENSUSE_OPTS
      @chef_run.converge "openstack-metering::common"
    end

    it "installs the common package" do
      expect(@chef_run).to install_package "openstack-ceilometer"
    end
  end
end
