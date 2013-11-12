#
# Cookbook Name:: postgresql
# Recipe:: ruby
#
# Author:: Joshua Timberman (<joshua@opscode.com>)
# Copyright 2012 Opscode, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

begin
  require 'pg'
rescue LoadError
  execute "apt-get update" do
    ignore_failure true
    action :nothing
  end.run_action(:run) if node['platform_family'] == "debian"

  node.set['build_essential']['compiletime'] = true
  include_recipe "build-essential"
  include_recipe "postgresql::client"

  node['postgresql']['client']['packages'].each do |pg_pack|

    resources("package[#{pg_pack}]").run_action(:install)

  end

  begin
    chef_gem "pg"
  rescue Gem::Installer::ExtensionBuildError => e
    # Are we an omnibus install?
    raise if RbConfig.ruby.scan(%r{(chef|opscode)}).empty?
    # Still here, must be omnibus. Lets make this thing install!
    Chef::Log.warn 'Failed to properly build pg gem. Forcing properly linking and retrying (omnibus fix)'
    gem_dir = e.message.scan(%r{will remain installed in ([^ ]+)}).flatten.first
    raise unless gem_dir
    gem_name = File.basename(gem_dir)
    ext_dir = File.join(gem_dir, 'ext')
    gem_exec = File.join(File.dirname(RbConfig.ruby), 'gem')
    new_content = <<-EOS
require 'rbconfig'
%w(
configure_args
LIBRUBYARG_SHARED
LIBRUBYARG_STATIC
LIBRUBYARG
LDFLAGS
).each do |key|
  RbConfig::CONFIG[key].gsub!(/-Wl[^ ]+( ?\\/[^ ]+)?/, '')
  RbConfig::MAKEFILE_CONFIG[key].gsub!(/-Wl[^ ]+( ?\\/[^ ]+)?/, '')
end
RbConfig::CONFIG['RPATHFLAG'] = ''
RbConfig::MAKEFILE_CONFIG['RPATHFLAG'] = ''
EOS
    new_content << File.read(extconf_path = File.join(ext_dir, 'extconf.rb'))
    File.open(extconf_path, 'w') do |file|
      file.write(new_content)
    end

    lib_builder = execute 'generate pg gem Makefile' do
      command "#{RbConfig.ruby} extconf.rb"
      cwd ext_dir
      action :nothing
    end
    lib_builder.run_action(:run)

    lib_maker = execute 'make pg gem lib' do
      command 'make'
      cwd ext_dir
      action :nothing
    end
    lib_maker.run_action(:run)

    lib_installer = execute 'install pg gem lib' do
      command 'make install'
      cwd ext_dir
      action :nothing
    end
    lib_installer.run_action(:run)

    spec_installer = execute 'install pg spec' do
      command "#{gem_exec} spec ./cache/#{gem_name}.gem --ruby > ./specifications/#{gem_name}.gemspec"
      cwd File.join(gem_dir, '..', '..')
      action :nothing
    end
    spec_installer.run_action(:run)

    Chef::Log.warn 'Installation of pg gem successful!'
  end
end
