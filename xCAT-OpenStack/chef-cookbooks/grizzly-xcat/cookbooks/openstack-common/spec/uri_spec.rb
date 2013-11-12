require_relative "spec_helper"
require ::File.join ::File.dirname(__FILE__), "..", "libraries", "uri"
require "uri"

describe ::Openstack do
  before do
    @subject = ::Object.new.extend(::Openstack)
  end

  describe "#uri_from_hash" do
    it "returns nil when no host or uri key found" do
      hash = {
        "port" => 8888,
        "path" => "/path"
      }
      @subject.uri_from_hash(hash).should be_nil
    end
    it "returns uri when uri key found, ignoring other parts" do
      uri = "http://localhost/"
      hash = {
        "port" => 8888,
        "path" => "/path",
        "uri"  => uri
      }
      result = @subject.uri_from_hash(hash)
      result.should be_a URI
      result.to_s.should == uri
    end
    it "constructs from host" do
      uri = "https://localhost:8888/path"
      hash = {
        "scheme" => 'https',
        "port"   => 8888,
        "path"   => "/path",
        "host"   => "localhost"
      }
      result = @subject.uri_from_hash(hash)
      result.to_s.should == uri
    end
    it "constructs with defaults" do
      uri = "https://localhost"
      hash = {
        "scheme" => 'https',
        "host"   => "localhost"
      }
      result = @subject.uri_from_hash(hash)
      result.to_s.should == uri
    end
    it "constructs with extraneous keys" do
      uri = "http://localhost"
      hash = {
        "host"    => "localhost",
        "network" => "public"  # To emulate the osops-utils::ip_location way...
      }
      result = @subject.uri_from_hash(hash)
      result.to_s.should == uri
    end
  end

  describe "#uri_join_paths" do
    it "returns nil when no paths are passed in" do
      @subject.uri_join_paths().should be_nil
    end
    it "preserves absolute path when only absolute path passed in" do
      path = "/abspath"
      result = @subject.uri_join_paths(path)
      result.should == path
    end
    it "preserves relative path when only relative path passed in" do
      path = "abspath/"
      result = @subject.uri_join_paths(path)
      result.should == path
    end
    it "preserves leadng and trailing slashes" do
      expected = "/path/to/resource/"
      result = @subject.uri_join_paths("/path", "to", "resource/")
      result.should == expected
    end
    it "removes extraneous intermediate slashes" do
      expected = "/path/to/resource"
      result = @subject.uri_join_paths("/path", "//to/", "/resource")
      result.should == expected
    end
  end
end
