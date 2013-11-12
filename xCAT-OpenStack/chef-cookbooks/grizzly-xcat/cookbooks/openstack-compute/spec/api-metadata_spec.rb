require_relative "spec_helper"

describe "openstack-compute::api-metadata" do
  before { compute_stubs }
  describe "ubuntu" do
    before do
      @chef_run = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS
      @chef_run.converge "openstack-compute::api-metadata"
    end

    expect_runs_nova_common_recipe

    expect_creates_nova_lock_dir

    expect_installs_python_keystone

    it "installs metadata api packages" do
      expect(@chef_run).to upgrade_package "nova-api-metadata"
    end

    it "starts metadata api on boot" do
      expect(@chef_run).to set_service_to_start_on_boot "nova-api-metadata"
    end

    expect_creates_api_paste "service[nova-api-metadata]"
  end
end
