require_relative "spec_helper"

describe "openstack-block-storage::api" do
  before { block_storage_stubs }
  describe "opensuse" do
    before do
      @chef_run = ::ChefSpec::ChefRunner.new ::OPENSUSE_OPTS
      @chef_run.converge "openstack-block-storage::api"
    end

    it "installs cinder api packages" do
      expect(@chef_run).to upgrade_package "openstack-cinder-api"
    end

    it "installs mysql python packages by default" do
      expect(@chef_run).to upgrade_package "python-mysql"
    end

    it "installs postgresql python packages if explicitly told" do
      chef_run = ::ChefSpec::ChefRunner.new ::OPENSUSE_OPTS
      node = chef_run.node
      node.set["openstack"]["db"]["volume"]["db_type"] = "postgresql"
      chef_run.converge "openstack-block-storage::api"

      expect(chef_run).to upgrade_package "python-psycopg2"
      expect(chef_run).not_to upgrade_package "python-mysql"
    end

    it "starts cinder api on boot" do
      expect(@chef_run).to set_service_to_start_on_boot "openstack-cinder-api"
    end

    expect_creates_policy_json(
      "service[cinder-api]", "openstack-cinder", "openstack-cinder")
    expect_creates_cinder_conf(
      "service[cinder-api]", "openstack-cinder", "openstack-cinder")
  end
end
