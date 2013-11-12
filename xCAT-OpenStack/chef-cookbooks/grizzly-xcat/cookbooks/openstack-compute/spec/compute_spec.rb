require_relative "spec_helper"

describe "openstack-compute::compute" do
  before { compute_stubs }
  describe "ubuntu" do
    before do
      @chef_run = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS
      @chef_run.converge "openstack-compute::compute"
    end

    expect_runs_nova_common_recipe

    it "runs api-metadata recipe" do
      expect(@chef_run).to include_recipe "openstack-compute::api-metadata"
    end

    it "runs network recipe" do
      expect(@chef_run).to include_recipe "openstack-compute::network"
    end

    it "doesn't run network recipe with openstack-network::server" do
      chef_run = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS
      node = chef_run.node
      node.run_list.stub("include?").and_return true
      chef_run.converge "openstack-compute::compute"

      expect(chef_run).not_to include_recipe "openstack-compute::network"
    end

    it "installs nova compute packages" do
      expect(@chef_run).to upgrade_package "nova-compute"
    end

    it "installs nfs client packages" do
      expect(@chef_run).to upgrade_package "nfs-common"
    end

    it "installs kvm when virt_type is 'kvm'" do
      chef_run = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS
      node = chef_run.node
      node.set["openstack"]["compute"]["libvirt"]["virt_type"] = "kvm"
      chef_run.converge "openstack-compute::compute"

      expect(chef_run).to upgrade_package "nova-compute-kvm"
      expect(chef_run).not_to upgrade_package "nova-compute-qemu"
    end

    it "installs qemu when virt_type is 'qemu'" do
      chef_run = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS
      node = chef_run.node
      node.set["openstack"]["compute"]["libvirt"]["virt_type"] = "qemu"
      chef_run.converge "openstack-compute::compute"

      expect(chef_run).to upgrade_package "nova-compute-qemu"
      expect(chef_run).not_to upgrade_package "nova-compute-kvm"
    end

    describe "nova-compute.conf" do
      before do
        @file = @chef_run.cookbook_file "/etc/nova/nova-compute.conf"
      end

      it "has proper modes" do
        expect(sprintf("%o", @file.mode)).to eq "644"
      end

      it "template contents" do
        pending "TODO: implement"
      end
    end

    it "starts nova compute on boot" do
      expect(@chef_run).to set_service_to_start_on_boot "nova-compute"
    end

    it "starts nova compute" do
      expect(@chef_run).to start_service "nova-compute"
    end

    it "runs libvirt recipe" do
      expect(@chef_run).to include_recipe "openstack-compute::libvirt"
    end
  end
end
