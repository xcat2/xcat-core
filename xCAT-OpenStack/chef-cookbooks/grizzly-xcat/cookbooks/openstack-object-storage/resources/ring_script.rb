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
  Build a proposed ring-building script
  Sample use:

  openstack_object_storage_ring_script "/tmp/build-rings.sh" do
     owner "root"
     group "swift"
     mode "0700"
     ring_path "/etc/swift/ring-workspace"
     action :ensure_exists
  end

=end

actions :ensure_exists

def initialize(*args)
  super
  @action = :ensure_exists
end

attribute :name,                   :kind_of => String
attribute :owner,                  :kind_of => String, :default => "root"
attribute :group,                  :kind_of => String, :default => "root"
attribute :mode,                   :kind_of => String, :default => "0600"
attribute :ring_path,              :kind_of => String, :default => "/etc/swift"
