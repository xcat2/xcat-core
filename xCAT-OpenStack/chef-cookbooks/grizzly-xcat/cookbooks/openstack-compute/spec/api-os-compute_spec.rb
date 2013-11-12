require_relative "spec_helper"

describe "openstack-compute::api-os-compute" do
  before { compute_stubs }
  describe "ubuntu" do
    before do
      @chef_run = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS
      @chef_run.converge "openstack-compute::api-os-compute"
    end

    expect_runs_nova_common_recipe

    expect_creates_nova_lock_dir

    describe "/var/cache/nova" do
      before do
        @dir = @chef_run.directory "/var/cache/nova"
      end

      it "has proper owner" do
        expect(@dir).to be_owned_by "nova", "nova"
      end

      it "has proper modes" do
        expect(sprintf("%o", @dir.mode)).to eq "700"
      end
    end

    expect_installs_python_keystone

    it "installs openstack api packages" do
      expect(@chef_run).to upgrade_package "nova-api-os-compute"
    end

    it "starts openstack api on boot" do
      expect(@chef_run).to set_service_to_start_on_boot "nova-api-os-compute"
    end

    it "starts openstack api now" do
      expect(@chef_run).to start_service "nova-api-os-compute"
    end

    expect_creates_api_paste "service[nova-api-os-compute]"
  end
end
