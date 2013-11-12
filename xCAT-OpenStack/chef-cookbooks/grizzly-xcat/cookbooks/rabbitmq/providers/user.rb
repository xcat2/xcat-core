#
# Cookbook Name:: rabbitmq
# Provider:: user
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

def user_exists?(name)
  cmdStr = "rabbitmqctl -q list_users |grep '^#{name}\\b'"
  cmd = Mixlib::ShellOut.new(cmdStr)
  cmd.environment['HOME'] = ENV.fetch('HOME', '/root')
  cmd.run_command
  Chef::Log.debug "rabbitmq_user_exists?: #{cmdStr}"
  Chef::Log.debug "rabbitmq_user_exists?: #{cmd.stdout}"
  begin
    cmd.error!
    true
  rescue
    false
  end
end

def user_has_tag?(name, tag)
  tag = '"\[\]"' if tag.nil?
  cmdStr = "rabbitmqctl -q list_users | grep \"^#{name}\\b\" | grep #{tag}"
  cmd = Mixlib::ShellOut.new(cmdStr)
  cmd.environment['HOME'] = ENV.fetch('HOME', '/root')
  cmd.run_command
  Chef::Log.debug "rabbitmq_user_has_tag?: #{cmdStr}"
  Chef::Log.debug "rabbitmq_user_has_tag?: #{cmd.stdout}"
  begin
    cmd.error!
    true
  rescue Exception => e
    false
  end
end

# does the user have the rights listed on the vhost?
# empty perm_list means we're checking for any permissions
def user_has_permissions?(name, vhost, perm_list = nil)
  vhost = '/' if vhost.nil?
  cmdStr = "rabbitmqctl -q list_user_permissions #{name} | grep \"^#{vhost}\\b\""
  cmd = Mixlib::ShellOut.new(cmdStr)
  cmd.environment['HOME'] = ENV.fetch('HOME', '/root')
  cmd.run_command
  Chef::Log.debug "rabbitmq_user_has_permissions?: #{cmdStr}"
  Chef::Log.debug "rabbitmq_user_has_permissions?: #{cmd.stdout}"
  Chef::Log.debug "rabbitmq_user_has_permissions?: #{cmd.exitstatus}"
  if perm_list.nil? && cmd.stdout.empty? #looking for empty and found nothing
    Chef::Log.debug "rabbitmq_user_has_permissions?: no permissions found"
    return false
  end
  if perm_list == cmd.stdout.split.drop(1) #existing match search
    Chef::Log.debug "rabbitmq_user_has_permissions?: matching permissions already found"
    return true
  end
  Chef::Log.debug "rabbitmq_user_has_permissions?: permissions found but do not match"
  return false
end

action :add do
  unless user_exists?(new_resource.user)
    if new_resource.password.nil? || new_resource.password.empty?
      Chef::Application.fatal!("rabbitmq_user with action :add requires a non-nil/empty password.")
    end
    # To escape single quotes in a shell, you have to close the surrounding single quotes, add
    # in an escaped single quote, and then re-open the original single quotes.
    # Since this string is interpolated once by ruby, and then a second time by the shell, we need
    # to escape the escape character ('\') twice.  This is why the following is such a mess
    # of leaning toothpicks:
    new_password = new_resource.password.gsub("'", "'\\\\''")
    cmdStr = "rabbitmqctl add_user #{new_resource.user} '#{new_password}'"
    execute "rabbitmqctl add_user #{new_resource.user}" do
      command cmdStr
      Chef::Log.info "Adding RabbitMQ user '#{new_resource.user}'."
      new_resource.updated_by_last_action(true)
    end
  end
end

action :delete do
  if user_exists?(new_resource.user)
    cmdStr = "rabbitmqctl delete_user #{new_resource.user}"
    execute cmdStr do
      Chef::Log.debug "rabbitmq_user_delete: #{cmdStr}"
      Chef::Log.info "Deleting RabbitMQ user '#{new_resource.user}'."
      new_resource.updated_by_last_action(true)
    end
  end
end

action :set_permissions do
  if !user_exists?(new_resource.user)
    Chef::Application.fatal!("rabbitmq_user action :set_permissions fails with non-existant '#{new_resource.user}' user.")
  end
  perm_list = new_resource.permissions.split
  unless user_has_permissions?(new_resource.user, new_resource.vhost, perm_list)
    vhostOpt = "-p #{new_resource.vhost}" unless new_resource.vhost.nil?
    cmdStr = "rabbitmqctl set_permissions #{vhostOpt} #{new_resource.user} \"#{perm_list.join("\" \"")}\""
    execute cmdStr do
      Chef::Log.debug "rabbitmq_user_set_permissions: #{cmdStr}"
      Chef::Log.info "Setting RabbitMQ user permissions for '#{new_resource.user}' on vhost #{new_resource.vhost}."
      new_resource.updated_by_last_action(true)
    end
  end
end

action :clear_permissions do
  if !user_exists?(new_resource.user)
    Chef::Application.fatal!("rabbitmq_user action :clear_permissions fails with non-existant '#{new_resource.user}' user.")
  end
  if user_has_permissions?(new_resource.user, new_resource.vhost)
    vhostOpt = "-p #{new_resource.vhost}" unless new_resource.vhost.nil?
    cmdStr = "rabbitmqctl clear_permissions #{vhostOpt} #{new_resource.user}"
    execute cmdStr do
      Chef::Log.debug "rabbitmq_user_clear_permissions: #{cmdStr}"
      Chef::Log.info "Clearing RabbitMQ user permissions for '#{new_resource.user}' from vhost #{new_resource.vhost}."
      new_resource.updated_by_last_action(true)
    end
  end
end

action :set_tags do
  if !user_exists?(new_resource.user)
    Chef::Application.fatal!("rabbitmq_user action :set_tags fails with non-existant '#{new_resource.user}' user.")
  end
  unless user_has_tag?(new_resource.user, new_resource.tag)
    cmdStr = "rabbitmqctl set_user_tags #{new_resource.user} #{new_resource.tag}"
    execute cmdStr do
      Chef::Log.debug "rabbitmq_user_set_tags: #{cmdStr}"
      Chef::Log.info "Setting RabbitMQ user '#{new_resource.user}' tags '#{new_resource.tag}'"
      new_resource.updated_by_last_action(true)
    end
  end
end

action :clear_tags do
  if !user_exists?(new_resource.user)
    Chef::Application.fatal!("rabbitmq_user action :clear_tags fails with non-existant '#{new_resource.user}' user.")
  end
  unless user_has_tag?(new_resource.user, '"\[\]"')
    cmdStr = "rabbitmqctl set_user_tags #{new_resource.user}"
    execute cmdStr do
      Chef::Log.debug "rabbitmq_user_clear_tags: #{cmdStr}"
      Chef::Log.info "Clearing RabbitMQ user '#{new_resource.user}' tags."
      new_resource.updated_by_last_action(true)
    end
  end
end

action :change_password do
  if user_exists?(new_resource.user)
    cmdStr = "rabbitmqctl change_password #{new_resource.user} #{new_resource.password}"
    execute cmdStr do
      Chef::Log.debug "rabbitmq_user_change_password: #{cmdStr}"
      Chef::Log.info "Editing RabbitMQ user '#{new_resource.user}'."
      new_resource.updated_by_last_action(true)
    end
  end
end
