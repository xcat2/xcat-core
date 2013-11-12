require_relative "spec_helper"

describe "openstack-image::registry" do
  before { image_stubs }
  describe "ubuntu" do
    before do
      @chef_run = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS do |n|
        n.set["openstack"]["image"]["syslog"]["use"] = true
      end
      @chef_run.converge "openstack-image::registry"
    end

    expect_runs_openstack_common_logging_recipe

    it "doesn't run logging recipe" do
      chef_run = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS
      chef_run.converge "openstack-image::registry"

      expect(chef_run).not_to include_recipe "openstack-common::logging"
    end

    expect_installs_python_keystone

    expect_installs_curl

    it "installs mysql python packages" do
      expect(@chef_run).to install_package "python-mysqldb"
    end

    expect_installs_ubuntu_glance_packages

    expect_creates_cache_dir

    it "starts glance registry on boot" do
      expect(@chef_run).to set_service_to_start_on_boot "glance-registry"
    end

    describe "version_control" do
      before { @cmd = "glance-manage version_control 0" }

      it "versions the database" do
        opts = ::UBUNTU_OPTS.merge(:evaluate_guards => true)
        chef_run = ::ChefSpec::ChefRunner.new opts
        chef_run.stub_command("glance-manage db_version", false)
        chef_run.converge "openstack-image::registry"

        expect(chef_run).to execute_command @cmd
      end

      it "doesn't version when glance-manage db_version false" do
        opts = ::UBUNTU_OPTS.merge(:evaluate_guards => true)
        chef_run = ::ChefSpec::ChefRunner.new opts
        chef_run.stub_command("glance-manage db_version", true)
        chef_run.converge "openstack-image::registry"

        expect(chef_run).not_to execute_command @cmd
      end
    end

    it "deletes glance.sqlite" do
      expect(@chef_run).to delete_file "/var/lib/glance/glance.sqlite"
    end

    expect_creates_glance_dir

    describe "glance-registry.conf" do
      before do
        @file = @chef_run.template "/etc/glance/glance-registry.conf"
      end

      it "has proper owner" do
        expect(@file).to be_owned_by "root", "root"
      end

      it "has proper modes" do
        expect(sprintf("%o", @file.mode)).to eq "644"
      end

      it "has bind host when bind_interface not specified" do
        expect(@chef_run).to create_file_with_content @file.name,
          "bind_host = 127.0.0.1"
      end

      it "has bind host when bind_interface specified" do
        chef_run = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS do |n|
          n.set["openstack"]["image"]["registry"]["bind_interface"] = "lo"
        end
        chef_run.converge "openstack-image::registry"

        expect(chef_run).to create_file_with_content @file.name,
          "bind_host = 127.0.1.1"
      end

      it "notifies image-registry restart" do
        expect(@file).to notify "service[image-registry]", :restart
      end
    end

    describe "db_sync" do
      before do
        @cmd = "glance-manage db_sync"
      end

      it "runs migrations" do
        expect(@chef_run).to execute_command @cmd
      end

      it "doesn't run migrations" do
        opts = ::UBUNTU_OPTS.merge(:evaluate_guards => true)
        chef_run = ::ChefSpec::ChefRunner.new(opts) do |n|
          n.set["openstack"]["image"]["db"]["migrate"] = false
        end
        # Lame we must still stub this, since the recipe contains shell
        # guards.  Need to work on a way to resolve this.
        chef_run.stub_command("glance-manage db_version", false)
        chef_run.converge "openstack-image::registry"

        expect(chef_run).not_to execute_command @cmd
      end
    end

    describe "glance-registry-paste.ini" do
      before do
        @file = @chef_run.template "/etc/glance/glance-registry-paste.ini"
      end

      it "has proper owner" do
        expect(@file).to be_owned_by "root", "root"
      end

      it "has proper modes" do
        expect(sprintf("%o", @file.mode)).to eq "644"
      end

      it "template contents" do
        pending "TODO: implement"
      end

      it "notifies image-registry restart" do
        expect(@file).to notify "service[image-registry]", :restart
      end
    end
  end
end
