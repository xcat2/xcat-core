require_relative "spec_helper"

describe "openstack-metering::agent-compute" do
  before { metering_stubs }
  describe "ubuntu" do
    before do
      @chef_run = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS
      @chef_run.converge "openstack-metering::agent-compute"
    end

    expect_runs_common_recipe

    it "installs the agent-compute package" do
      expect(@chef_run).to install_package "ceilometer-agent-compute"
    end

    it "starts ceilometer-agent-compute service" do
      expect(@chef_run).to start_service("ceilometer-agent-compute")
    end
  end
end
