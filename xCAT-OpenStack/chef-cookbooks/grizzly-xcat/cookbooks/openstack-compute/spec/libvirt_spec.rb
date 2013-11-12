require_relative "spec_helper"

describe "openstack-compute::libvirt" do
  before { compute_stubs }
  describe "ubuntu" do
    before do
      @chef_run = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS
      @chef_run.converge "openstack-compute::libvirt"
    end

    it "installs libvirt packages" do
      expect(@chef_run).to install_package "libvirt-bin"
    end

    it "does not create libvirtd group and add to nova" do
      pending "TODO: how to test this"
    end

    it "does not symlink qemu-kvm" do
      pending "TODO: how to test this"
    end

    it "starts dbus" do
      expect(@chef_run).to start_service "dbus"
    end

    it "starts dbus on boot" do
      expect(@chef_run).to set_service_to_start_on_boot "dbus"
    end

    it "starts libvirt" do
      expect(@chef_run).to start_service "libvirt-bin"
    end

    it "starts libvirt on boot" do
      expect(@chef_run).to set_service_to_start_on_boot "libvirt-bin"
    end

    it "disables default libvirt network" do
      cmd = "virsh net-autostart default --disable"
      expect(@chef_run).to execute_command cmd
    end

    it "deletes default libvirt network" do
      cmd = "virsh net-destroy default"
      expect(@chef_run).to execute_command cmd
    end

    describe "libvirtd.conf" do
      before do
        @file = @chef_run.template "/etc/libvirt/libvirtd.conf"
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

    describe "libvirt-bin" do
      before do
        @file = @chef_run.template "/etc/default/libvirt-bin"
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

    it "does not create /etc/sysconfig/libvirtd" do
      pending "TODO: how to test this"
    end
  end
end
