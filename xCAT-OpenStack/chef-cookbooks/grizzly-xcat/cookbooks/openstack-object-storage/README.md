Description
===========

Installs the OpenStack Object Storage service **Swift** as part of the OpenStack reference deployment Chef for OpenStack. The http://github.com/stackforge/chef-openstack-repo contains documentation for using this cookbook in the context of a full OpenStack deployment. Swift is currently installed from packages.

https://wiki.openstack.org/wiki/Swift

Requirements
============

Clients
--------

 * CentOS >= 6.3
 * Ubuntu >= 12.04

Chef
---------

 * 11.4.4

Cookbooks
---------

 * memcached
 * sysctl

Roles
=====

 * swift-account-server - storage node for account data
 * swift-container-server - storage node for container data
 * swift-object-server - storage node for object server
 * swift-proxy-server - proxy for swift storge nodes
 * swift-setup - server responsible for generating initial settings
 * swift-management-server - responsible for ring generation

The swift-management-server role performs the following functions:

 * proxy node that knows super admin password
 * ring repository and ring building workstation
 * generally always has the swift-setup role too
 * there can only be _one_ swift-management-server

There *must* be  node with the the swift-managment-server role to act
as the ring repository.

In small environments, it is likely that all storage machines will
have all-in-one roles, with a load balancer ahead of it

In larger environments, where it is cost effective to split the proxy
and storage layer, storage nodes will carry
swift-{account,container,object}-server roles, and there will be
dedicated hosts with the swift-proxy-server role.

In really really huge environments, it's possible that the storage
node will be split into swift-{container,accout}-server nodes and
swift-object-server nodes.


Attributes
==========

 * ```default[:swift][:authmode]``` - "swauth" or "keystone" (default "swauth"). Right now, only swauth is supported (defaults to swauth)

 * ```default[:swift][:tempurl]``` - "true" or "false". Adds tempurl to the pipeline and sets allow_overrides to true when using swauth

 * ```default[:swift][:swauth_source]``` - "git" or "package"(default). Selects between installing python-swauth from git or system package

 * ```default[:swift][:swauth_repository]``` - Specifies git repo. Default "https://github.com/gholt/swauth.git"

 * ```default[:swift][:swauth_version]``` - Specifies git repo tagged branch. Default "1.0.8"

 * ```default[:swift][:swift_secret_databag_name]``` - this cookbook supports an optional secret databag where we will retrieve the following attributes overriding any default attributes below. (defaults to nil)

```
        {
          "id": "swift_dal2",
          "swift_hash": "1a7c0568fa84"
          "swift_authkey": "keY4all"
          "dispersion_auth_user": "ops:dispersion",
          "dispersion_auth_key": "dispersionpass"
        }
```

 * ```default[:swift][:swift_hash]``` - swift_hash_path_suffix in /etc/swift/swift.conf (defaults to 107c0568ea84)

 * ```default[:swift][:audit_hour]``` - Hour to run swift_auditor on storage nodes (defaults to 5)

 * ```default[:swift][:disk_enum_expr]``` - Eval-able expression that lists
   candidate disk nodes for disk probing.  The result shoule be a hash
   with keys being the device name (without the leading "/dev/") and a
   hash block of any extra info associated with the device.  For
   example: { "sdc" => { "model": "Hitachi 7K3000" }}.  Largely,
   though, if you are going to make a list of valid devices, you
   probably know all the valid devices, and don't need to pass any
   metadata about them, so { "sdc" => {}} is probably enough.  Example
   expression: Hash[('a'..'f').to_a.collect{|x| [ "sd{x}", {} ]}]

 * ```default[:swift][:ring][:part_power]``` - controls the size of the ring (defaults to 18)

 * ```default[:swift][:ring][:min_part_hours]``` - the minimum number of hours before swift is allowed to migrate a partition (defaults to 1)

 * ```default[:swift][:ring][:replicas]``` - how many replicas swift should retain (defaults to 3)

 * ```default[:swift][:disk_test_filter]``` - an array of expressions that must
   all be true in order a block deviced to be considered for
   formatting and inclusion in the cluster.  Each rule gets evaluated
   with "candidate" set to the device name (without the leading
   "/dev/") and info set to the node hash value.  Default rules:

    * "candidate =~ /sd[^a]/ or candidate =~ /hd[^a]/ or candidate =~
      /vd[^a]/"

    * "File.exists?('/dev/ + candidate)"

    * "not system('/sbin/sfdisk -V /dev/' + candidate + '>/dev/null 2>&2')"

    * "info['removable'] = 0" ])

 * ```default[:swift][:expected_disks]``` - an array of device names that the
   operator expecs to be identified by the previous two values.  This
   acts as a second-check on discovered disks.  If this array doesn't
   match the found disks, then chef processing will be stopped.
   Example: ("b".."f").collect{|x| "sd#{x}"}.  Default: none.

There are other attributes that must be set depending on authmode.
For "swauth", the following attributes are used:

 * ```default[:swift][:authkey]``` - swauth super admin key if using swauth (defaults to test)

In addition, because swift is typically deployed as a cluster
there are some attributes used to find interfaces and ip addresses
on storage nodes:

 * ```default[:swift][:git_builder_ip]``` - the IP address of the management server which other cluster members will use as their git pull target for ring updates (defaults to 127.0.0.1)
 * ```default[:swift][:network][:proxy-bind-ip]``` - the IP address to bind to
   on the proxy servers (defaults to 0.0.0.0 for all addresses)
 * ```default[:swift][:network][:proxy-bind-port]``` - the port to bind to
   on the proxy servers (defaults to 8080)
 * ```default[:swift][:network][:account-bind-ip]``` - the IP address to bind to
   on the account servers (defaults to 0.0.0.0 for all addresses)
 * ```default[:swift][:network][:account-bind-port]``` - the port to bind to
   on the account servers (defaults to 6002)
 * ```default[:swift][:network][:container-bind-ip]``` - the IP address to bind to
   on the container servers (defaults to 0.0.0.0 for all addresses)
 * ```default[:swift][:network][:container-bind-port]``` - the port to bind to
   on the container servers (defaults to 6002)
 * ```default[:swift][:network][:object-bind-ip]``` - the IP address to bind to
   on the object servers (defaults to 0.0.0.0 for all addresses)
 * ```default[:swift][:network][:object-bind-port]``` - the port to bind to
   on the container servers (defaults to 6002)
 * ```default[:swift][:network][:object-cidr]``` - the CIDR network for your object
   servers in order to build the ring (defaults to 10.0.0.0/24)

Examples
========

Example environment
-------------------

```json
{
  "default_attributes": {
    "swift": {
          "swift_hash": "107c0568ea84",
          "authmode": "swauth",
          "authkey": "test"
      "auto_rebuild_rings": false
      "git_builder_ip": "10.0.0.10"
      "swauth": {
        "url": "http://10.0.0.10:8080/v1/"
        }
      },
  },
  "name": "swift",
  "chef_type": "environment",
  "json_class": "Chef::Environment"
}
```

This sets up defaults for a swauth-based cluster with the storage
network on 10.0.0.0/24.

Example all-in-one
--------------------------

Example all-in-one storage node config (note there should only ever be
one node with the swift-setup and swift-management roles)

```json
{
  "id":       "storage1",
  "name":     "storage1",
  "json_class": "Chef::Node",
  "run_list": [
    "role[swift-setup]",
    "role[swift-management-server]",
    "role[swift-account-server]",
    "role[swift-object-server]",
    "role[swift-container-server]",
    "role[swift-proxy-server]"
  ],
  "chef_environment": "development",
  "normal": {
    "swift": {
      "zone": "1"
    }
  }
}
```

Standalone Storage Server
-------------------------

```json
{
  "name": "swift-object-server",
  "json_class": "Chef::Role",
  "run_list": [
    "recipe[swift::object-server]"
  ],
  "description": "A storage server role.",
  "chef_type": "role"
}
```

Standalone Proxy Server
-----------------------

```json
  "run_list": [
    "role[swift-proxy-server]"
  ]
```

Testing
=======

This cookbook is using [ChefSpec](https://github.com/acrmp/chefspec) for testing. Run the following before commiting. It will run your tests, and check for lint errors.

    $ ./run_tests.bash

There is also a Vagrant test environment that you can launch in order to integration
test this cookbook. See the <a href="tests/README.md" target="_blank">tests/README.md</a> file for more information on launching the environment.

Testing
=======

    $ bundle install
    $ bundle exec berks install
    $ bundle exec strainer test

License and Author
==================

|                      |                                                    |
|:---------------------|:---------------------------------------------------|
| **Authors**          |  Alan Meadows (<alan.meadows@gmail.com>)           |
|                      |  Oisin Feeley (<of3434@att.com>)                    |
|                      |  Ron Pedde (<ron.pedde@rackspace.com>)             |
|                      |  Will Kelly (<will.kelly@rackspace.com>)           |
|                      |                                                    |
| **Copyright**        |  Copyright (c) 2013, AT&T, Inc.                    |
|                      |  Copyright (c) 2012, Rackspace US, Inc.            |

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
