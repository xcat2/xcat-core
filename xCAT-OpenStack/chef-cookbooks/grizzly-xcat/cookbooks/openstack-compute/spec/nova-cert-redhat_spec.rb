require_relative "spec_helper"

describe "openstack-compute::nova-cert" do
  before { compute_stubs }
  describe "redhat" do
    before do
      @chef_run = ::ChefSpec::ChefRunner.new ::REDHAT_OPTS
      @chef_run.converge "openstack-compute::nova-cert"
    end

    it "installs nova cert packages" do
      expect(@chef_run).to upgrade_package "openstack-nova-cert"
    end

    it "starts nova cert on boot" do
      expect(@chef_run).to set_service_to_start_on_boot "openstack-nova-cert"
    end
  end
end
