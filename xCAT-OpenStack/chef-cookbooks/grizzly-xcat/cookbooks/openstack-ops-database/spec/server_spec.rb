require_relative "spec_helper"

describe "openstack-ops-database::server" do
  before { ops_database_stubs }
  describe "ubuntu" do

    it "uses mysql database server recipe by default" do
      chef_run = ::ChefSpec::ChefRunner.new(::UBUNTU_OPTS) do |n|
        n.set["mysql"] = {
          "server_debian_password" => "server-debian-password",
          "server_root_password" => "server-root-password",
          "server_repl_password" => "server-repl-password"
        }
      end
      chef_run.converge "openstack-ops-database::server"

      expect(chef_run).to include_recipe "openstack-ops-database::mysql-server"
    end

    it "uses postgresql database server recipe when configured" do
      chef_run = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS do |n|
        n.set["openstack"]["db"]["service_type"] = "postgresql"
        # The postgresql cookbook will raise an "uninitialized constant
        # Chef::Application" error without this attribute when running
        # the tests
        n.set["postgresql"]["password"]["postgres"] = String.new
      end

      chef_run.converge "openstack-ops-database::server"

      expect(chef_run).to include_recipe "openstack-ops-database::postgresql-server"
    end
  end
end
