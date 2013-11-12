require 'spec_helper'

describe 'openstack-object-storage::container-server' do

  #-------------------
  # UBUNTU
  #-------------------

  describe "ubuntu" do

    before do
      swift_stubs
      @chef_run = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS
      @node = @chef_run.node
      @node.set['lsb']['code'] = 'precise'
      @node.set['swift']['authmode'] = 'swauth'
      @node.set['swift']['network']['container-bind-ip'] = '10.0.0.1'
      @node.set['swift']['network']['container-bind-port'] = '8080'
      @node.set['swift']['disk_enum_expr'] = "[{ 'sda' => {}}]"
      @node.set['swift']['disk_test_filter'] = [ "candidate =~ /sd[^a]/ or candidate =~ /hd[^a]/ or candidate =~ /vd[^a]/ or candidate =~ /xvd[^a]/",
                                         "File.exist?('/dev/' + candidate)",
                                         "not system('/sbin/parted /dev/' + candidate + ' -s print | grep linux-swap')",
                                         "not info.has_key?('removable') or info['removable'] == 0.to_s"]

      # mock out an interface on the storage node
      @node.set["network"] = MOCK_NODE_NETWORK_DATA['network']

      @chef_run.converge "openstack-object-storage::container-server"
    end

    it "installs swift container packages" do
      expect(@chef_run).to install_package "swift-container"
    end

    it "starts swift container services on boot" do
      %w{swift-container swift-container-auditor swift-container-replicator swift-container-updater}.each do |svc|
        expect(@chef_run).to set_service_to_start_on_boot svc
      end
    end

    describe "/etc/swift/container-server.conf" do

      before do
        @file = @chef_run.template "/etc/swift/container-server.conf"
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
