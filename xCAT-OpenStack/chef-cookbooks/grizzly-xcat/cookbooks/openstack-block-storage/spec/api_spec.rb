require_relative "spec_helper"

describe "openstack-block-storage::api" do
  before { block_storage_stubs }
  describe "ubuntu" do
    before do
      @chef_run = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS do |n|
        n.set["openstack"]["block-storage"]["syslog"]["use"] = true
      end
      @chef_run.converge "openstack-block-storage::api"
    end

    expect_runs_openstack_common_logging_recipe

    it "doesn't run logging recipe" do
      chef_run = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS
      chef_run.converge "openstack-block-storage::api"

      expect(chef_run).not_to include_recipe "openstack-common::logging"
    end

    it "installs cinder api packages" do
      expect(@chef_run).to upgrade_package "cinder-api"
      expect(@chef_run).to upgrade_package "python-cinderclient"
    end

    it "installs mysql python packages by default" do
      expect(@chef_run).to upgrade_package "python-mysqldb"
    end

    it "installs postgresql python packages if explicitly told" do
      chef_run = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS
      node = chef_run.node
      node.set["openstack"]["db"]["volume"]["db_type"] = "postgresql"
      chef_run.converge "openstack-block-storage::api"

      expect(chef_run).to upgrade_package "python-psycopg2"
      expect(chef_run).not_to upgrade_package "python-mysqldb"
    end

    describe "/var/cache/cinder" do
      before do
        @dir = @chef_run.directory "/var/cache/cinder"
      end

      it "has proper owner" do
        expect(@dir).to be_owned_by "cinder", "cinder"
      end

      it "has proper modes" do
        expect(sprintf("%o", @dir.mode)).to eq "700"
      end
    end

    it "starts cinder api on boot" do
      expect(@chef_run).to set_service_to_start_on_boot "cinder-api"
    end

    expect_creates_cinder_conf "service[cinder-api]", "cinder", "cinder"

    describe "cinder.conf" do
      before do
        @file = "/etc/cinder/cinder.conf"
      end

      it "runs logging recipe if node attributes say to" do
        expect(@chef_run).to create_file_with_content @file,
          "log_config = /etc/openstack/logging.conf"
      end

      it "doesn't run logging recipe" do
        chef_run = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS
        chef_run.converge "openstack-block-storage::api"

        expect(chef_run).not_to create_file_with_content @file,
          "log_config = /etc/openstack/logging.conf"
      end

      it "has rbd driver settings" do
        chef_run = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS do |n|
          n.set["openstack"]["block-storage"]["volume"] = {
            "driver" => "cinder.volume.drivers.RBDDriver"
          }
        end
        chef_run.converge "openstack-block-storage::api"

        expect(chef_run).to create_file_with_content @file,
          /^rbd_/
        expect(chef_run).not_to create_file_with_content @file,
          /^netapp_/
      end

      it "has netapp driver settings" do
        chef_run = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS do |n|
          n.set["openstack"]["block-storage"]["volume"] = {
            "driver" => "cinder.volume.drivers.netapp.NetAppISCSIDriver"
          }
        end
        chef_run.converge "openstack-block-storage::api"

        expect(chef_run).to create_file_with_content @file,
          /^netapp_/
        expect(chef_run).not_to create_file_with_content @file,
          /^rbd_/
      end
    end

    it "runs db migrations" do
      cmd = "cinder-manage db sync"

      expect(@chef_run).to execute_command cmd
    end

    expect_creates_policy_json "service[cinder-api]", "cinder", "cinder"

    describe "api-paste.ini" do
      before do
        @file = @chef_run.template "/etc/cinder/api-paste.ini"
      end

      it "has proper owner" do
        expect(@file).to be_owned_by "cinder", "cinder"
      end

      it "has proper modes" do
        expect(sprintf("%o", @file.mode)).to eq "644"
      end

      it "has signing_dir" do
        expect(@chef_run).to create_file_with_content @file.name,
          "signing_dir = /var/cache/cinder/api"
      end

      it "notifies cinder-api restart" do
        expect(@file).to notify "service[cinder-api]", :restart
      end
    end
  end
end
