require_relative 'spec_helper'

describe "openstack-ops-messaging::server" do
  before { ops_messaging_stubs }
  describe "ubuntu" do

    it "uses proper messaging server recipe" do
      chef_run = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS
      chef_run.converge "openstack-ops-messaging::server"

      expect(chef_run).to include_recipe "openstack-ops-messaging::rabbitmq-server"
    end
  end
end
