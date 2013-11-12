require_relative 'spec_helper'

describe 'openstack-network::balancer' do

  describe "ubuntu" do

    before do
      quantum_stubs
      @chef_run = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS
      @chef_run.converge "openstack-network::balancer"
    end

    ['haproxy', 'quantum-lbaas-agent'].each do |pack|
      it "installs #{pack} package" do
        expect(@chef_run).to install_package pack
      end
    end

    it 'creates directory /etc/quantum/plugins/services/agent_loadbalancer' do
      expect(@chef_run).to create_directory '/etc/quantum/plugins/services/agent_loadbalancer'
    end

    it 'balancer config' do
      configf = "/etc/quantum/plugins/services/agent_loadbalancer/lbaas_agent.ini"
      expect(@chef_run).to create_file configf
      expect(@chef_run).to create_file_with_content configf, /periodic_interval = 10/
      expect(@chef_run).to create_file_with_content configf, /interface_driver = quantum.agent.linux.interface.OVSInterfaceDriver/
    end

  end

end
