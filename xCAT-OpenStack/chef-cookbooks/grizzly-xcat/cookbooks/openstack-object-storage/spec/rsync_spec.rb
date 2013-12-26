require 'spec_helper'

describe 'openstack-object-storage::rsync' do

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
      @node.set['swift']['release'] = "grizzly"
      @node.set['swift']['authmode'] = 'swauth'
      @node.set['swift']['git_builder_ip'] = '10.0.0.10'
      @chef_run.converge "openstack-object-storage::rsync"
    end

    it 'installs git package for ring management' do
      expect(@chef_run).to install_package "rsync"
    end

    it "starts rsync service on boot" do
      %w{rsync}.each do |svc|
        expect(@chef_run).to set_service_to_start_on_boot svc
      end
    end

    describe "/etc/rsyncd.conf" do

      before do
        @file = @chef_run.template "/etc/rsyncd.conf"
      end

      it "has proper modes" do
        expect(sprintf("%o", @file.mode)).to eq "644"
      end

      it "template contents" do
        pending "TODO: implement"
      end

    end

  end

end
