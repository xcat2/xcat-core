require_relative "spec_helper"

describe "openstack-compute::nova-common" do
  before { compute_stubs }
  describe "ubuntu" do
    before do
      @chef_run = ::ChefSpec::ChefRunner.new(::UBUNTU_OPTS) do |n|
        n.set["openstack"]["mq"] = {
          "host" => "127.0.0.1"
        }
        n.set["openstack"]["compute"]["syslog"]["use"] = true
      end
      @chef_run.converge "openstack-compute::nova-common"
    end

    it "doesn't run epel recipe" do
      expect(@chef_run).to_not include_recipe 'yum::epel'
    end

    it "runs logging recipe if node attributes say to" do
      expect(@chef_run).to include_recipe "openstack-common::logging"
    end

    it "doesn't run logging recipe" do
      chef_run = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS
      chef_run.converge "openstack-compute::nova-common"
      expect(chef_run).not_to include_recipe "openstack-common::logging"
    end

    it "can converge with quantum service type" do
      chef_run = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS
      node = chef_run.node
      node.set["openstack"]["compute"]["network"]["service_type"] = "quantum"
      chef_run.converge "openstack-compute::nova-common"
    end

    it "installs nova common packages" do
      expect(@chef_run).to upgrade_package "nova-common"
    end

    it "installs memcache python packages" do
      expect(@chef_run).to install_package "python-memcache"
    end

    describe "/etc/nova" do
      before do
        @dir = @chef_run.directory "/etc/nova"
      end

      it "has proper owner" do
        expect(@dir).to be_owned_by "nova", "nova"
      end

      it "has proper modes" do
        expect(sprintf("%o", @dir.mode)).to eq "700"
      end
    end

    describe "/etc/nova/rootwrap.d" do
      before do
        @dir = @chef_run.directory "/etc/nova/rootwrap.d"
      end

      it "has proper owner" do
        expect(@dir).to be_owned_by "root", "root"
      end

      it "has proper modes" do
        expect(sprintf("%o", @dir.mode)).to eq "700"
      end
    end

    describe "nova.conf" do
      before do
        @file = @chef_run.template "/etc/nova/nova.conf"
        # README(shep) need this to evaluate nova.conf.erb template
        @chef_run.node.set['cpu'] = Hash.new()
        @chef_run.node.set.cpu.total = "2"
      end

      it "has proper owner" do
        expect(@file).to be_owned_by "nova", "nova"
      end

      it "has proper modes" do
        expect(sprintf("%o", @file.mode)).to eq "644"
      end

      it "has rabbit_user" do
        expect(@chef_run).to create_file_with_content @file.name,
          "rabbit_userid=guest"
      end

      it "has rabbit_password" do
        expect(@chef_run).to create_file_with_content @file.name,
          "rabbit_password=rabbit-pass"
      end

      it "has rabbit_virtual_host" do
        expect(@chef_run).to create_file_with_content @file.name,
          "rabbit_virtual_host=/"
      end

      it "has rabbit_host" do
        expect(@chef_run).to create_file_with_content @file.name,
          "rabbit_host=127.0.0.1"
      end

      it "does not have rabbit_hosts" do
        expect(@chef_run).not_to create_file_with_content @file.name,
          "rabbit_hosts="
      end

      it "does not have rabbit_ha_queues" do
        expect(@chef_run).not_to create_file_with_content @file.name,
          "rabbit_ha_queues="
      end

      it "has rabbit_port" do
        expect(@chef_run).to create_file_with_content @file.name,
          "rabbit_port=5672"
      end

      describe "rabbit ha" do
        before do
          @chef_run = ::ChefSpec::ChefRunner.new(::UBUNTU_OPTS) do |n|
            n.set["openstack"]["compute"]["rabbit"]["ha"] = true
            n.set["cpu"] = {
              "total" => "2"
            }
          end
          @chef_run.converge "openstack-compute::nova-common"
        end

        it "has rabbit_hosts" do
          expect(@chef_run).to create_file_with_content @file.name,
            "rabbit_hosts=1.1.1.1:5672,2.2.2.2:5672"
        end

        it "has rabbit_ha_queues" do
          expect(@chef_run).to create_file_with_content @file.name,
            "rabbit_ha_queues=True"
        end

        it "does not have rabbit_host" do
          expect(@chef_run).not_to create_file_with_content @file.name,
            "rabbit_host=127.0.0.1"
        end

        it "does not have rabbit_port" do
          expect(@chef_run).not_to create_file_with_content @file.name,
            "rabbit_port=5672"
        end
      end

      it "has vncserver_listen" do
        expect(@chef_run).to create_file_with_content @file.name,
          "vncserver_listen=127.0.1.1"
      end

      it "has vncserver_proxyclient_address" do
        expect(@chef_run).to create_file_with_content @file.name,
          "vncserver_proxyclient_address=127.0.1.1"
      end

      it "has xvpvncproxy_host" do
        expect(@chef_run).to create_file_with_content @file.name,
          "xvpvncproxy_host=127.0.1.1"
      end

      it "has novncproxy_host" do
        expect(@chef_run).to create_file_with_content @file.name,
          "novncproxy_host=127.0.1.1"
      end

      it "has correct force_dhcp_release value" do
        expect(@chef_run).to create_file_with_content @file.name,
          "force_dhcp_release=true"
      end

      it "has virtio enabled" do
        expect(@chef_run).to create_file_with_content @file.name,
          "libvirt_use_virtio_for_bridges=true"
      end

      it "does not have ec2_private_dns_show_ip option" do
        expect(@chef_run).to_not create_file_with_content @file.name,
          "ec2_private_dns_show_ip"
      end
    end


#    describe "identity role local node" do
#      before do
#        @chef_run = ::ChefSpec::ChefRunner.new(::UBUNTU_OPTS) do |n|
#          n.set["openstack"]["identity"]["admin_tenant_name"] = "admin-tenant"
#          n.set["openstack"]["identity"]["admin_user"] = "admin-user"
#        end
#        @chef_run.converge 'role[os-identity]', "openstack-compute::nova-common"
#      end
#      it "has keystone_hash" do
#        expect(@chef_run).to log 'openstack-compute::nova-common:keystone|node[???]'
#      end
#      it "has ksadmin_user" do
#        expect(@chef_run).to log 'openstack-compute::nova-common:ksadmin_user|admin-user'
#      end
#      it "has ksadmin_tenant_name" do
#        expect(@chef_run).to log 'openstack-compute::nova-common:ksadmin_tenant_name|admin-tenant'
#      end
#    end


#    describe "identity role search" do
#      before do
#        @chef_run = ::ChefSpec::ChefRunner.new(::UBUNTU_OPTS) do |n|
#          n.set["openstack"]["compute"]["identity_service_chef_role"] = "os-identity"
#        end
#        @chef_run.converge "openstack-compute::nova-common"
#      end
#      it "has keystone_hash" do
#        expect(@chef_run).to log 'openstack-compute::nova-common:keystone|node[???]'
#      end
#      it "has ksadmin_user" do
#        expect(@chef_run).to log 'openstack-compute::nova-common:ksadmin_user|admin-user'
#      end
#      it "has ksadmin_tenant_name" do
#        expect(@chef_run).to log 'openstack-compute::nova-common:ksadmin_tenant_name|admin-tenant'
#      end
#    end

    describe "rootwrap.conf" do
      before do
        @file = @chef_run.template "/etc/nova/rootwrap.conf"
      end

      it "has proper owner" do
        expect(@file).to be_owned_by "root", "root"
      end

      it "has proper modes" do
        expect(sprintf("%o", @file.mode)).to eq "644"
      end

      it "template contents" do
        pending "TODO: implement"
      end
    end

    describe "api-metadata.filters" do
      before do
        @file = @chef_run.template "/etc/nova/rootwrap.d/api-metadata.filters"
      end

      it "has proper owner" do
        expect(@file).to be_owned_by "root", "root"
      end

      it "has proper modes" do
        expect(sprintf("%o", @file.mode)).to eq "644"
      end

      it "template contents" do
        pending "TODO: implement"
      end
    end

    describe "compute.filters" do
      before do
        @file = @chef_run.template "/etc/nova/rootwrap.d/compute.filters"
      end

      it "has proper owner" do
        expect(@file).to be_owned_by "root", "root"
      end

      it "has proper modes" do
        expect(sprintf("%o", @file.mode)).to eq "644"
      end

      it "template contents" do
        pending "TODO: implement"
      end
    end

    describe "network.filters" do
      before do
        @file = @chef_run.template "/etc/nova/rootwrap.d/network.filters"
      end

      it "has proper owner" do
        expect(@file).to be_owned_by "root", "root"
      end

      it "has proper modes" do
        expect(sprintf("%o", @file.mode)).to eq "644"
      end

      it "template contents" do
        pending "TODO: implement"
      end
    end

    describe "openrc" do
      before do
        @file = @chef_run.template "/root/openrc"
      end

      it "has proper owner" do
        expect(@file).to be_owned_by "root", "root"
      end

      it "has proper modes" do
        expect(sprintf("%o", @file.mode)).to eq "600"
      end

      it "contains ksadmin_user" do
        expect(@chef_run).to create_file_with_content @file.name,
          "export OS_USERNAME=admin-user"
      end

      it "contains ksadmin_tenant_name" do
        expect(@chef_run).to create_file_with_content @file.name,
          "export OS_TENANT_NAME=admin-tenant"
      end

      it "contains ksadmin_pass" do
        expect(@chef_run).to create_file_with_content @file.name,
          "export OS_PASSWORD=admin-pass"
      end

      it "rest of template contents" do
        pending "TODO: implement"
      end
    end

    it "enables nova login" do
      cmd = "usermod -s /bin/sh nova"
      expect(@chef_run).to execute_command cmd
    end
  end
end
