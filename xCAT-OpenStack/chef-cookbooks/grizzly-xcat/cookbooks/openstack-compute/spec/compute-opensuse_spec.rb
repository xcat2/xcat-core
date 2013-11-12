require_relative "spec_helper"

describe "openstack-compute::compute" do
  before { compute_stubs }
  describe "opensuse" do
    before do
      @chef_run = ::ChefSpec::ChefRunner.new ::OPENSUSE_OPTS
      @chef_run.converge "openstack-compute::compute"
    end

    it "installs nfs client packages" do
      expect(@chef_run).to upgrade_package "nfs-utils"
      expect(@chef_run).not_to upgrade_package "nfs-utils-lib"
    end
  end
end
