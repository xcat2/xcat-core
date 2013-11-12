require_relative "spec_helper"

describe "openstack-block-storage::cinder-common" do
  before { block_storage_stubs }
  before do
    @chef_run = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS do |n|
      n.set["openstack"]["mq"] = {
        "host" => "127.0.0.1"
      }
      n.set["openstack"]["block-storage"]["syslog"]["use"] = true
    end
    @chef_run.converge "openstack-block-storage::cinder-common"
  end

  it "installs the cinder-common package" do
    expect(@chef_run).to upgrade_package "cinder-common"
  end

  describe "/etc/cinder" do
    before do
     @dir = @chef_run.directory "/etc/cinder"
    end

    it "has proper owner" do
      expect(@dir).to be_owned_by "cinder", "cinder"
    end

    it "has proper modes" do
     expect(sprintf("%o", @dir.mode)).to eq "750"
    end
  end

  describe "cinder.conf" do
    before do
     @file = @chef_run.template "/etc/cinder/cinder.conf"
    end

    it "has proper owner" do
      expect(@file).to be_owned_by "cinder", "cinder"
    end

    it "has proper modes" do
     expect(sprintf("%o", @file.mode)).to eq "644"
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

    it "has rabbit_userid" do
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

    describe "rabbit ha" do
      before do
        @chef_run = ::ChefSpec::ChefRunner.new(::UBUNTU_OPTS) do |n|
          n.set["openstack"]["block-storage"]["rabbit"]["ha"] = true
        end
        @chef_run.converge "openstack-block-storage::cinder-common"
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
  end
end
