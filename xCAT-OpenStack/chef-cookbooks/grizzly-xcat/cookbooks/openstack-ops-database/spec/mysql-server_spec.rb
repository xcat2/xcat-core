require_relative "spec_helper"

describe "openstack-ops-database::mysql-server" do
  before { ops_database_stubs }
  describe "ubuntu" do
    before do
      @chef_run = ::ChefSpec::ChefRunner.new(::UBUNTU_OPTS) do |n|
        n.set["mysql"] = {
          "server_debian_password" => "server-debian-password",
          "server_root_password" => "server-root-password",
          "server_repl_password" => "server-repl-password"
        }
      end
      @chef_run.converge "openstack-ops-database::mysql-server"
    end

    it "overrides default mysql attributes" do
      expect(@chef_run.node["mysql"]["bind_address"]).to eql "127.0.0.1"
      expect(@chef_run.node['mysql']['tunable']['innodb_thread_concurrency']).to eql "0"
      expect(@chef_run.node['mysql']['tunable']['innodb_commit_concurrency']).to eql "0"
      expect(@chef_run.node['mysql']['tunable']['innodb_read_io_threads']).to eql "4"
      expect(@chef_run.node['mysql']['tunable']['innodb_flush_log_at_trx_commit']).to eql "2"
    end

    it "includes mysql recipes" do
      expect(@chef_run).to include_recipe "openstack-ops-database::mysql-client"
      expect(@chef_run).to include_recipe "mysql::server"
    end

    describe "lwrps" do
      before do
        @connection = {
          :host => "localhost",
          :username => "root",
          :password => "server-root-password"
        }
      end

      it "removes insecure default localhost mysql users" do
        resource = @chef_run.find_resource(
          "mysql_database",
          "drop empty localhost user"
        ).to_hash

        expect(resource).to include(
          :sql => "DELETE FROM mysql.user WHERE User = '' OR Password = ''",
          :connection => @connection,
          :action => [:query]
        )
      end

      it "drops the test database" do
        resource = @chef_run.find_resource(
          "mysql_database",
          "test"
        ).to_hash

        expect(resource).to include(
          :connection => @connection,
          :action => [:drop]
        )
      end

      it "flushes privileges" do
        resource = @chef_run.find_resource(
          "mysql_database",
          "FLUSH PRIVILEGES"
        ).to_hash

        expect(resource).to include(
          :connection => @connection,
          :sql => "FLUSH PRIVILEGES",
          :action => [:query]
        )
      end
    end
  end
end
