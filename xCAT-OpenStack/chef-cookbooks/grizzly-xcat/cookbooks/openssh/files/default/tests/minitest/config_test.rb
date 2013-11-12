require File.expand_path('../support/helpers', __FILE__)

describe "openssh::config" do
  include Helpers::OpenSSH

  describe "services" do
    it "runs as a daemon" do
      service("ssh").must_be_running
    end

    it "boots on startup" do
      service("ssh").must_be_enabled
    end
  end

  describe "files" do
    it "is listening on port 22" do
      assert_include 'Port 22'
    end

    it "is listening on 0.0.0.0" do
      assert_include 'ListenAddress 0.0.0.0'
    end

    it "permits root login" do
      assert_include 'PermitRootLogin no'
    end

    it "permits password authentication" do
      assert_include 'PasswordAuthentication no'
    end

    it "has client alive directives" do
      assert_include 'ClientAliveInterval 900'
      assert_include 'ClientAliveCountMax 0'
    end
  end
end
