require_relative "spec_helper"

describe "openstack-compute::nova-setup" do
  before { compute_stubs }
  describe "ubuntu" do
    before do
      @chef_run = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS
      @chef_run.converge "openstack-compute::nova-setup"
    end

    expect_runs_nova_common_recipe

    it "runs db migrations" do
      cmd = "nova-manage db sync"
      expect(@chef_run).to execute_command cmd
    end

    it "adds nova network ipv4 addresses" do
      cmd = ["nova-manage network create --label=public",
        "--fixed_range_v4=192.168.100.0/24",
        "--multi_host='T'",
        "--num_networks=1",
        "--network_size=255",
        "--bridge=br100",
        "--bridge_interface=eth2",
        "--dns1=8.8.8.8",
        "--dns2=8.8.4.4"].join(' ')
      expect(@chef_run).to execute_command cmd
    end

    it "add_floaters.py has proper modes" do
      file = @chef_run.cookbook_file "/usr/local/bin/add_floaters.py"
      expect(sprintf("%o", file.mode)).to eq "755"
    end

    it "adds cidr range of floating ipv4 addresses" do
      chef_run = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS
      node = chef_run.node
      node.set["openstack"]["compute"]["network"]["floating"]["ipv4_cidr"] = "10.10.10.0/24"
      chef_run.converge "openstack-compute::nova-setup"

      cmd = "/usr/local/bin/add_floaters.py nova --cidr=10.10.10.0/24"
      expect(chef_run).to execute_command cmd
    end

    it "adds range of floating ipv4 addresses" do
      chef_run = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS
      node = chef_run.node
      node.set["openstack"]["compute"]["network"] = {
        "floating" => {
          "ipv4_range" => "10.10.10.1,10.10.10.5"
        }
      }
      chef_run.converge "openstack-compute::nova-setup"

      cmd = "/usr/local/bin/add_floaters.py nova --ip-range=10.10.10.1,10.10.10.5"
      expect(chef_run).to execute_command cmd
    end

    it "adds cidr range of floating ipv4 addresses to neutron" do
      chef_run = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS
      node = chef_run.node
      node.set["openstack"]["compute"]["network"]["service_type"] = "neutron"
      node.set["openstack"]["compute"]["network"]["floating"]["ipv4_cidr"] = "10.10.10.0/24"
      node.set["openstack"]["compute"]["network"]["floating"]["public_network_name"] = "public"
      chef_run.converge "openstack-compute::nova-setup"
      cmd = ". /root/openrc && /usr/local/bin/add_floaters.py neutron --cidr=10.10.10.0/24 --pool=public"
      expect(chef_run).to execute_command cmd
    end
  end
end
