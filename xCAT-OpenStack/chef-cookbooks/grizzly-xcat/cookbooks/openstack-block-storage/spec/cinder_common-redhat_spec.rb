require_relative "spec_helper"

describe "openstack-block-storage::cinder-common" do
  before { block_storage_stubs }
  before do
    @chef_run = ::ChefSpec::ChefRunner.new ::REDHAT_OPTS do |n|
      n.set["openstack"]["mq"] = {
        "host" => "127.0.0.1"
      }
      n.set["openstack"]["block-storage"]["syslog"]["use"] = true
    end
    @chef_run.converge "openstack-block-storage::cinder-common"
  end

  it "installs the openstack-cinder package" do
    expect(@chef_run).to upgrade_package "openstack-cinder"
  end
end
