#
# Cookbook Name:: swift
# Provider:: mounts
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

require "chef/util/file_edit"

action :ensure_exists do
  proposed_devices = @new_resource.devices
  path = @new_resource.name
  dev_info = {}

  Chef::Log.info("IN MOUNTS")

  new_resource.updated_by_last_action(false)

  # walk through the devices, gathering information
  proposed_devices.each do |device|
    next if !::File.exists?("/dev/#{device}")

    info = {}
    info["device"] = device
    info["ip"] = @new_resource.ip
    info["format"] = @new_resource.format
    info["uuid"] = `blkid /dev/#{device} -s UUID -o value`.strip
    info["mountpoint"] = info["uuid"].split("-").join("")
    info["mounted"] = system("mount | grep '#{path}/#{info["mountpoint"]}\'")
    info["size"] = `sfdisk -s /dev/#{device}`.to_i / 1024

    next if (info["uuid"] == '')

    dev_info[info["uuid"]] = info
  end

  Chef::Log.info("Physical Inventory:")
  dev_info.each do |_,v|
    Chef::Log.info("Device: #{v['device']}, UUID: #{v['uuid']}, Mounted: #{v['mounted']}, Format: #{v['format']}")
  end

  # make sure we have a "path"
  Directory(path) do
    group "swift"
    owner "swift"
    recursive true
  end.run_action(:create)

  # find what should be mounted, and what IS mounted
  mounts=node["filesystem"].inject({}) { |hsh, (k,v)| hsh.merge(v["mount"] => k) }
  valid_mounts = dev_info.inject([]) {|ary, (_,v)| ary << "#{path}/#{v['mountpoint']}"}
  mountpoints = Dir.new(path).reject {|x| x[/^\./] }.collect { |d| "#{path}/#{d}" }
  inverted_mounts = dev_info.inject({}) {|hsh,(k,v)| hsh.merge({v["mountpoint"] => v.merge("uuid" => k)})}
  fstabs=::File.readlines("/etc/fstab").inject({}) do |hash,line|
    line = line.split("#")[0].split()
    Chef::Log.info("#{line[0]} ... #{line[1]}")
    hash.merge(line[1] => line[0])
  end.reject { |k,v| !k or !v or !k.length or !v.length }

  Chef::Log.info("Mounts: #{mounts}")
  Chef::Log.info("Valid Mounts: #{valid_mounts}")
  Chef::Log.info("Mountpoints: #{mountpoints}")
  Chef::Log.info("Fstabs: #{fstabs}")

  # mounts in /srv/node that shouldn't be there
  (mounts.keys.select{|x| x and x[/^#{path}/]} - valid_mounts).each do |dev|
    Chef::Log.info("Unmounting #{dev}")
    system("umount #{dev}") if system("mount | grep '#{dev}'")
    new_resource.updated_by_last_action(true)
  end

  # fstab entries that don't need to be there anymore
  (fstabs.keys.select {|k| k.start_with? path}  - valid_mounts).each do |dev|
    fe = Chef::Util::FileEdit.new("/etc/fstab")
    fe.search_file_delete_line(Regexp.new(dev.gsub("/","\/")))
    fe.write_file
    new_resource.updated_by_last_action(true)
  end

  # directories/mountpoints in /srv/node that are now useless
  (mountpoints - valid_mounts).each do |mountpoint|
    Chef::Log.info("rmdiring #{mountpoint}")
    begin
      Dir.rmdir(mountpoint)
    rescue SystemCallError
      Chef::Log.info("Directory #{mountpoint} appears non-empty")
    end
    new_resource.updated_by_last_action(true)
  end

  # new, unmounted devices
  (valid_mounts - mounts.keys).each do |mountpoint|
    info = inverted_mounts[mountpoint.gsub("#{path}/","")]

    Chef::Log.info("mounting #{mountpoint} (#{info['device']})")

    mount_path = "#{path}/#{info['mountpoint']}"

    Directory(mount_path) do
      group "swift"
      owner "swift"
      recursive true
    end.run_action(:create)

    case info['format']
    when 'ext4'
      mount_options = "noatime,nodiratime,nobarrier,user_xattr"
    when 'xfs'
      case node["platform"]
        when "ubuntu","debian"
          mount_options = "noatime,nodiratime,nobarrier,logbufs=8,nobootwait"
        else
          mount_options = "noatime,nodiratime,nobarrier,logbufs=8"
      end
    end

    mt = Mount(mount_path) do
      device info['uuid']
      device_type :uuid
      options mount_options
      dump 0
      fstype info['format']
      action :nothing
    end

    if not fstabs.has_key?(mount_path)
      # then its a brand-new drive, freshly formatted
      Chef::Log.info("Mounting new device #{info['mountpoint']}")
      mt.run_action(:enable)
      mt.run_action(:mount)
    end

    new_resource.updated_by_last_action(true)
  end

  dev_info.reject { |k,v| v["mounted"] }.keys.each do |uuid|
    dev_info[uuid]["mounted"] = system("mount | grep '#{path}/#{dev_info[uuid]["mountpoint"]}\'")
  end

  if @new_resource.publish_attributes and dev_info != {}
    dev_info.each do |k,v|
      node.set["swift"]["state"]["devs"][k] = {
        :device => v["device"],
        :size => v["size"],
        :uuid => v["uuid"],
        :mounted => v["mounted"],
        :format => v["format"],
        :mountpoint => v["mountpoint"],
        :ip => v["ip"]
      }
    end
  end
end

