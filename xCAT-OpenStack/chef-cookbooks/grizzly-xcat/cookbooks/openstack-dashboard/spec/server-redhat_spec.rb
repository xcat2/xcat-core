require_relative "spec_helper"

describe "openstack-dashboard::server" do
  before { dashboard_stubs }

  describe "redhat" do
    before do
      @chef_run = ::ChefSpec::ChefRunner.new ::REDHAT_OPTS
      @chef_run.converge "openstack-dashboard::server"
    end

    it "executes set-selinux-permissive" do
      opts = ::REDHAT_OPTS.merge(:evaluate_guards => true)
      chef_run = ::ChefSpec::ChefRunner.new opts
      chef_run.stub_command(/.*/, true)
      chef_run.converge "openstack-dashboard::server"
      cmd = "/sbin/setenforce Permissive"

      expect(chef_run).to execute_command cmd
    end

    it "installs packages" do
      expect(@chef_run).to upgrade_package "openstack-dashboard"
      expect(@chef_run).to upgrade_package "MySQL-python"
    end

    it "executes set-selinux-enforcing" do
      opts = ::REDHAT_OPTS.merge(:evaluate_guards => true)
      chef_run = ::ChefSpec::ChefRunner.new opts
      chef_run.stub_command(/.*/, true)
      chef_run.converge "openstack-dashboard::server"
      cmd = "/sbin/setenforce Enforcing ; restorecon -R /etc/httpd"

      expect(chef_run).to execute_command cmd
    end

    describe "local_settings" do
      before do
        @file = @chef_run.template "/etc/openstack-dashboard/local_settings"
      end

      it "has proper owner" do
        expect(@file).to be_owned_by "root", "root"
      end

      it "has proper modes" do
        expect(sprintf("%o", @file.mode)).to eq "644"
      end

      it "rh specific template" do
        expect(@chef_run).to create_file_with_content @file.name, "WEBROOT"
      end
    end

    describe "certs" do
      before do
        @crt = @chef_run.cookbook_file "/etc/pki/tls/certs/horizon.pem"
        @key = @chef_run.cookbook_file "/etc/pki/tls/private/horizon.key"
      end

      it "has proper owner" do
        expect(@crt).to be_owned_by "root", "root"
        expect(@key).to be_owned_by "root", "root"
      end

      it "has proper modes" do
        expect(sprintf("%o", @crt.mode)).to eq "644"
        expect(sprintf("%o", @key.mode)).to eq "640"
      end

      it "notifies restore-selinux-context" do
        expect(@crt).to notify "execute[restore-selinux-context]", :run
        expect(@key).to notify "execute[restore-selinux-context]", :run
      end
    end

    describe "openstack-dashboard virtual host" do
      before do
        f = "/etc/httpd/conf.d/openstack-dashboard"
        @file = @chef_run.template f
      end

      it "has proper owner" do
        expect(@file).to be_owned_by "root", "root"
      end

      it "has proper modes" do
        expect(sprintf("%o", @file.mode)).to eq "644"
      end

      it "sets the ServerName directive " do
        chef_run = ::ChefSpec::ChefRunner.new ::REDHAT_OPTS do |n|
          n.set["openstack"]["dashboard"]["server_hostname"] = "spec-test-host"
        end
        chef_run.converge "openstack-dashboard::server"

        expect(chef_run).to create_file_with_content @file.name, "spec-test-host"
      end

      it "notifies restore-selinux-context" do
        expect(@file).to notify "execute[restore-selinux-context]", :run
      end
    end

    it "deletes openstack-dashboard.conf" do
      opts = ::REDHAT_OPTS.merge(:evaluate_guards => true)
      chef_run = ::ChefSpec::ChefRunner.new opts
      chef_run.stub_command(/.*/, true)
      chef_run.converge "openstack-dashboard::server"
      file = "/etc/httpd/conf.d/openstack-dashboard.conf"

      expect(chef_run).to delete_file file
    end

    it "does not remove openstack-dashboard-ubuntu-theme package" do
      opts = ::REDHAT_OPTS.merge(:evaluate_guards => true)
      chef_run = ::ChefSpec::ChefRunner.new opts
      chef_run.stub_command(/.*/, false)
      chef_run.converge "openstack-dashboard::server"

      expect(chef_run).not_to purge_package "openstack-dashboard-ubuntu-theme"
    end

    it "doesn't remove default apache site" do
      pending "TODO: how to properly test this"
    end

    it "doesn't execute restore-selinux-context" do
      opts = ::REDHAT_OPTS.merge(:evaluate_guards => true)
      chef_run = ::ChefSpec::ChefRunner.new opts
      chef_run.stub_command(/.*/, false)
      chef_run.converge "openstack-dashboard::server"
      cmd = "restorecon -Rv /etc/httpd /etc/pki; chcon -R -t httpd_sys_content_t /usr/share/openstack-dashboard || :"

      expect(chef_run).not_to execute_command cmd
    end
  end
end
