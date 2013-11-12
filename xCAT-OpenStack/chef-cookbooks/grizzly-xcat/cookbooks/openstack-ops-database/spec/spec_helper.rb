require "chefspec"

::LOG_LEVEL = :fatal
::OPENSUSE_OPTS = {
  :platform  => "opensuse",
  :version   => "12.3",
  :log_level => ::LOG_LEVEL
}
::REDHAT_OPTS = {
  :platform  => "redhat",
  :version => "6.3",
  :log_level => ::LOG_LEVEL
}
::UBUNTU_OPTS = {
  :platform  => "ubuntu",
  :version   => "12.04",
  :log_level => ::LOG_LEVEL
}

def ops_database_stubs
  ::Chef::Recipe.any_instance.stub(:address_for).
    with("lo").
    and_return "127.0.0.1"
end
