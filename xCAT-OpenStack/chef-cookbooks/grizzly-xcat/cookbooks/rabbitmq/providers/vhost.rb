#
# Cookbook Name:: rabbitmq
# Provider:: vhost
#
# Copyright 2011-2013, Opscode, Inc.
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

def vhost_exists?(name)
  cmdStr = "rabbitmqctl -q list_vhosts | grep ^#{name}$"
  cmd = Mixlib::ShellOut.new(cmdStr)
  cmd.environment['HOME'] = ENV.fetch('HOME', '/root')
  cmd.run_command
  Chef::Log.debug "rabbitmq_vhost_exists?: #{cmdStr}"
  Chef::Log.debug "rabbitmq_vhost_exists?: #{cmd.stdout}"
  begin
    cmd.error!
    true
  rescue
    false
  end
end

action :add do
  unless vhost_exists?(new_resource.vhost)
    cmdStr = "rabbitmqctl add_vhost #{new_resource.vhost}"
    execute cmdStr do
      Chef::Log.debug "rabbitmq_vhost_add: #{cmdStr}"
      Chef::Log.info "Adding RabbitMQ vhost '#{new_resource.vhost}'."
      new_resource.updated_by_last_action(true)
    end
  end
end

action :delete do
  if vhost_exists?(new_resource.vhost)
    cmdStr =  "rabbitmqctl delete_vhost #{new_resource.vhost}"
    execute cmdStr do
      Chef::Log.debug "rabbitmq_vhost_delete: #{cmdStr}"
      Chef::Log.info "Deleting RabbitMQ vhost '#{new_resource.vhost}'."
      new_resource.updated_by_last_action(true)
    end
  end
end
