require_relative 'spec_helper'

describe 'openstack-network::l3_agent' do

  describe "ubuntu" do

    before do
      quantum_stubs
      @chef_run = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS
      @chef_run.converge "openstack-network::l3_agent"
    end

    it "installs quamtum l3 package" do
      expect(@chef_run).to install_package "quantum-l3-agent"
    end

    describe "l3_agent.ini" do

      before do
        @file = @chef_run.template "/etc/quantum/l3_agent.ini"
      end

      it "has proper owner" do
        expect(@file).to be_owned_by "quantum", "quantum"
      end

      it "has proper modes" do
        expect(sprintf("%o", @file.mode)).to eq "644"
      end

      it "it has ovs driver" do
        expect(@chef_run).to create_file_with_content @file.name,
          "interface_driver = quantum.agent.linux.interface.OVSInterfaceDriver"
      end

      it "sets fuzzy delay to default" do
        expect(@chef_run).to create_file_with_content @file.name,
          "periodic_fuzzy_delay = 5"
      end

      it "it does not set a nil router_id" do
        expect(@chef_run).not_to create_file_with_content @file.name,
          /^router_id =/
      end

      it "it does not set a nil router_id" do
        expect(@chef_run).not_to create_file_with_content @file.name,
          /^gateway_external_network_id =/
      end
    end

    describe "create ovs bridges" do
      before do
        quantum_stubs
        opts = ::UBUNTU_OPTS.merge(:evaluate_guards => true)
        @chef_run = ::ChefSpec::ChefRunner.new opts
      end

      cmd = "ovs-vsctl add-br br-ex && ovs-vsctl add-port br-ex eth1"

      it "doesn't add the external bridge if it already exists" do
        @chef_run.stub_command(/ovs-vsctl show/, true)
        @chef_run.stub_command(/ip link show eth1/, true)
        @chef_run.converge "openstack-network::l3_agent"
        expect(@chef_run).not_to execute_command(cmd)
      end

      it "doesn't add the external bridge if the physical interface doesn't exist" do
        @chef_run.stub_command(/ovs-vsctl show/, true)
        @chef_run.stub_command(/ip link show eth1/, false)
        @chef_run.converge "openstack-network::l3_agent"
        expect(@chef_run).not_to execute_command(cmd)
      end

      it "adds the external bridge if it does not yet exist" do
        @chef_run.stub_command(/ovs-vsctl show/, false)
        @chef_run.stub_command(/ip link show eth1/, true)
        @chef_run.converge "openstack-network::l3_agent"
        expect(@chef_run).to execute_command(cmd)
      end

      it "adds the external bridge if the physical interface exists" do
        @chef_run.stub_command(/ovs-vsctl show/, false)
        @chef_run.stub_command(/ip link show eth1/, true)
        @chef_run.converge "openstack-network::l3_agent"
        expect(@chef_run).to execute_command(cmd)
      end
    end
  end
end
