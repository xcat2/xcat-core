#
# Cookbook Name:: statsd
# Recipe:: default
#
# Copyright 2011, Librato, Inc.
#

include_recipe "nodejs"
include_recipe "git"

git "/usr/share/statsd" do
  repository node[:statsd][:repo]
  revision node[:statsd][:revision]
  action :sync
end

execute "install dependencies" do
  command "npm install -d"
  cwd "/usr/share/statsd"
end

backends = []

if node[:statsd][:graphite_enabled]
  backends << "./backends/graphite"
end

node[:statsd][:backends].each do |k, v|
  if v
    name = "#{k}@#{v}"
  else
    name= k
  end

  execute "install npm module #{name}" do
    command "npm install #{name}"
    cwd "/usr/share/statsd"
  end

  backends << k
end

directory "/etc/statsd" do
  action :create
end

user "statsd" do
  comment "statsd"
  system true
  shell "/bin/false"
end

service "statsd" do
  provider Chef::Provider::Service::Upstart

  restart_command "stop statsd; start statsd"
  start_command "start statsd"
  stop_command "stop statsd"

  supports :restart => true, :start => true, :stop => true
end

template "/etc/statsd/config.js" do
  source "config.js.erb"
  mode 0644

  config_hash = {
    :flushInterval => node[:statsd][:flush_interval_msecs],
    :port => node[:statsd][:port],
    :backends => backends
  }.merge(node[:statsd][:extra_config])

  if node[:statsd][:graphite_enabled]
    config_hash[:graphitePort] = node[:statsd][:graphite_port]
    config_hash[:graphiteHost] = node[:statsd][:graphite_host]
  end

  variables(:config_hash => config_hash)

  notifies :restart, resources(:service => "statsd")
end

directory "/usr/share/statsd/scripts" do
  action :create
end

template "/usr/share/statsd/scripts/start" do
  source "upstart.start.erb"
  mode 0755

  notifies :restart, resources(:service => "statsd")
end

cookbook_file "/etc/init/statsd.conf" do
  source "upstart.conf"
  mode 0644

  notifies :restart, resources(:service => "statsd")
end

bash "create_log_file" do
  code <<EOH
touch #{node[:statsd][:log_file]} && chown statsd #{node[:statsd][:log_file]}
EOH
  not_if {File.exist?(node[:statsd][:log_file])}
end

service "statsd" do
  action [ :enable, :start ]
end
