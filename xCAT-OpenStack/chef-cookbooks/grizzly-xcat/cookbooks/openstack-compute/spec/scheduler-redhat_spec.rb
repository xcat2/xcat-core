require_relative "spec_helper"

describe "openstack-compute::scheduler" do
  before { compute_stubs }
  describe "redhat" do
    before do
      @chef_run = ::ChefSpec::ChefRunner.new ::REDHAT_OPTS
      @chef_run.converge "openstack-compute::scheduler"
    end

    it "installs nova scheduler packages" do
      expect(@chef_run).to upgrade_package "openstack-nova-scheduler"
    end

    it "starts nova scheduler" do
      expect(@chef_run).to start_service "openstack-nova-scheduler"
    end

    it "starts nova scheduler on boot" do
      expected = "openstack-nova-scheduler"
      expect(@chef_run).to set_service_to_start_on_boot expected
    end
  end
end
