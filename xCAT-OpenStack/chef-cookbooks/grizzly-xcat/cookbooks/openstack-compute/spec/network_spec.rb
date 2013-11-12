require_relative "spec_helper"

describe "openstack-compute::network" do
  before { compute_stubs }
  describe "ubuntu" do
    before do
      @chef_run = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS
      @node = @chef_run.node
      @node.set["openstack"]["compute"]["network"]["service_type"] = "nova"
      @chef_run.converge "openstack-compute::network"
    end

    expect_runs_nova_common_recipe

    it "installs nova network packages" do
      expect(@chef_run).to upgrade_package "iptables"
      expect(@chef_run).to upgrade_package "nova-network"
    end

    it "starts nova network on boot" do
      expect(@chef_run).to set_service_to_start_on_boot "nova-network"
    end

    it "includes openstack-network recipes for quantum when service type is quantum" do
      @chef_run = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS
      @node = @chef_run.node
      @node.set["openstack"]["compute"]["network"]["service_type"] = "quantum"
      @chef_run.converge "openstack-compute::network"
      expect(@chef_run).to include_recipe "openstack-network::openvswitch"
      expect(@chef_run).to include_recipe "openstack-network::dhcp_agent"
    end

  end
end
