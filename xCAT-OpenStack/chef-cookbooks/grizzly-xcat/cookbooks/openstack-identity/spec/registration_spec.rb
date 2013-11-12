require_relative "spec_helper"

describe "openstack-identity::registration" do
  before { identity_stubs }

  describe "ubuntu" do
    let(:chef_run) {
      runner = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS
      runner.converge "openstack-identity::registration"
    }

    let(:chef_run_test_users) {
      runner = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS
      runner.node.set["openstack"]["identity"]["users"] = {
        "user1" => {
          "default_tenant" => "default_tenant1",
          "password" => "secret1",
          "roles" => {
            "role1" => [ "role_tenant1" ],
            "role2" => [ "default_tenant1" ]
          }
        },
      }
      runner.converge "openstack-identity::registration"
    }

    describe "tenant registration" do
      context "default tenants" do
        ["admin", "service"].each do |tenant_name|
          it "registers the #{tenant_name} tenant" do
            resource = chef_run.find_resource(
              "openstack-identity_register",
              "Register '#{tenant_name}' Tenant"
              ).to_hash

            expect(resource).to include(
              :auth_uri => "https://127.0.0.1:35357/v2.0",
              :bootstrap_token => "bootstrap-token",
              :tenant_name => tenant_name,
              :tenant_description => "#{tenant_name} Tenant",
              :action => [:create_tenant]
              )
          end
        end
      end

      context "configured tenants from users attribute" do
        tenants = ["default_tenant1", "role_tenant1"]

        tenants.each do |tenant_name|
          it "registers the #{tenant_name} tenant" do
            resource = chef_run_test_users.find_resource(
              "openstack-identity_register",
              "Register '#{tenant_name}' Tenant"
              ).to_hash

            expect(resource).to include(
              :auth_uri => "https://127.0.0.1:35357/v2.0",
              :bootstrap_token => "bootstrap-token",
              :tenant_name => tenant_name,
              :tenant_description => "#{tenant_name} Tenant",
              :action => [:create_tenant]
              )
          end
        end
      end
    end

    describe "role registration" do
      context "default roles" do
        ["admin", "Member", "KeystoneAdmin", "KeystoneServiceAdmin"
        ].each do |role_name|
          it "registers the #{role_name} role" do
            resource = chef_run.find_resource(
              "openstack-identity_register",
              "Register '#{role_name}' Role"
              ).to_hash

            expect(resource).to include(
              :auth_uri => "https://127.0.0.1:35357/v2.0",
              :bootstrap_token => "bootstrap-token",
              :role_name => role_name,
              :action => [:create_role]
              )
          end
        end
      end

      context "configured roles derived from users attribute" do

        roles = ["role1", "role2"]

        roles.each do |role_name|
          it "registers the #{role_name} role" do
            resource = chef_run_test_users.find_resource(
              "openstack-identity_register",
              "Register '#{role_name}' Role"
              ).to_hash

            expect(resource).to include(
              :auth_uri => "https://127.0.0.1:35357/v2.0",
              :bootstrap_token => "bootstrap-token",
              :role_name => role_name,
              :action => [:create_role]
              )
          end
        end
      end
    end

    describe "user registration" do
      context "default users" do
        [
          ["admin", "admin", ["admin", "KeystoneAdmin", "KeystoneServiceAdmin"]],
          ["monitoring", "service", ["Member"]]
        ].each do |user, tenant, roles|
          context "#{user} user" do
            it "registers the #{user} user" do
              user_resource = chef_run.find_resource(
                "openstack-identity_register",
                "Register '#{user}' User"
                ).to_hash

              expect(user_resource).to include(
                :auth_uri => "https://127.0.0.1:35357/v2.0",
                :bootstrap_token => "bootstrap-token",
                :user_name => user,
                :user_pass => nil,
                :tenant_name => tenant,
                :action => [:create_user]
                )
            end

            roles.each do |role|
              it "grants '#{role}' role to '#{user}' user in 'admin' tenant" do
                grant_resource = chef_run.find_resource(
                  "openstack-identity_register",
                  "Grant '#{role}' Role to '#{user}' User in 'admin' Tenant"
                  ).to_hash

                expect(grant_resource).to include(
                  :auth_uri => "https://127.0.0.1:35357/v2.0",
                  :bootstrap_token => "bootstrap-token",
                  :user_name => user,
                  :role_name => role,
                  :tenant_name => "admin",
                  :action => [:grant_role]
                  )
              end
            end
          end
        end
      end

      context "configured user" do
        it "registers the user1 user" do
          resource = chef_run_test_users.find_resource(
            "openstack-identity_register",
            "Register 'user1' User"
            ).to_hash

          expect(resource).to include(
            :auth_uri => "https://127.0.0.1:35357/v2.0",
            :bootstrap_token => "bootstrap-token",
            :user_name => "user1",
            :user_pass => "secret1",
            :tenant_name => "default_tenant1",
            :action => [:create_user]
            )
        end

        it "grants 'role1' role to 'user1' user in 'role_tenant1' tenant" do
          grant_resource = chef_run_test_users.find_resource(
            "openstack-identity_register",
            "Grant 'role1' Role to 'user1' User in 'role_tenant1' Tenant"
            ).to_hash

          expect(grant_resource).to include(
            :auth_uri => "https://127.0.0.1:35357/v2.0",
            :bootstrap_token => "bootstrap-token",
            :user_name => "user1",
            :role_name => "role1",
            :tenant_name => "role_tenant1",
            :action => [:grant_role]
            )
        end
      end
    end
  end
end
