require_relative "spec_helper"

describe "openstack-image::registry" do
  before { image_stubs }
  describe "redhat" do
    before do
      @chef_run = ::ChefSpec::ChefRunner.new ::REDHAT_OPTS
      @chef_run.converge "openstack-image::registry"
    end

    it "installs mysql python packages" do
      expect(@chef_run).to install_package "MySQL-python"
    end

    it "installs glance packages" do
      expect(@chef_run).to upgrade_package "openstack-glance"
      expect(@chef_run).to upgrade_package "openstack-swift"
      expect(@chef_run).to upgrade_package "cronie"
    end

    it "starts glance registry on boot" do
      expected = "openstack-glance-registry"
      expect(@chef_run).to set_service_to_start_on_boot expected
    end

    it "doesn't version the database" do
      opts = ::REDHAT_OPTS.merge(:evaluate_guards => true)
      chef_run = ::ChefSpec::ChefRunner.new opts
      chef_run.stub_command("glance-manage db_version", false)
      chef_run.converge "openstack-image::registry"
      cmd = "glance-manage version_control 0"

      expect(chef_run).not_to execute_command cmd
    end
  end
end
