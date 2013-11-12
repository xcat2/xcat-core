require 'spec_helper'

describe 'openstack-object-storage::common' do

  #-------------------
  # UBUNTU
  #-------------------

  describe "ubuntu" do

    before do
      swift_stubs
      @chef_run = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS
      @node = @chef_run.node
      @node.set['platform_family'] = "debian"
      @node.set['lsb']['codename'] = "precise"
      @node.set['swift']['release'] = "folsom"
      @node.set['swift']['authmode'] = 'swauth'
      @node.set['swift']['git_builder_ip'] = '10.0.0.10'

      # TODO: this does not work
      # ::Chef::Log.should_receive(:info).with("chefspec: precise-updates/folsom")

      @chef_run.converge "openstack-object-storage::common"
    end


    it 'should set syctl paramaters' do
      # N.B. we could examine chef log
      pending "TODO: right now theres no way to do lwrp and test for this"
    end

    it 'installs git package for ring management' do
      expect(@chef_run).to install_package "git"
    end

    describe "/etc/swift" do

      before do
        @file = @chef_run.directory "/etc/swift"
      end

      it "has proper owner" do
        expect(@file).to be_owned_by "swift", "swift"
      end

      it "has proper modes" do
        expect(sprintf("%o", @file.mode)).to eq "700"
      end

    end

    describe "/etc/swift/swift.conf" do

      before do
        @file = @chef_run.file "/etc/swift/swift.conf"
      end

      it "has proper owner" do
        expect(@file).to be_owned_by "swift", "swift"
      end

      it "has proper modes" do
        expect(sprintf("%o", @file.mode)).to eq "700"
      end

    end

    describe "/etc/swift/pull-rings.sh" do

      before do
        @file = @chef_run.template "/etc/swift/pull-rings.sh"
      end

      it "has proper owner" do
        expect(@file).to be_owned_by "swift", "swift"
      end

      it "has proper modes" do
        expect(sprintf("%o", @file.mode)).to eq "700"
      end

      it "template contents" do
        pending "TODO: implement"
      end

    end

  end


end
