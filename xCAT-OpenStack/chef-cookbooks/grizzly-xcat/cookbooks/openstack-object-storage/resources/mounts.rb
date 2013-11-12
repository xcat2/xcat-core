#
# Cookbook Name:: swift
# Resource:: mounts
#
# Copyright 2012, Rackspace US, Inc.
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
# Author: Ron Pedde <ron.pedde@rackspace.com>
#

=begin
  Ensure that swift mounts are strongly enforced.  This
  will ensure specified drives are mounted, and unspecified
  drives are not mounted.  In addition, if there is a stale
  mountpoint (from disk failure, maybe?), then that mountpoint
  will try to be unmounted

  Sample use:

  openstack_object_storage_mounts "/srv/node" do
     devices [ "sdb1", "sdc1" ]
     action :ensure_exists
     ip "10.1.1.1"
  end

  It will force mounts based on fs uuid (mangled to remove
  dashes) and return a structure that describes the disks
  mounted.

  As this is expected to be consumed for the purposes of
  swift, the ip address should be the address that gets
  embedded into the ring (i.e. the listen port of the storage server)

  Example return structure:

  { "2a9452c5-d929-43d9-9631-4340ace45279": {
      "device": "sdb1",
      "ip": "10.1.1.1",
      "mounted": "true",
      "mountpoint": "2a9452c5d92943d996314340ace45279",
      "size": 1022 (in 1k increments)
      "uuid": "2a9452c5-d929-43d9-9631-4340ace45279"
    },
    ...
  }

=end

actions :ensure_exists

def initialize(*args)
  super
  @action = :ensure_exists
end

attribute :name,               :kind_of => String
attribute :devices,            :kind_of => Array
attribute :ip,                 :kind_of => String, :default => "127.0.0.1"
attribute :publish_attributes, :kind_of => String, :default => nil
attribute :format,             :kind_of => String, :default => "xfs"
