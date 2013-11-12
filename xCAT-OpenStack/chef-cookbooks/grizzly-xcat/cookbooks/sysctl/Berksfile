site :opscode
#chef_api :config

metadata

group :test do
  cookbook "apt"
  cookbook "yum"
  cookbook "minitest-handler"

  cookbook "sysctl_test", :path => "./test/kitchen/cookbooks/sysctl_test"
  # https://github.com/opscode/test-kitchen/issues/28
#  require 'pathname'
#  cb_dir = ::File.join('.', 'test', 'kitchen', 'cookbooks')
#  if ::File.exist?(cb_dir)
#    Pathname.new(cb_dir).children.select(&:directory?).each do |c|
#      cookbook c.basename.to_s, :path => ::File.join(cb_dir, c.basename.to_s).to_s
#    end
#  end
end
