#--------------------
# node/ring settings
#--------------------

default["swift"]["state"] = {}
default["swift"]["swift_hash"] = "107c0568ea84"
default["swift"]["audit_hour"] = "5"
default["swift"]["disk_enum_expr"] = "node[:block_device]"
default["swift"]["auto_rebuild_rings"] = false
default["swift"]["git_builder_ip"] = "127.0.0.1"

# the release only has any effect on ubuntu, and must be
# a valid release on http://ubuntu-cloud.archive.canonical.com/ubuntu
default["swift"]["release"] = "grizzly"

# we support an optional secret databag where we will retrieve the
# following attributes overriding any default attributes here
#
# {
#   "id": "swift_dal2",
#   "swift_hash": "107c0568ea84"
#   "swift_authkey": "keW4all"
#   "dispersion_auth_user": "test:test",
#   "dispersion_auth_key": "test"
# }
default["swift"]["swift_secret_databag_name"] = nil

#--------------------
# roles
#--------------------

default["swift"]["setup_chef_role"]             = "swift-setup"
default["swift"]["management_server_chef_role"] = "swift-management-server"
default["swift"]["proxy_server_chef_role"]      = "swift-proxy-server"
default["swift"]["object_server_chef_role"]     = "swift-object-server"
default["swift"]["account_server_chef_role"]    = "swift-account-server"
default["swift"]["container_server_chef_role"]  = "swift-container-server"

#--------------------
# authentication
#--------------------

default["swift"]["authmode"]              = "swauth"
default["swift"]["authkey"]               = "test"
default["swift"]["swift_url"]             = "http://127.0.0.1:8080/v1/"
default["swift"]["swauth_url"]            = "http://127.0.0.1:8080/v1/"
default["swift"]["auth_url"]              = "http://127.0.0.1:8080/auth/v1.0"

#---------------------
# dispersion settings
#---------------------

default["swift"]["dispersion"]["auth_user"] = "test:test"
default["swift"]["dispersion"]["auth_key"] = "test"


# settings for the swift ring - these default settings are
# a safe setting for testing but part_power should be set to
# 26 in production to allow a swift cluster with 50,000 spindles
default["swift"]["ring"]["part_power"] = 18
default["swift"]["ring"]["min_part_hours"] = 1
default["swift"]["ring"]["replicas"] = 3

#------------------
# statistics
#------------------
default["swift"]["statistics"]["enabled"] = true
default["swift"]["statistics"]["sample_rate"] = 1

# there are two ways to discover your graphite server ip for
# statsd to periodically publish to.  You can directly set
# the ip below, or leave it set to nil and supply chef with
# the role name of your graphite server and the interface
# name to retrieve the appropriate internal ip address from
#
# if no servers with the role below can be found then
# 127.0.0.1 will be used
default["swift"]["statistics"]["graphing_ip"]  = nil
default["swift"]["statistics"]["graphing_role"] = 'graphite-role'
default["swift"]["statistics"]["graphing_interface"] = 'eth0'

# how frequently to run chef instantiated /usr/local/bin/swift_statsd_publish.py
# which publishes dispersion and recon statistics (in minutes)
default["swift"]["statistics"]["report_frequency"] = 15

# enable or disable specific portions of generated report
default["swift"]["statistics"]["enable_dispersion_report"] = true
default["swift"]["statistics"]["enable_recon_report"] = true
default["swift"]["statistics"]["enable_disk_report"] = true

# settings for statsd which should be configured to use the local
# statsd daemon that chef will install if statistics are enabled
default["swift"]["statistics"]["statsd_host"] = "127.0.0.1"
default["swift"]["statistics"]["statsd_port"] = "8125"
default["swift"]["statistics"]["statsd_prefix"] = "openstack.swift"

# paths to the recon cache files
default["swift"]["statistics"]["recon_account_cache"] = "/var/cache/swift/account.recon"
default["swift"]["statistics"]["recon_container_cache"] = "/var/cache/swift/container.recon"
default["swift"]["statistics"]["recon_object_cache"] = "/var/cache/swift/object.recon"

#------------------
# network settings
#------------------

# the cidr configuration items are unimportant for a single server
# configuration, but in a multi-server setup, the cidr should match
# the interface appropriate to that service as they are used to
# resolve the appropriate addresses to use for internode
# communication

# proxy servers
default["swift"]["network"]["proxy-bind-ip"]	        = "0.0.0.0"
default["swift"]["network"]["proxy-bind-port"] 	        = "8080"
default["swift"]["network"]["proxy-cidr"]               = "10.0.0.0/24"

# account servers
default["swift"]["network"]["account-bind-ip"]	        = "0.0.0.0"
default["swift"]["network"]["account-bind-port"]        = "6002"

# container servers
default["swift"]["network"]["container-bind-ip"]	= "0.0.0.0"
default["swift"]["network"]["container-bind-port"]      = "6001"

# object servers
default["swift"]["network"]["object-bind-ip"]	        = "0.0.0.0"
default["swift"]["network"]["object-bind-port"]         = "6000"
default["swift"]["network"]["object-cidr"]              = "10.0.0.0/24"

#------------------
# sysctl
#------------------

# set sysctl properties for time waits
default['sysctl']['params']['net']['ipv4']['tcp_tw_recycle'] = 1
default['sysctl']['params']['net']['ipv4']['tcp_tw_reuse'] = 1
default['sysctl']['params']['net']['ipv4']['tcp_syncookies'] = 0

# N.B. conntrack_max may also need to be adjusted if
# server is running a stateful firewall

#------------------
# disk search
#------------------

# disk_test_filter is an array of predicates to test against disks to
# determine if a disk should be formatted and configured for swift.
# Each predicate is evaluated in turn, and a false from the predicate
# will result in the disk not being considered as a candidate for
# formatting.
default["swift"]["disk_test_filter"] = [ "candidate =~ /(sd|hd|xvd|vd)(?!a$)[a-z]+/",
                                         "File.exist?('/dev/' + candidate)",
                                         "not system('/sbin/parted /dev/' + candidate + ' -s print | grep linux-swap')",
                                         "not info.has_key?('removable') or info['removable'] == 0.to_s" ]

#-------------------
# template overrides
#-------------------

# proxy-server

# override in a wrapper to enable tempurl with swauth
default["swift"]["tempurl"]["enabled"] = false

# container-server

# Override this with an allowed list of your various swift clusters if you wish
# to enable container sync for your end-users between clusters.  This should
# be an array of fqdn hostnames for the cluster end-points that your end-users
# would access in the format of ['host1', 'host2', 'host3']
default["swift"]["container-server"]["allowed_sync_hosts"] = []

# container-sync logging settings
default["swift"]["container-server"]["container-sync"]["log_name"] = 'container-sync'
default["swift"]["container-server"]["container-sync"]["log_facility"] = 'LOG_LOCAL0'
default["swift"]["container-server"]["container-sync"]["log_level"] = 'INFO'

# If you need to use an HTTP Proxy, set it here; defaults to no proxy.
default["swift"]["container-server"]["container-sync"]["sync_proxy"] = nil

# Will sync, at most, each container once per interval (in seconds)
default["swift"]["container-server"]["container-sync"]["interval"] = 300

# Maximum amount of time to spend syncing each container per pass (in seconds)
default["swift"]["container-server"]["container-sync"]["container_time"] = 60

#------------------
# swauth source
# -----------------
# Versions of swauth in Ubuntu Cloud Archive PPA can be outdated. This
# allows us to chose to install directly from a tagged branch of
# gholt's repository.
# values:  package, git
default["swift"]["swauth_source"] = "package"
default["swift"]["swauth_repository"] = "https://github.com/gholt/swauth.git"
default["swift"]["swauth_version"] = "1.0.8"

#------------------
# packages
#------------------

# Leveling between distros
case platform
when "redhat"
  default["swift"]["platform"] = {
    "disk_format" => "ext4",
    "proxy_packages" => ["openstack-swift-proxy", "sudo", "cronie", "python-memcached"],
    "object_packages" => ["openstack-swift-object", "sudo", "cronie"],
    "container_packages" => ["openstack-swift-container", "sudo", "cronie"],
    "account_packages" => ["openstack-swift-account", "sudo", "cronie"],
    "swift_packages" => ["openstack-swift", "sudo", "cronie"],
    "swauth_packages" => ["openstack-swauth", "sudo", "cronie"],
    "rsync_packages" => ["rsync"],
    "git_packages" => ["xinetd", "git", "git-daemon"],
    "service_prefix" => "openstack-",
    "service_suffix" => "",
    "git_dir" => "/var/lib/git",
    "git_service" => "git",
    "service_provider" => Chef::Provider::Service::Redhat,
    "override_options" => "",
    "swift_statsd_publish" => "/usr/bin/swift-statsd-publish.py"
  }
#
# python-iso8601 is a missing dependency for swift.
# https://bugzilla.redhat.com/show_bug.cgi?id=875948
when "centos"
  default["swift"]["platform"] = {
    "disk_format" => "xfs",
    "proxy_packages" => ["openstack-swift-proxy", "sudo", "cronie", "python-iso8601", "python-memcached" ],
    "object_packages" => ["openstack-swift-object", "sudo", "cronie", "python-iso8601" ],
    "container_packages" => ["openstack-swift-container", "sudo", "cronie", "python-iso8601" ],
    "account_packages" => ["openstack-swift-account", "sudo", "cronie", "python-iso8601" ],
    "swift_packages" => ["openstack-swift", "sudo", "cronie", "python-iso8601" ],
    "swauth_packages" => ["openstack-swauth", "sudo", "cronie", "python-iso8601" ],
    "rsync_packages" => ["rsync"],
    "git_packages" => ["xinetd", "git", "git-daemon"],
    "service_prefix" => "openstack-",
    "service_suffix" => "",
    "git_dir" => "/var/lib/git",
    "git_service" => "git",
    "service_provider" => Chef::Provider::Service::Redhat,
    "override_options" => "",
    "swift_statsd_publish" => "/usr/bin/swift-statsd-publish.py"
  }
when "fedora"
  default["swift"]["platform"] = {
    "disk_format" => "xfs",
    "proxy_packages" => ["openstack-swift-proxy", "python-memcached"],
    "object_packages" => ["openstack-swift-object"],
    "container_packages" => ["openstack-swift-container"],
    "account_packages" => ["openstack-swift-account"],
    "swift_packages" => ["openstack-swift"],
    "swauth_packages" => ["openstack-swauth"],
    "rsync_packages" => ["rsync"],
    "git_packages" => ["git", "git-daemon"],
    "service_prefix" => "openstack-",
    "service_suffix" => ".service",
    "git_dir" => "/var/lib/git",
    "git_service" => "git",
    "service_provider" => Chef::Provider::Service::Systemd,
    "override_options" => "",
    "swift_statsd_publish" => "/usr/bin/swift-statsd-publish.py"
  }
when "ubuntu"
  default["swift"]["platform"] = {
    "disk_format" => "xfs",
    "proxy_packages" => ["swift-proxy", "python-memcache"],
    "object_packages" => ["swift-object"],
    "container_packages" => ["swift-container"],
    "account_packages" => ["swift-account", "python-swiftclient"],
    "swift_packages" => ["swift"],
    "swauth_packages" => ["swauth"],
    "rsync_packages" => ["rsync"],
    "git_packages" => ["git-daemon-sysvinit"],
    "service_prefix" => "",
    "service_suffix" => "",
    "git_dir" => "/var/cache/git",
    "git_service" => "git-daemon",
    "service_provider" => Chef::Provider::Service::Upstart,
    "override_options" => "-o Dpkg::Options:='--force-confold' -o Dpkg::Option:='--force-confdef'",
    "swift_statsd_publish" => "/usr/local/bin/swift-statsd-publish.py"
  }
end
