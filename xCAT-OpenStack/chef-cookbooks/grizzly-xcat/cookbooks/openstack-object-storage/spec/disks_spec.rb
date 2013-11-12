require 'spec_helper'

describe 'openstack-object-storage::disks' do

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
      @node.set['swift']['disk_enum_expr'] = "[{ 'sda' => {}}]"
      @node.set['swift']['disk_test_filter'] = [ "candidate =~ /sd[^a]/ or candidate =~ /hd[^a]/ or candidate =~ /vd[^a]/ or candidate =~ /xvd[^a]/",
                                         "File.exist?('/dev/' + candidate)",
                                         "not system('/sbin/parted /dev/' + candidate + ' -s print | grep linux-swap')",
                                         "not info.has_key?('removable') or info['removable'] == 0.to_s"]

      # mock out an interface on the storage node
      @node.set["network"] = MOCK_NODE_NETWORK_DATA['network']

      @chef_run.converge "openstack-object-storage::disks"
    end

    it 'installs xfs progs package' do
      expect(@chef_run).to install_package "xfsprogs"
    end

    it 'installs parted package' do
      expect(@chef_run).to install_package "parted"
    end

  end


end
