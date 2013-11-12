#
# Cookbook Name:: rabbitmq_test
# Recipe:: lwrps
#
# Copyright 2013, Opscode, Inc. <legal@opscode.com>
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

chef_gem "bunny"

include_recipe "rabbitmq::default"

# force the rabbitmq restart now, then start testing
execute "sleep 10" do
  notifies :restart, "service[#{node['rabbitmq']['service_name']}]", :immediately
end

include_recipe "rabbitmq::plugin_management"
include_recipe "rabbitmq::virtualhost_management"
include_recipe "rabbitmq::policy_management"
include_recipe "rabbitmq::user_management"

# can't verify it actually goes through without logging in, but at least exercise the code
rabbitmq_user 'kitchen3' do
  password 'foobar'
  action :change_password
end
