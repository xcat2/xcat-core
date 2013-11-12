require_relative 'spec_helper'

describe 'openstack-network::dhcp_agent' do

  describe "opensuse" do

    before do
      quantum_stubs
      @chef_run = ::ChefSpec::ChefRunner.new ::OPENSUSE_OPTS
      @chef_run.converge "openstack-network::dhcp_agent"
    end

    it "installs quamtum dhcp package" do
      expect(@chef_run).to install_package "openstack-quantum-dhcp-agent"
    end

    it "installs plugin packages" do
      expect(@chef_run).not_to install_package(/openvswitch/)
      expect(@chef_run).not_to install_package(/plugin/)
    end

    it "starts the dhcp agent on boot" do
      expect(@chef_run).to(
        set_service_to_start_on_boot "openstack-quantum-dhcp-agent")
    end

    it "/etc/quantum/dhcp_agent.ini has the proper owner" do
      expect(@chef_run.template "/etc/quantum/dhcp_agent.ini").to(
        be_owned_by "openstack-quantum", "openstack-quantum")
    end

    it "/etc/quantum/dnsmasq.conf has the proper owner" do
      expect(@chef_run.template "/etc/quantum/dnsmasq.conf").to(
        be_owned_by "openstack-quantum", "openstack-quantum")
    end
  end
end
