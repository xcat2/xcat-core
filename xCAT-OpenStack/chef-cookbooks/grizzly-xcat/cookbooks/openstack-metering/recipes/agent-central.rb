#
# Cookbook Name:: openstack-metering
# Recipe:: agent-central
#
# Copyright 2013, AT&T Services, Inc.
# Copyright 2013, SUSE Linux GmbH
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

include_recipe "openstack-metering::common"

platform = node["openstack"]["metering"]["platform"]
platform["agent_central_packages"].each do |pkg|
  package pkg
end

service platform["agent_central_service"] do
  action :start
end
