require_relative "spec_helper"

describe "openstack-compute::api-metadata" do
  before { compute_stubs }
  describe "redhat" do
    before do
      @chef_run = ::ChefSpec::ChefRunner.new ::REDHAT_OPTS
      @chef_run.converge "openstack-compute::api-metadata"
    end

    it "installs metadata api packages" do
      expect(@chef_run).to upgrade_package "openstack-nova-api"
    end

    it "starts metadata api on boot" do
      expect(@chef_run).to set_service_to_start_on_boot "openstack-nova-api"
    end
  end
end
