require_relative "spec_helper"

describe "openstack-compute::vncproxy" do
  before { compute_stubs }
  describe "ubuntu" do
    before do
      @chef_run = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS
      @chef_run.converge "openstack-compute::vncproxy"
    end

    expect_runs_nova_common_recipe

    it "installs vncproxy packages" do
      expect(@chef_run).to upgrade_package "novnc"
      expect(@chef_run).to upgrade_package "websockify"
      expect(@chef_run).to upgrade_package "nova-novncproxy"
    end

    it "installs consoleauth packages" do
      expect(@chef_run).to upgrade_package "nova-consoleauth"
    end

    it "starts nova vncproxy on boot" do
      expect(@chef_run).to set_service_to_start_on_boot "nova-novncproxy"
    end

    it "starts nova consoleauth" do
      expect(@chef_run).to start_service "nova-consoleauth"
    end

    it "starts nova consoleauth on boot" do
      expect(@chef_run).to set_service_to_start_on_boot "nova-consoleauth"
    end
  end
end
