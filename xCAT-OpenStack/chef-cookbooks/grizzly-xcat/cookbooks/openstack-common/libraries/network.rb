#
# Cookbook Name:: openstack-common
# library:: address
#
# Copyright 2012-2013, AT&T Services, Inc.
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

module ::Openstack
  # return the IPv4 (default) address of the given interface.
  #
  # @param [String] interface The interface to query.
  # @param [String] family The protocol family to use.
  # @return [String] The IPv4 address.
  def address_for interface, family="inet"
    interface_node = node["network"]["interfaces"][interface]["addresses"]
    interface_node.select do |address, data|
      if data['family'] == family
        return address
      end
    end
  end
end
