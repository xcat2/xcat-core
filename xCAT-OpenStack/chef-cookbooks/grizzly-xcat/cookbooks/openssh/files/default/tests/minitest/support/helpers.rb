module Helpers
  module OpenSSH
    include MiniTest::Chef::Assertions
    include MiniTest::Chef::Context
    include MiniTest::Chef::Resources

    def assert_include(expected)
      skip unless %w{debian ubuntu}.include? node.platform

      file(node['openssh']['config']).must_include expected
    end
  end
end
