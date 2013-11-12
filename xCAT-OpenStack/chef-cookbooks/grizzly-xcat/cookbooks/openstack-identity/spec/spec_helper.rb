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

def identity_stubs
  ::Chef::Recipe.any_instance.stub(:address_for).
    with("lo").
    and_return "127.0.1.1"
  ::Chef::Recipe.any_instance.stub(:memcached_servers).and_return []
  ::Chef::Recipe.any_instance.stub(:db_password).and_return String.new
  ::Chef::Recipe.any_instance.stub(:user_password).and_return String.new
  ::Chef::Recipe.any_instance.stub(:secret).
    with("secrets", "openstack_identity_bootstrap_token").
    and_return "bootstrap-token"
end
