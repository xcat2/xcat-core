require_relative "spec_helper"

describe "openstack-ops-database::openstack-db" do
  before do
    ::Chef::Recipe.any_instance.stub(:db_create_with_user)
    ::Chef::Recipe.any_instance.stub(:db_password).
      and_return("test-pass")
    @chef_run = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS
  end

  it "creates nova database and user" do
    ::Chef::Recipe.any_instance.should_receive(:db_create_with_user).
      with "dashboard", "dash", "test-pass"

    @chef_run.converge "openstack-ops-database::openstack-db"
  end

  it "creates dashboard database and user" do
    ::Chef::Recipe.any_instance.should_receive(:db_create_with_user).
      with "dashboard", "dash", "test-pass"

    @chef_run.converge "openstack-ops-database::openstack-db"
  end

  it "creates identity database and user" do
    ::Chef::Recipe.any_instance.should_receive(:db_create_with_user).
      with "identity", "keystone", "test-pass"

    @chef_run.converge "openstack-ops-database::openstack-db"
  end

  it "creates image database and user" do
    ::Chef::Recipe.any_instance.should_receive(:db_create_with_user).
      with "image", "glance", "test-pass"

    @chef_run.converge "openstack-ops-database::openstack-db"
  end

  it "creates metering database and user" do
    ::Chef::Recipe.any_instance.should_receive(:db_create_with_user).
      with "metering", "ceilometer", "test-pass"

    @chef_run.converge "openstack-ops-database::openstack-db"
  end

  it "creates network database and user" do
    ::Chef::Recipe.any_instance.should_receive(:db_create_with_user).
      with "network", "quantum", "test-pass"

    @chef_run.converge "openstack-ops-database::openstack-db"
  end

  it "creates volume database and user" do
    ::Chef::Recipe.any_instance.should_receive(:db_create_with_user).
      with "volume", "cinder", "test-pass"

    @chef_run.converge "openstack-ops-database::openstack-db"
  end
end
