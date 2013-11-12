require_relative 'spec_helper'

describe 'openstack-network::metadata_agent' do

  describe "ubuntu" do

    before do
      quantum_stubs
      @chef_run = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS
      @chef_run.converge "openstack-network::metadata_agent"
    end

    it "installs quamtum metadata agent" do
      expect(@chef_run).to install_package "quantum-metadata-agent"
    end

    describe "metadata_agent.ini" do

      before do
       @file = @chef_run.template "/etc/quantum/metadata_agent.ini"
      end

      it "has proper owner" do
        expect(@file).to be_owned_by "quantum", "quantum"
      end

      it "has proper modes" do
       expect(sprintf("%o", @file.mode)).to eq "644"
      end

      it "sets auth url correctly" do
        expect(@chef_run).to create_file_with_content @file.name,
          "auth_url = http://127.0.0.1:5000/v2.0"
      end
      it "sets auth region correctly" do
        expect(@chef_run).to create_file_with_content @file.name,
          "auth_region = RegionOne"
      end
      it "sets admin tenant name" do
        expect(@chef_run).to create_file_with_content @file.name,
          "admin_tenant_name = service"
      end
      it "sets admin user" do
        expect(@chef_run).to create_file_with_content @file.name,
          "admin_user = quantum"
      end
      it "sets admin password" do
        expect(@chef_run).to create_file_with_content @file.name,
          "admin_password = quantum-pass"
      end
      it "sets nova metadata ip correctly" do
        expect(@chef_run).to create_file_with_content @file.name,
          "nova_metadata_ip = 127.0.0.1"
      end
      it "sets nova metadata ip correctly" do
        expect(@chef_run).to create_file_with_content @file.name,
          "nova_metadata_port = 8775"
      end
      it "sets quantum secret correctly" do
        expect(@chef_run).to create_file_with_content @file.name,
          "metadata_proxy_shared_secret = metadata-secret"
      end
    end
  end
end
