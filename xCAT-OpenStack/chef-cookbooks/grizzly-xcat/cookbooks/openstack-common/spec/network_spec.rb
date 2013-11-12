require_relative "spec_helper"
require ::File.join ::File.dirname(__FILE__), "..", "libraries", "network"

describe ::Openstack do
  before do
    @chef_run = ::ChefSpec::ChefRunner.new(::CHEFSPEC_OPTS) do |n|
      n.set["network"] = {
        "interfaces" => {
          "lo" => {
            "addresses" => {
              "127.0.0.1"=> {
                "family" => "inet",
                "prefixlen" => "8",
                "netmask" => "255.0.0.0",
                "scope" => "Node"
              },
              "::1" => {
                "family" => "inet6",
                "prefixlen" => "128",
                "scope" => "Node"
              }
            }
          }
        }
      }
    end
    @chef_run.converge "openstack-common::default"
    @subject = ::Object.new.extend ::Openstack
  end

  describe "#address_for" do
    it "returns ipv4 address" do
      @subject.stub(:node).and_return @chef_run.node
      resp = @subject.address_for "lo"

      expect(resp).to eq "127.0.0.1"
    end

    it "returns ipv4 address" do
      @subject.stub(:node).and_return @chef_run.node
      resp = @subject.address_for "lo", "inet6"

      expect(resp).to eq "::1"
    end
  end
end
