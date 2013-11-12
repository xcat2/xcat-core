require_relative "spec_helper"

describe 'openstack-network::server' do
  describe "opensuse" do
    before do
      quantum_stubs
      @chef_run = ::ChefSpec::ChefRunner.new ::OPENSUSE_OPTS do |n|
        n.set["chef_client"]["splay"] = 300
      end
      @node = @chef_run.node
      @chef_run.converge "openstack-network::server"
    end

    it "installs openstack-quantum packages" do
      expect(@chef_run).to install_package "openstack-quantum"
    end

    it "enables openstack-quantum service" do
      expect(@chef_run).to enable_service "openstack-quantum"
    end

    it "does not install openvswitch package" do
      opts = ::OPENSUSE_OPTS.merge(:evaluate_guards => true)
      chef_run = ::ChefSpec::ChefRunner.new opts do |n|
        n.set["chef_client"]["splay"] = 300
      end
      chef_run.converge "openstack-network::server"

      expect(chef_run).not_to install_package "openstack-quantum-openvswitch"
    end

    describe "/etc/sysconfig/quantum" do
      before do
        @file = @chef_run.template("/etc/sysconfig/quantum")
      end

      it "has proper owner" do
        expect(@file).to be_owned_by "root", "root"
      end

      it "has proper modes" do
        expect(sprintf("%o", @file.mode)).to eq "644"
      end

      it "has the correct plugin config location - ovs by default" do
        expect(@chef_run).to create_file_with_content(
          @file.name, "/etc/quantum/plugins/openvswitch/ovs_quantum_plugin.ini")
      end

      it "uses linuxbridge when configured to use it" do
        chef_run = ::ChefSpec::ChefRunner.new ::OPENSUSE_OPTS do |n|
          n.set["openstack"]["network"]["interface_driver"] = "quantum.agent.linux.interface.BridgeInterfaceDriver"
        end
        chef_run.converge "openstack-network::server"

        expect(chef_run).to create_file_with_content(
          "/etc/sysconfig/quantum",
          "/etc/quantum/plugins/linuxbridge/linuxbridge_conf.ini"
          )
      end
    end
  end
end
