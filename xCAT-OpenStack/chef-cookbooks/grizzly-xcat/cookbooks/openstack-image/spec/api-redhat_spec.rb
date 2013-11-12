require_relative "spec_helper"

describe "openstack-image::api" do
  before { image_stubs }
  describe "redhat" do
    before do
      @chef_run = ::ChefSpec::ChefRunner.new ::REDHAT_OPTS
      @chef_run.converge "openstack-image::api"
    end

    it "starts glance api on boot" do
      expect(@chef_run).to set_service_to_start_on_boot "openstack-glance-api"
    end
  end
end
