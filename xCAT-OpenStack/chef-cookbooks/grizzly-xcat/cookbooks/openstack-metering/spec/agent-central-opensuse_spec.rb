require_relative "spec_helper"

describe "openstack-metering::agent-central" do
  before { metering_stubs }
  describe "opensuse" do
    before do
      @chef_run = ::ChefSpec::ChefRunner.new ::OPENSUSE_OPTS
      @chef_run.converge "openstack-metering::agent-central"
    end

    it "installs the agent-central package" do
      expect(@chef_run).to install_package "openstack-ceilometer-agent-central"
    end

    it "starts the agent-central service" do
      expect(@chef_run).to start_service "openstack-ceilometer-agent-central"
    end
  end
end
