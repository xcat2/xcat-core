require File.expand_path('../support/helpers', __FILE__)

describe_recipe "openssh::default" do
  include Helpers::OpenSSH

  describe "package" do
    it "installs" do
      node['openssh']['package_name'].each do |pkg|
        package(pkg).must_be_installed
      end
    end
  end
end
