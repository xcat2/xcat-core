require_relative "spec_helper"

describe "openstack-block-storage::volume" do
  before { block_storage_stubs }
  describe "ubuntu" do
    before do
      @chef_run = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS do |n|
        n.set["openstack"]["block-storage"]["syslog"]["use"] = true
      end
      @chef_run.converge "openstack-block-storage::volume"
    end

    expect_runs_openstack_common_logging_recipe

    it "doesn't run logging recipe" do
      chef_run = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS
      chef_run.converge "openstack-block-storage::volume"

      expect(chef_run).not_to include_recipe "openstack-common::logging"
    end

    it "installs cinder volume packages" do
      expect(@chef_run).to upgrade_package "cinder-volume"
    end

    it "installs mysql python packages by default" do
      expect(@chef_run).to upgrade_package "python-mysqldb"
    end

    it "installs postgresql python packages if explicitly told" do
      chef_run = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS
      node = chef_run.node
      node.set["openstack"]["db"]["volume"]["db_type"] = "postgresql"
      chef_run.converge "openstack-block-storage::volume"

      expect(chef_run).to upgrade_package "python-psycopg2"
      expect(chef_run).not_to upgrade_package "python-mysqldb"
    end

    it "installs cinder iscsi packages" do
      expect(@chef_run).to upgrade_package "tgt"
    end

    it "installs nfs packages" do
      chef_run = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS do |n|
        n.set["openstack"]["block-storage"]["volume"]["driver"] = "cinder.volume.drivers.netapp.nfs.NetAppDirect7modeNfsDriver"
      end
      chef_run.converge "openstack-block-storage::volume"

      expect(chef_run).to upgrade_package "nfs-common"
    end

    it "creates the nfs mount point" do
      chef_run = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS do |n|
        n.set["openstack"]["block-storage"]["volume"]["driver"] = "cinder.volume.drivers.netapp.nfs.NetAppDirect7modeNfsDriver"
      end
      chef_run.converge "openstack-block-storage::volume"

      expect(chef_run).to create_directory "/mnt/cinder-volumes"
    end

    it "configures netapp dfm password" do
      ::Chef::Recipe.any_instance.stub(:service_password).with("netapp").
        and_return "netapp-pass"
      chef_run = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS do |n|
        n.set["openstack"]["block-storage"]["volume"]["driver"] = "cinder.volume.drivers.netapp.iscsi.NetAppISCSIDriver"
      end
      chef_run.converge "openstack-block-storage::volume"
      n = chef_run.node["openstack"]["block-storage"]["netapp"]["dfm_password"]

      expect(n).to eq "netapp-pass"
    end

    it "configures rbd password" do
      ::Chef::Recipe.any_instance.stub(:service_password).with("rbd").
        and_return "rbd-pass"
      chef_run = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS do |n|
        n.set["openstack"]["block-storage"]["volume"]["driver"] = "cinder.volume.drivers.RBDDriver"
      end
      chef_run.converge "openstack-block-storage::volume"
      n = chef_run.node["openstack"]["block-storage"]["rbd_secret_uuid"]

      expect(n).to eq "rbd-pass"
    end

    it "starts cinder volume" do
      expect(@chef_run).to start_service "cinder-volume"
    end

    it "starts cinder volume on boot" do
      expect(@chef_run).to set_service_to_start_on_boot "cinder-volume"
    end

    expect_creates_cinder_conf "service[cinder-volume]", "cinder", "cinder"

    it "starts iscsi target on boot" do
      expect(@chef_run).to set_service_to_start_on_boot "tgt"
    end

    describe "targets.conf" do
      before do
        @file = @chef_run.template "/etc/tgt/targets.conf"
      end

      it "has proper modes" do
        expect(sprintf("%o", @file.mode)).to eq "600"
      end

      it "notifies iscsi restart" do
        expect(@file).to notify "service[iscsitarget]", :restart
      end

      it "has ubuntu include" do
        expect(@chef_run).to create_file_with_content @file.name,
          "include /etc/tgt/conf.d/*.conf"
        expect(@chef_run).not_to create_file_with_content @file.name,
          "include /var/lib/cinder/volumes/*"
      end
    end
  end
end
