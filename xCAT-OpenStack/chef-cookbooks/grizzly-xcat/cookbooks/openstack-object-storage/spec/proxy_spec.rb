require 'spec_helper'

describe 'openstack-object-storage::proxy-server' do

  #--------------
  # UBUNTU
  #--------------

  describe "ubuntu" do

    before do
      swift_stubs
      @chef_run = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS
      @node = @chef_run.node
      @node.set['lsb']['code'] = 'precise'
      @node.set['swift']['authmode'] = 'swauth'
      @node.set['swift']['network']['proxy-bind-ip'] = '10.0.0.1'
      @node.set['swift']['network']['proxy-bind-port'] = '8080'
      @chef_run.converge "openstack-object-storage::proxy-server"
    end

    it "installs memcache python packages" do
      expect(@chef_run).to install_package "python-memcache"
    end

    it "installs swift packages" do
      expect(@chef_run).to install_package "swift-proxy"
    end

    it "installs swauth package if swauth is selected" do
      expect(@chef_run).to install_package "python-swauth"
    end

    it "starts swift-proxy on boot" do
     expect(@chef_run).to set_service_to_start_on_boot "swift-proxy"
    end

    describe "/etc/swift/proxy-server.conf" do

      before do
        @file = @chef_run.template "/etc/swift/proxy-server.conf"
      end

      it "has proper owner" do
        expect(@file).to be_owned_by "swift", "swift"
      end

      it "has proper modes" do
        expect(sprintf("%o", @file.mode)).to eq "600"
      end

      it "template contents" do
        pending "TODO: implement"
      end

    end

  end

end
