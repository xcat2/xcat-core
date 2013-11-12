require 'spec_helper'

describe 'openstack-object-storage::management-server' do

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

      @chef_run.converge "openstack-object-storage::management-server"
    end

    it "installs swift swauth package" do
      expect(@chef_run).to install_package "swauth"
    end

    describe "/etc/swift/dispersion.conf" do

      before do
        @file = @chef_run.template "/etc/swift/dispersion.conf"
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
