require_relative "spec_helper"

describe 'openstack-network::server' do
  describe "opensuse" do
    before do
      quantum_stubs
      @chef_run = ::ChefSpec::ChefRunner.new ::OPENSUSE_OPTS do |n|
        n.set["chef_client"]["splay"] = 300
      end
      @node = @chef_run.node
      @chef_run.converge "openstack-network::openvswitch"
    end

    it "installs the openvswitch package" do
      expect(@chef_run).to install_package "openvswitch-switch"
    end

    it "installs the openvswitch-agent package" do
      expect(@chef_run).to install_package "openstack-quantum-openvswitch-agent"
    end

    it "starts the openvswitch-switch service" do
      expect(@chef_run).to set_service_to_start_on_boot "openvswitch-switch"
    end
  end
end
