require_relative "spec_helper"

describe "openstack-common::logging" do
  describe "ubuntu" do
    before do
      @chef_run = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS
      @chef_run.converge "openstack-common::logging"
    end

    describe "/etc/openstack" do
      before do
        @dir = @chef_run.directory "/etc/openstack"
      end

      it "has proper owner" do
        expect(@dir).to be_owned_by "root", "root"
      end

      it "has proper modes" do
        expect(sprintf("%o", @dir.mode)).to eq "755"
      end
    end

    describe "logging.conf" do
      before do
        @file = "/etc/openstack/logging.conf"
      end

      it "has proper owner" do
        expect(@chef_run.template(@file)).to be_owned_by "root", "root"
      end

      it "has proper modes" do
        m = @chef_run.template(@file).mode
        expect(sprintf("%o", m)).to eq "644"
      end

      it "templates openstack.logging.ignore block" do
        chef_run = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS
        chef_run.converge "openstack-common::logging"
        node = chef_run.node
        node.set["openstack"]["logging"]["ignore"] = {
          "test.nova.api.openstack.wsgi" => "WARNING"
        }

        tmp = [
          "[logger_test_nova_api_openstack_wsgi]",
          "level = WARNING",
          "handlers = prod,debug",
          "qualname = test.nova.api.openstack.wsgi"
        ]
        expect(chef_run).to create_file_with_content @file, tmp.join("\n")
      end
    end
  end
end
