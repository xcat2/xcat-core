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
      @node.set['swift']['statistics']['enabled'] = true
      @node.set['swift']['swauth_source'] = 'package'
      @node.set['swift']['platform']['swauth_packages'] = ['swauth']

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

    describe "/usr/local/bin/swift-statsd-publish.py" do

      before do
       @file = @chef_run.template "/usr/local/bin/swift-statsd-publish.py"
      end

      it "has proper owner" do
        expect(@file).to be_owned_by "root", "root"
      end

      it "has proper modes" do
       expect(sprintf("%o", @file.mode)).to eq "755"
      end

      it "has expected statsd host" do
        expect(@chef_run).to create_file_with_content @file.name,
          "self.statsd_host              = '127.0.0.1'"
      end

    end

  end

end
