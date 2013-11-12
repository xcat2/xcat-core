require "chefspec"

::LOG_LEVEL = :fatal
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

def ops_messaging_stubs
  ::Chef::Recipe.any_instance.stub(:address_for).
    with("lo").
    and_return "127.0.0.1"
  ::Chef::Recipe.any_instance.stub(:search).
    with(:node, "roles:os-ops-messaging AND chef_environment:_default").
    and_return [
      { 'hostname' => 'host2' },
      { 'hostname' => 'host1' }
    ]
  ::Chef::Recipe.any_instance.stub(:user_password).
    and_return "rabbit-pass"
  ::Chef::Recipe.any_instance.stub(:service_password).
    with("rabbit_cookie").
    and_return "erlang-cookie"
end
