require "chefspec"

::LOG_LEVEL = :fatal
::FEDORA_OPTS = {
  :platform => "fedora",
  :version => "18",
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
::OPENSUSE_OPTS = {
  :platform => "opensuse",
  :version => "12.3",
  :log_level => ::LOG_LEVEL
}

def dashboard_stubs
  ::Chef::Recipe.any_instance.stub(:memcached_servers).
    and_return ["hostA:port", "hostB:port"]
  ::Chef::Recipe.any_instance.stub(:db_password).with("horizon").
    and_return "test-pass"
end
