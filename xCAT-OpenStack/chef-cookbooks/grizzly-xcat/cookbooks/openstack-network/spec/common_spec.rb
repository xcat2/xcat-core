require_relative 'spec_helper'

describe "openstack-network::common" do
  describe "ubuntu" do
    before do
      quantum_stubs
      @chef_run = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS
      @chef_run.converge "openstack-network::common"
    end

    it "upgrades python quantumclient" do
      expect(@chef_run).to upgrade_package "python-quantumclient"
    end

    it "upgrades python pyparsing" do
      expect(@chef_run).to upgrade_package "python-pyparsing"
    end
  end
end
