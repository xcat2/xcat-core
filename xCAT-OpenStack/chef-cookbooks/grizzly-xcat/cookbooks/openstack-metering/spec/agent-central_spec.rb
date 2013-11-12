require_relative "spec_helper"

describe "openstack-metering::agent-central" do
  before { metering_stubs }
  describe "ubuntu" do
    before do
      @chef_run = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS
      @chef_run.converge "openstack-metering::agent-central"
    end

    expect_runs_common_recipe

    it "installs the agent-central package" do
      expect(@chef_run).to install_package "ceilometer-agent-central"
    end

    it "starts agent-central service" do
      expect(@chef_run).to start_service("ceilometer-agent-central")
    end
  end
end
