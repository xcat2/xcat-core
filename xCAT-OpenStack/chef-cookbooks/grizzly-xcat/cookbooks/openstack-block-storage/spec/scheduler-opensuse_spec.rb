require_relative "spec_helper"

describe "openstack-block-storage::scheduler" do
  before { block_storage_stubs }
  describe "opensuse" do
    before do
      @chef_run = ::ChefSpec::ChefRunner.new ::OPENSUSE_OPTS
      @chef_run.converge "openstack-block-storage::scheduler"
    end

    it "installs cinder api packages" do
      expect(@chef_run).to upgrade_package "openstack-cinder-scheduler"
    end

    it "does not upgrade stevedore" do
      chef_run = ::ChefSpec::ChefRunner.new ::OPENSUSE_OPTS
      chef_run.converge "openstack-block-storage::scheduler"

      expect(chef_run).not_to upgrade_python_pip "stevedore"
    end

    it "installs mysql python packages by default" do
      expect(@chef_run).to upgrade_package "python-mysql"
    end

    it "installs postgresql python packages if explicitly told" do
      chef_run = ::ChefSpec::ChefRunner.new ::OPENSUSE_OPTS
      node = chef_run.node
      node.set["openstack"]["db"]["volume"]["db_type"] = "postgresql"
      chef_run.converge "openstack-block-storage::scheduler"

      expect(chef_run).to upgrade_package "python-psycopg2"
      expect(chef_run).not_to upgrade_package "python-mysql"
    end

    it "starts cinder scheduler" do
      expect(@chef_run).to start_service "openstack-cinder-scheduler"
    end

    it "starts cinder scheduler on boot" do
      expect(@chef_run).to set_service_to_start_on_boot "openstack-cinder-scheduler"
    end
  end
end
