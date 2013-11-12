require_relative "spec_helper"

describe "openstack-compute::libvirt" do
  before { compute_stubs }
  describe "redhat" do
    before do
      @chef_run = ::ChefSpec::ChefRunner.new ::REDHAT_OPTS
      @chef_run.converge "openstack-compute::libvirt"
    end

    it "installs libvirt packages" do
      expect(@chef_run).to install_package "libvirt"
    end

    it "creates libvirtd group and adds nova as a member" do
      expect(@chef_run).to create_group "libvirtd"
      libvirt_group = @chef_run.group("libvirtd")
      libvirt_group.members.should == ["nova"]
    end

    it "symlinks qemu-kvm" do
      link = @chef_run.link "/usr/bin/qemu-system-x86_64"
      expect(link).to link_to "/usr/libexec/qemu-kvm"
    end

    it "starts libvirt" do
      expect(@chef_run).to start_service "libvirtd"
    end

    it "starts libvirt on boot" do
      expect(@chef_run).to set_service_to_start_on_boot "libvirtd"
    end

    it "does not create /etc/default/libvirt-bin" do
      pending "TODO: how to test this"
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
  end
end
