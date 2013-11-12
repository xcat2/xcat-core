require_relative 'spec_helper'

describe 'openstack-network::openvswitch' do
  before do
    quantum_stubs
    @chef_run = ::ChefSpec::ChefRunner.new(::UBUNTU_OPTS) do |n|
      n.automatic_attrs["kernel"]["release"] = "1.2.3"
      n.set["openstack"]["network"]["local_ip_interface"] = "eth0"
    end
    @chef_run.converge "openstack-network::openvswitch"
  end

  it "installs openvswitch switch" do
    expect(@chef_run).to install_package "openvswitch-switch"
  end

  it "installs openvswitch datapath dkms" do
    expect(@chef_run).to install_package "openvswitch-datapath-dkms"
  end

  it "installs linux bridge utils" do
    expect(@chef_run).to install_package "bridge-utils"
  end

  it "installs linux linux headers" do
    expect(@chef_run).to install_package "linux-headers-1.2.3"
  end

  it "sets the openvswitch service to start on boot" do
    expect(@chef_run).to set_service_to_start_on_boot 'openvswitch-switch'
  end

  it "installs openvswitch agent" do
    expect(@chef_run).to install_package "quantum-plugin-openvswitch-agent"
  end

  it "sets the openvswitch service to start on boot" do
    expect(@chef_run).to set_service_to_start_on_boot "quantum-plugin-openvswitch-agent"
  end

  describe "ovs-dpctl-top" do
    before do
      @file = @chef_run.cookbook_file "ovs-dpctl-top"
    end

    it "creates the ovs-dpctl-top file" do
      expect(@chef_run).to create_file "/usr/bin/ovs-dpctl-top"
    end

    it "has the proper owner" do
      expect(@file).to be_owned_by "root", "root"
    end

    it "has the proper mode" do
      expect(sprintf("%o", @file.mode)).to eq "755"
    end

    it "has the proper interpreter line" do
      expect(@chef_run).to create_file_with_content @file.name,
        /^#!\/usr\/bin\/env python/
    end
  end

  describe "ovs_quantum_plugin.ini" do
    before do
      @file = @chef_run.template "/etc/quantum/plugins/openvswitch/ovs_quantum_plugin.ini"
    end

    it "has proper owner" do
      expect(@file).to be_owned_by "quantum", "quantum"
    end

    it "has proper modes" do
      expect(sprintf("%o", @file.mode)).to eq "644"
    end

    it "uses default network_vlan_range" do
      expect(@chef_run).not_to create_file_with_content @file.name,
        /^network_vlan_ranges =/
    end

    it "uses default tunnel_id_ranges" do
      expect(@chef_run).not_to create_file_with_content @file.name,
        /^tunnel_id_ranges =/
    end

    it "uses default integration_bridge" do
      expect(@chef_run).to create_file_with_content @file.name,
        "integration_bridge = br-int"
    end

    it "uses default tunnel bridge" do
      expect(@chef_run).to create_file_with_content @file.name,
        "tunnel_bridge = br-tun"
    end

    it "uses default int_peer_patch_port" do
      expect(@chef_run).not_to create_file_with_content @file.name,
        /^int_peer_patch_port =/
    end

    it "uses default tun_peer_patch_port" do
      expect(@chef_run).not_to create_file_with_content @file.name,
        /^tun_peer_patch_port =/
    end

    it "it has firewall driver" do
      expect(@chef_run).to create_file_with_content @file.name,
        "firewall_driver = quantum.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver"
    end

    it "it uses local_ip from eth0 when local_ip_interface is set" do
      expect(@chef_run).to create_file_with_content @file.name,
        "local_ip = 10.0.0.3"
    end
  end
end
