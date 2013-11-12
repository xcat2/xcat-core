require_relative "spec_helper"

describe "openstack-compute::libvirt" do
  before do
    compute_stubs

    # This is stubbed b/c systems without '/boot/grub/menul.lst`,
    # fail to pass tests.  This can be removed if a check verifies
    # the files existence prior to File#open.
    ::File.stub(:open).and_call_original
  end

  describe "suse" do
    before do
      @chef_run = ::ChefSpec::ChefRunner.new ::OPENSUSE_OPTS
      @chef_run.converge "openstack-compute::libvirt"
    end

    it "installs libvirt packages" do
      expect(@chef_run).to install_package "libvirt"
    end

    it "starts libvirt" do
      expect(@chef_run).to start_service "libvirtd"
    end

    it "starts libvirt on boot" do
      expect(@chef_run).to set_service_to_start_on_boot "libvirtd"
    end

    describe "libvirtd" do
      before do
        @file = @chef_run.template "/etc/sysconfig/libvirtd"
      end

      it "has proper owner" do
        expect(@file).to be_owned_by "root", "root"
      end

      it "has proper modes" do
        expect(sprintf("%o", @file.mode)).to eq "644"
      end

      it "template contents" do
        pending "TODO: implement"
      end

      it "notifies libvirt-bin restart" do
        expect(@file).to notify "service[libvirt-bin]", :restart
      end
    end

    it "installs kvm packages" do
      expect(@chef_run).to install_package "kvm"
    end

    it "installs qemu packages" do
      chef_run = ::ChefSpec::ChefRunner.new ::OPENSUSE_OPTS do |node|
        node.set["openstack"]["compute"]["libvirt"]["virt_type"] = "qemu"
      end
      chef_run.converge "openstack-compute::libvirt"
      expect(chef_run).to install_package "kvm"
    end

    it "installs xen packages" do
      chef_run = ::ChefSpec::ChefRunner.new ::OPENSUSE_OPTS do |node|
        node.set["openstack"]["compute"]["libvirt"]["virt_type"] = "xen"
      end
      chef_run.converge "openstack-compute::libvirt"
      ["kernel-xen", "xen", "xen-tools"].each do |pkg|
        expect(chef_run).to install_package pkg
      end
    end

    describe "lxc" do
      before do
        @chef_run_lxc = ::ChefSpec::ChefRunner.new ::OPENSUSE_OPTS do |node|
          node.set["openstack"]["compute"]["libvirt"]["virt_type"] = "lxc"
        end
        @chef_run_lxc.converge "openstack-compute::libvirt"
      end

      it "installs packages" do
        expect(@chef_run_lxc).to install_package "lxc"
      end

      it "starts boot.cgroupslxc" do
        expect(@chef_run_lxc).to start_service "boot.cgroup"
      end

      it "starts boot.cgroups on boot" do
        expect(@chef_run_lxc).to set_service_to_start_on_boot "boot.cgroup"
      end
    end
  end
end
