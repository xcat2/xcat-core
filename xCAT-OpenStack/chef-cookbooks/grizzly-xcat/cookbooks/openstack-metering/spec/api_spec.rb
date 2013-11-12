require_relative "spec_helper"

describe "openstack-metering::api" do
  before { metering_stubs }
  describe "ubuntu" do
    before do
      @chef_run = ::ChefSpec::ChefRunner.new ::UBUNTU_OPTS
      @chef_run.converge "openstack-metering::api"
    end

    expect_runs_common_recipe

    describe "/var/cache/ceilometer" do
      before do
        @dir = @chef_run.directory "/var/cache/ceilometer"
      end

      it "has proper owner" do
        expect(@dir).to be_owned_by "ceilometer", "ceilometer"
      end

      it "has proper modes" do
        expect(sprintf("%o", @dir.mode)).to eq "700"
      end
    end

    it "starts api service" do
      expect(@chef_run).to start_service("ceilometer-api")
    end

    it "starts api service" do
      expect(@chef_run).to start_service("ceilometer-api")
    end
  end
end
