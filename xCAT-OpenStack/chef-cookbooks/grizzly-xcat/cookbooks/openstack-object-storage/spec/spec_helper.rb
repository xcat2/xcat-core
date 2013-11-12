require "chefspec"

::LOG_LEVEL = :fatal
::REDHAT_OPTS = {
    :platform  => "redhat",
    :log_level => ::LOG_LEVEL
}
::UBUNTU_OPTS = {
    :platform  => "ubuntu",
    :version   => "12.04",
    :log_level => ::LOG_LEVEL
}

MOCK_NODE_NETWORK_DATA =
  {
    "ipaddress" => '10.0.0.2',
    "fqdn" => 'localhost.localdomain',
    "hostname" => 'localhost',
    "network" => {
      "default_interface" => "eth0",
      "interfaces" => {
        "eth0" => {
          "addresses" => {
            "fe80::a00:27ff:feca:ab08" => {"scope" => "Link", "prefixlen" => "64", "family" => "inet6"},
            "10.0.0.2" => {"netmask" => "255.255.255.0", "broadcast" => "10.0.0.255", "family" => "inet"},
            "08:00:27:CA:AB:08" => {"family" => "lladdr"}
          },
        },
        "lo" => {
          "addresses" => {
            "::1" => {"scope" => "Node", "prefixlen" => "128", "family" => "inet6"},
            "127.0.0.1" => {"netmask" => "255.0.0.0", "family" => "inet"}
          },
        },
      },
    }
  }

def swift_stubs
    # create mock cluster
    n = Chef::Node.new()
    n.name('manager')
    n.default_attrs = {
      "swift" => {
        "service_pass" => "foobar"
      }
   }
   Chef::Recipe.any_instance.stub(:search).with(:node, 'chef_environment:_default AND roles:swift-setup').and_return([n])
end
