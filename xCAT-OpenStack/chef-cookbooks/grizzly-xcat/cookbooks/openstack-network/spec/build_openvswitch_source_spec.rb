require_relative 'spec_helper'

describe "openvswitch::build_openvswitch_source" do
  before do
    quantum_stubs
    @chef_run = ::ChefSpec::ChefRunner.new(::UBUNTU_OPTS)
    @chef_run.converge "openstack-network::openvswitch"
    @chef_run.converge "openstack-network::build_openvswitch_source"
  end

  # since our mocked version of ubuntu is precise, our compile
  # utilities should be installed to build OVS from source
  it "installs openvswitch build dependencies" do
    [ "build-essential", "pkg-config", "fakeroot", "libssl-dev", "openssl", "debhelper", "autoconf" ].each do |pkg|
      expect(@chef_run).to install_package pkg
    end
  end

  it "installs openvswitch switch dpkg" do
    pkg = @chef_run.dpkg_package("openvswitch-switch")

    pkg.source.should == "/var/chef/cache/22df718eb81fcfe93228e9bba8575e50/openvswitch-switch_1.10.2-1_amd64.deb"
    pkg.action.should == [:nothing]
  end

  it "installs openvswitch datapath dkms dpkg" do
    pkg = @chef_run.dpkg_package("openvswitch-datapath-dkms")

    pkg.source.should == "/var/chef/cache/22df718eb81fcfe93228e9bba8575e50/openvswitch-datapath-dkms_1.10.2-1_all.deb"
    pkg.action.should == [:nothing]
  end

  it "installs openvswitch pki dpkg" do
    pkg = @chef_run.dpkg_package("openvswitch-pki")

    pkg.source.should == "/var/chef/cache/22df718eb81fcfe93228e9bba8575e50/openvswitch-pki_1.10.2-1_all.deb"
    pkg.action.should == [:nothing]
  end

  it "installs openvswitch common dpkg" do
    pkg = @chef_run.dpkg_package("openvswitch-common")

    pkg.source.should == "/var/chef/cache/22df718eb81fcfe93228e9bba8575e50/openvswitch-common_1.10.2-1_amd64.deb"
    pkg.action.should == [:nothing]
  end
end
