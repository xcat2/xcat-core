require "chefspec"

::LOG_LEVEL = :fatal
::OPENSUSE_OPTS = {
  :platform => "opensuse",
  :version => "12.3",
  :log_level => ::LOG_LEVEL
}
::REDHAT_OPTS = {
  :platform => "redhat",
  :version => "6.3",
  :log_level => ::LOG_LEVEL
}
::UBUNTU_OPTS = {
  :platform => "ubuntu",
  :version => "12.04",
  :log_level => ::LOG_LEVEL
}

def metering_stubs
  ::Chef::Recipe.any_instance.stub(:memcached_servers).and_return []
  ::Chef::Recipe.any_instance.stub(:service_password).and_return String.new
  ::Chef::Recipe.any_instance.stub(:db_password).and_return String.new
  ::Chef::Recipe.any_instance.stub(:user_password).and_return String.new
  ::Chef::Recipe.any_instance.stub(:user_password).
    with("guest").
    and_return "rabbit-pass"
  ::Chef::Recipe.any_instance.stub(:secret).
    with("secrets", "openstack_identity_bootstrap_token").
    and_return "bootstrap-token"
end

def expect_runs_common_recipe
  it "runs common recipe" do
    expect(@chef_run).to include_recipe "openstack-metering::common"
  end
end
