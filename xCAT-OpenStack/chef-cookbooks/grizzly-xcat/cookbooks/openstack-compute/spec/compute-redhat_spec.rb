require_relative "spec_helper"

describe "openstack-compute::compute" do
  before { compute_stubs }
  describe "redhat" do
    before do
      @chef_run = ::ChefSpec::ChefRunner.new ::REDHAT_OPTS
      @chef_run.converge "openstack-compute::compute"
    end

    it "does not install kvm when virt_type is 'kvm'" do
      chef_run = ::ChefSpec::ChefRunner.new ::REDHAT_OPTS
      node = chef_run.node
      node.set["openstack"]["compute"]["libvirt"]["virt_type"] = "kvm"
      chef_run.converge "openstack-compute::compute"
      expect(chef_run).to_not upgrade_package "nova-compute-kvm"
    end

    it "does not install qemu when virt_type is 'qemu'" do
      chef_run = ::ChefSpec::ChefRunner.new ::REDHAT_OPTS
      node = chef_run.node
      node.set["openstack"]["compute"]["libvirt"]["virt_type"] = "qemu"
      chef_run.converge "openstack-compute::compute"
      expect(chef_run).to_not upgrade_package "nova-compute-qemu"
    end

    it "installs nova compute packages" do
      expect(@chef_run).to upgrade_package "openstack-nova-compute"
    end

    it "installs nfs client packages" do
      expect(@chef_run).to upgrade_package "nfs-utils"
      expect(@chef_run).to upgrade_package "nfs-utils-lib"
    end

    it "starts nova compute on boot" do
      expected = "openstack-nova-compute"
      expect(@chef_run).to set_service_to_start_on_boot expected
    end

    it "starts nova compute" do
      expect(@chef_run).to start_service "openstack-nova-compute"
    end
  end
end
