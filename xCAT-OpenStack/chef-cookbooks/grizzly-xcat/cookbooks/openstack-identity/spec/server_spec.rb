require_relative "spec_helper"

describe "openstack-identity::server" do
  before { identity_stubs }
  describe "ubuntu" do
    before do
      @chef_run = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS do |n|
        n.set["openstack"]["identity"]["syslog"]["use"] = true
        n.set["openstack"]["endpoints"]["identity-api"] = {
          "host" => "127.0.1.1",
          "port" => "5000",
          "scheme" => "https"
        }
        n.set["openstack"]["endpoints"]["identity-admin"] = {
          "host" => "127.0.1.1",
          "port" => "35357",
          "scheme" => "https"
        }
      end
      @chef_run.converge "openstack-identity::server"
    end

    it "runs logging recipe if node attributes say to" do
      expect(@chef_run).to include_recipe "openstack-common::logging"
    end

    it "doesn't run logging recipe" do
      chef_run = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS
      chef_run.converge "openstack-identity::server"

      expect(chef_run).not_to include_recipe "openstack-common::logging"
    end

    it "installs mysql python packages" do
      expect(@chef_run).to install_package "python-mysqldb"
    end

    it "installs postgresql python packages if explicitly told" do
      chef_run = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS
      node = chef_run.node
      node.set["openstack"]["db"]["identity"]["db_type"] = "postgresql"
      chef_run.converge "openstack-identity::server"

      expect(chef_run).to install_package "python-psycopg2"
    end

    it "installs memcache python packages" do
      expect(@chef_run).to install_package "python-memcache"
    end

    it "installs keystone packages" do
      expect(@chef_run).to upgrade_package "keystone"
    end

    it "starts keystone on boot" do
      expect(@chef_run).to set_service_to_start_on_boot "keystone"
    end

    it "sleep on keystone service enable" do
      expect(@chef_run.service("keystone")).
        to notify "execute[Keystone: sleep]", :run
    end

    describe "/etc/keystone" do
      before do
        @dir = @chef_run.directory "/etc/keystone"
      end

      it "has proper owner" do
        expect(@dir).to be_owned_by "keystone", "keystone"
      end

      it "has proper modes" do
        expect(sprintf("%o", @dir.mode)).to eq "700"
      end
    end

    describe "/etc/keystone/ssl" do
      before { @dir = "/etc/keystone/ssl" }

      describe "without pki" do
        it "doesn't create" do
          opts = ::UBUNTU_OPTS.merge(:evaluate_guards => true)
          chef_run = ::ChefSpec::ChefRunner.new opts
          chef_run.converge "openstack-identity::server"

          expect(chef_run).not_to create_directory @dir
        end
      end

      describe "with pki" do
        before do
          opts = ::UBUNTU_OPTS.merge(:evaluate_guards => true)
          @chef_run = ::ChefSpec::ChefRunner.new opts do |n|
            n.set["openstack"]["auth"]["strategy"] = "pki"
          end
          @chef_run.converge "openstack-identity::server"
          @directory = @chef_run.directory @dir
        end

        it "creates" do
          expect(@chef_run).to create_directory @directory.name
        end

        it "has proper owner" do
          expect(@directory).to be_owned_by "keystone", "keystone"
        end

        it "has proper modes" do
          expect(sprintf("%o", @directory.mode)).to eq "700"
        end
      end
    end

    it "deletes keystone.db" do
      expect(@chef_run).to delete_file "/var/lib/keystone/keystone.db"
    end

    describe "pki setup" do
      before { @cmd = "keystone-manage pki_setup" }

      describe "without pki" do
        it "doesn't execute" do
          opts = ::UBUNTU_OPTS.merge(:evaluate_guards => true)
          chef_run = ::ChefSpec::ChefRunner.new opts

          expect(chef_run).not_to execute_command(@cmd).with(
            :user => "keystone"
          )
        end
      end

      describe "with pki" do
        before do
          opts = ::UBUNTU_OPTS.merge(:evaluate_guards => true)
          @chef_run = ::ChefSpec::ChefRunner.new opts do |n|
            n.set["openstack"]["auth"]["strategy"] = "pki"
          end
        end

        it "executes" do
          ::FileTest.should_receive(:exists?).
            with("/etc/keystone/ssl/private/signing_key.pem").
            and_return(false)
          @chef_run.converge "openstack-identity::server"

          expect(@chef_run).to execute_command(@cmd).with(
            :user => "keystone"
          )
        end

        it "doesn't execute when dir exists" do
          ::FileTest.should_receive(:exists?).
            with("/etc/keystone/ssl/private/signing_key.pem").
            and_return(true)
          @chef_run.converge "openstack-identity::server"

          expect(@chef_run).not_to execute_command(@cmd).with(
            :user => "keystone"
          )
        end
      end
    end

    describe "keystone.conf" do
      before do
        @template = @chef_run.template "/etc/keystone/keystone.conf"
      end

      it "has proper owner" do
        expect(@template).to be_owned_by "keystone", "keystone"
      end

      it "has proper modes" do
        expect(sprintf("%o", @template.mode)).to eq "644"
      end

      it "has bind host" do
        expect(@chef_run).to create_file_with_content @template.name,
          "bind_host = 127.0.1.1"
      end

      it "has proper public and admin endpoint" do
        expect(@chef_run).to create_file_with_content @template.name,
          "public_endpoint = https://127.0.1.1:5000/"
        expect(@chef_run).to create_file_with_content @template.name,
          "admin_endpoint = https://127.0.1.1:35357/"
      end

      it "notifies keystone restart" do
        expect(@template).to notify "service[keystone]", :restart
      end

      describe "optional LDAP attributes" do
        optional_attrs = ["group_tree_dn", "group_filter",
          "user_filter", "user_tree_dn", "user_enabled_emulation_dn",
          "group_attribute_ignore", "role_attribute_ignore",
          "role_tree_dn", "role_filter", "tenant_tree_dn",
          "tenant_enabled_emulation_dn", "tenant_filter",
          "tenant_attribute_ignore"]

        optional_attrs.each do |setting|
          it "does not have the optional #{setting} LDAP attribute" do
            expect(@chef_run).not_to(
              create_file_with_content(
                @template.name, /^#{Regexp.quote(setting)} =/))
          end

          it "has the optional #{setting} LDAP attribute commented out" do
            expect(@chef_run).to(
              create_file_with_content(
                @template.name, /^# #{Regexp.quote(setting)} =$/))
          end
        end
      end

      ["url", "user", "suffix", "use_dumb_member",
        "allow_subtree_delete", "dumb_member", "page_size",
        "alias_dereferencing", "query_scope", "user_objectclass",
        "user_id_attribute", "user_name_attribute",
        "user_mail_attribute", "user_pass_attribute",
        "user_enabled_attribute", "user_domain_id_attribute",
        "user_attribute_ignore", "user_enabled_mask",
        "user_enabled_default", "user_allow_create",
        "user_allow_update", "user_allow_delete",
        "user_enabled_emulation", "tenant_objectclass",
        "tenant_id_attribute", "tenant_member_attribute",
        "tenant_name_attribute", "tenant_desc_attribute",
        "tenant_enabled_attribute", "tenant_domain_id_attribute",
        "tenant_allow_create", "tenant_allow_update",
        "tenant_allow_delete", "tenant_enabled_emulation",
        "role_objectclass", "role_id_attribute", "role_name_attribute",
        "role_member_attribute", "role_allow_create",
        "role_allow_update", "role_allow_delete", "group_objectclass",
        "group_id_attribute", "group_name_attribute",
        "group_member_attribute", "group_desc_attribute",
        "group_domain_id_attribute", "group_allow_create",
        "group_allow_update", "group_allow_delete",
      ].each do |setting|
        it "has a #{setting} LDAP attribute" do
          expect(@chef_run).to create_file_with_content @template.name,
          /^#{Regexp.quote(setting)} = \w+/
        end
      end
    end

    describe "default_catalog.templates" do
      before { @file = "/etc/keystone/default_catalog.templates" }

      describe "without templated" do
        it "doesn't create" do
          opts = ::UBUNTU_OPTS.merge(:evaluate_guards => true)
          chef_run = ::ChefSpec::ChefRunner.new opts
          chef_run.converge "openstack-identity::server"

          expect(chef_run).not_to create_file @file
        end
      end

      describe "with templated" do
        before do
          opts = ::UBUNTU_OPTS.merge(:evaluate_guards => true)
          @chef_run = ::ChefSpec::ChefRunner.new opts do |n|
            n.set["openstack"]["identity"]["catalog"]["backend"] = "templated"
          end
          @chef_run.converge "openstack-identity::server"
          @template = @chef_run.template @file
        end

        it "creates" do
          expect(@chef_run).to create_file @file
        end

        it "has proper owner" do
          expect(@template).to be_owned_by "keystone", "keystone"
        end

        it "has proper modes" do
          expect(sprintf("%o", @template.mode)).to eq "644"
        end

        it "template contents" do
          pending "TODO: implement"
        end

        it "notifies keystone restart" do
          expect(@template).to notify "service[keystone]", :restart
        end
      end
    end

    describe "db_sync" do
      before do
        @cmd = "keystone-manage db_sync"
      end

      it "runs migrations" do
        expect(@chef_run).to execute_command @cmd
      end

      it "doesn't run migrations" do
        opts = ::UBUNTU_OPTS.merge(:evaluate_guards => true)
        chef_run = ::ChefSpec::ChefRunner.new(opts) do |n|
          n.set["openstack"]["identity"]["db"]["migrate"] = false
        end
        chef_run.converge "openstack-identity::server"

        expect(chef_run).not_to execute_command @cmd
      end
    end
  end
end
