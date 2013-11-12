require_relative "spec_helper"

describe "openstack-compute::api-ec2" do
  before { compute_stubs }
  describe "ubuntu" do
    before do
      @chef_run = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS
      @chef_run.converge "openstack-compute::api-ec2"
    end

    expect_runs_nova_common_recipe

    expect_creates_nova_lock_dir

    expect_installs_python_keystone

    it "installs ec2 api packages" do
      expect(@chef_run).to upgrade_package "nova-api-ec2"
    end

    it "starts ec2 api on boot" do
      expect(@chef_run).to set_service_to_start_on_boot "nova-api-ec2"
    end

    expect_creates_api_paste "service[nova-api-ec2]"
  end
end
