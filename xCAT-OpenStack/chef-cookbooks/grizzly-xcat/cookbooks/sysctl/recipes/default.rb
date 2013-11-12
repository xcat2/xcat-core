#
# Cookbook Name:: sysctl
# Recipe:: default
#
# Copyright 2011, Fewbytes Technologies LTD
# Copyright 2012, Chris Roberts <chrisroberts.code@gmail.com>
# Copyright 2013, OneHealth Solutions, Inc.
#

template "/etc/rc.d/init.d/procps" do
  source "procps.init-rhel.erb"
  mode '0755'
  only_if {platform_family?("rhel") }
end

service "procps"

sysctl_path = if(node['sysctl']['conf_dir'])
  directory node['sysctl']['conf_dir'] do
    owner "root"
    group "root"
    mode 0755
    action :create
  end
  File.join(node['sysctl']['conf_dir'], '99-chef-attributes.conf')
else
  node['sysctl']['allow_sysctl_conf'] ? '/etc/sysctl.conf' : nil
end

if(sysctl_path)
  template sysctl_path do
    action :nothing
    source 'sysctl.conf.erb'
    mode '0644'
    notifies :start, "service[procps]", :immediately
    only_if do
      node['sysctl']['params'] && !node['sysctl']['params'].empty?
    end
  end

  ruby_block 'sysctl config notifier' do
    block do
      true
    end
    notifies :create, "template[#{sysctl_path}]", :delayed
  end
end
