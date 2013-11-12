require_relative "spec_helper"

describe "openstack-block-storage::scheduler" do
  before { block_storage_stubs }
  describe "ubuntu" do
    before do
      @chef_run = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS do |n|
        n.set["openstack"]["block-storage"]["syslog"]["use"] = true
      end
      @chef_run.converge "openstack-block-storage::scheduler"
    end

    expect_runs_openstack_common_logging_recipe

    it "doesn't run logging recipe" do
      chef_run = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS
      chef_run.converge "openstack-block-storage::scheduler"

      expect(chef_run).not_to include_recipe "openstack-common::logging"
    end

    it "installs cinder api packages" do
      expect(@chef_run).to upgrade_package "cinder-scheduler"
    end

    it "upgrades stevedore" do
      expect(@chef_run).to upgrade_python_pip "stevedore"
    end

    it "does not upgrade stevedore" do
      opts = ::UBUNTU_OPTS.merge(:version => "10.04")
      chef_run = ::ChefSpec::ChefRunner.new opts
      chef_run.converge "openstack-block-storage::scheduler"

      expect(chef_run).not_to upgrade_python_pip "stevedore"
    end

    it "installs mysql python packages by default" do
      expect(@chef_run).to upgrade_package "python-mysqldb"
    end

    it "installs postgresql python packages if explicitly told" do
      chef_run = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS
      node = chef_run.node
      node.set["openstack"]["db"]["volume"]["db_type"] = "postgresql"
      chef_run.converge "openstack-block-storage::scheduler"

      expect(chef_run).to upgrade_package "python-psycopg2"
      expect(chef_run).not_to upgrade_package "python-mysqldb"
    end

    it "starts cinder scheduler" do
      expect(@chef_run).to start_service "cinder-scheduler"
    end

    it "starts cinder scheduler on boot" do
      expect(@chef_run).to set_service_to_start_on_boot "cinder-scheduler"
    end

    it "doesn't run logging recipe" do
      expect(@chef_run).to set_service_to_start_on_boot "cinder-scheduler"
    end

    it "doesn't setup cron when no metering" do
      expect(@chef_run.cron("cinder-volume-usage-audit")).to be_nil
    end

    it "creates cron metering default" do
      ::Chef::Recipe.any_instance.stub(:search).
        with(:node, "roles:os-block-storage-scheduler").
        and_return([OpenStruct.new(:name => "fauxhai.local")])
      chef_run = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS do |n|
        n.set["openstack"]["metering"] = true
      end
      chef_run.converge "openstack-block-storage::scheduler"
      cron = chef_run.cron "cinder-volume-usage-audit"
      bin_str="/usr/bin/cinder-volume-usage-audit > /var/log/cinder/audit.log"
      expect(cron.command).to match(/#{bin_str}/)
      crontests = [ [:minute, '00'], [:hour, '*'], [:day, '*'],
                    [:weekday, '*'], [:month, '*'], [:user, 'cinder'] ]
      crontests.each do |k,v|
        expect(cron.send(k)).to eq v
      end
      expect(cron.action).to include :create
    end

    it "creates cron metering custom" do
      crontests = [ [:minute, '50'], [:hour, '23'], [:day, '6'],
                    [:weekday, '5'], [:month, '11'], [:user, 'foobar'] ]
      ::Chef::Recipe.any_instance.stub(:search).
        with(:node, "roles:os-block-storage-scheduler").
        and_return([OpenStruct.new(:name => "foobar")])
      chef_run = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS do |n|
        n.set["openstack"]["metering"] = true
        crontests.each do |k,v|
          n.set["openstack"]["block-storage"]["cron"][k.to_s] = v
        end
        n.set["openstack"]["block-storage"]["user"] = "foobar"
      end
      chef_run.converge "openstack-block-storage::scheduler"
      cron = chef_run.cron "cinder-volume-usage-audit"
      crontests.each do |k,v|
        expect(cron.send(k)).to eq v
      end
      expect(cron.action).to include :delete
    end

    expect_creates_cinder_conf "service[cinder-scheduler]", "cinder", "cinder"
  end
end
