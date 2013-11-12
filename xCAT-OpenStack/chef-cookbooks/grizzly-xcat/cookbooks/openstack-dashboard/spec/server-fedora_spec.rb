require_relative "spec_helper"

describe "openstack-dashboard::server" do
  before { dashboard_stubs }

  describe "fedora" do
    before do
      @chef_run = ::ChefSpec::ChefRunner.new ::FEDORA_OPTS
      @chef_run.converge "openstack-dashboard::server"
    end

    it "deletes openstack-dashboard.conf" do
      opts = ::FEDORA_OPTS.merge(:evaluate_guards => true)
      chef_run = ::ChefSpec::ChefRunner.new opts
      chef_run.stub_command(/.*/, true)
      chef_run.converge "openstack-dashboard::server"
      file = "/etc/httpd/conf.d/openstack-dashboard.conf"

      expect(chef_run).to delete_file file
    end

    it "doesn't remove the default ubuntu virtualhost" do
      resource = @chef_run.find_resource(
        "execute",
        "a2dissite 000-default"
      )

      expect(resource).to be_nil
    end

    it "removes default virtualhost" do
      resource = @chef_run.find_resource(
        "execute",
        "a2dissite default"
      ).to_hash

      expect(resource[:params]).to include(
        :enable => false
      )
    end

    it "notifies restore-selinux-context" do
      pending "TODO: how to test this occured on apache_site 'default'"
    end

    it "executes restore-selinux-context" do
      opts = ::FEDORA_OPTS.merge(:evaluate_guards => true)
      chef_run = ::ChefSpec::ChefRunner.new opts
      chef_run.stub_command(/.*/, true)
      chef_run.converge "openstack-dashboard::server"
      cmd = "restorecon -Rv /etc/httpd /etc/pki; chcon -R -t httpd_sys_content_t /usr/share/openstack-dashboard || :"

      expect(chef_run).to execute_command cmd
    end
  end
end
