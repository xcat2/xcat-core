#
# Cookbook Name:: swift
# Resource:: ring_script
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

require "pp"

def generate_script
  # need to load and parse the existing rings.
  ports = { "object" => "6000", "container" => "6001", "account" => "6002" }
  must_rebalance = false

  ring_path = @new_resource.ring_path
  ring_data = { :raw => {}, :parsed => {}, :in_use => {} }
  disk_data = {}
  dirty_cluster_reasons = []

  [ "account", "container", "object" ].each do |which|
    ring_data[:raw][which] = nil

    if ::File.exist?("#{ring_path}/#{which}.builder")
      IO.popen("su swift -c 'swift-ring-builder #{ring_path}/#{which}.builder'") do |pipe|
        ring_data[:raw][which] = pipe.readlines
        # Chef::Log.debug("#{ which.capitalize } Ring data: #{ring_data[:raw][which]}")
        ring_data[:parsed][which] = parse_ring_output(ring_data[:raw][which])

        node.set["swift"]["state"]["ring"][which] = ring_data[:parsed][which]
      end
    else
      Chef::Log.info("#{which.capitalize} ring builder files do not exist!")
    end

    # collect all the ring data, and note what disks are in use.  All I really
    # need is a hash of device and id

    ring_data[:in_use][which] ||= {}
    if ring_data[:parsed][which][:hosts]
      ring_data[:parsed][which][:hosts].each do |ip, dev|
        dev.each do |dev_id, devhash|
          ring_data[:in_use][which].store(devhash[:device], devhash[:id])
        end
      end
    end

    Chef::Log.debug("#{which.capitalize} Ring - In use: #{PP.pp(ring_data[:in_use][which],dump='')}")

    # figure out what's present in the cluster
    disk_data[which] = {}
    disk_state,_,_ = Chef::Search::Query.new.search(:node,"chef_environment:#{node.chef_environment} AND roles:swift-#{which}-server")

    # for a running track of available disks
    disk_data[:available] ||= {}
    disk_data[:available][which] ||= {}

    disk_state.each do |swiftnode|
      if swiftnode[:swift][:state] and swiftnode[:swift][:state][:devs]
        swiftnode[:swift][:state][:devs].each do |k,v|
          disk_data[which][v[:ip]] = disk_data[which][v[:ip]] || {}
          disk_data[which][v[:ip]][k] = {}
          v.keys.each { |x| disk_data[which][v[:ip]][k].store(x,v[x]) }

          if swiftnode[:swift].has_key?("#{which}-zone")
            disk_data[which][v[:ip]][k]["zone"]=swiftnode[:swift]["#{which}-zone"]
          elsif swiftnode[:swift].has_key?("zone")
            disk_data[which][v[:ip]][k]["zone"]=swiftnode[:swift]["zone"]
          else
            raise "Node #{swiftnode[:hostname]} has no zone assigned"
          end

          disk_data[:available][which][v[:mountpoint]] = v[:ip]

          if not v[:mounted]
            dirty_cluster_reasons << "Disk #{v[:name]} (#{v[:uuid]}) is not mounted on host #{v[:ip]} (#{swiftnode[:hostname]})"
          end
        end
      end
    end
    Chef::Log.debug("#{which.capitalize} Ring - Avail:  #{PP.pp(disk_data[:available][which],dump='')}")
  end

  # Have the raw data, now bump it together and drop the script

  s = "#!/bin/bash\n\n# This script is automatically generated.\n"
  s << "# Running it will likely blow up your system if you don't review it carefully.\n"
  s << "# You have been warned.\n\n"
  if not node["swift"]["auto_rebuild_rings"]
    s << "if [ \"$1\" != \"--force\" ]; then\n"
    s << "  echo \"Auto rebuild rings is disabled, so you must use --force to generate rings\"\n"
    s << "  exit 0\n"
    s << "fi\n\n"
  end

  # Chef::Log.debug("#{PP.pp(disk_data, dump='')}")

  new_disks = {}
  missing_disks = {}
  new_servers = []

  [ "account", "container", "object" ].each do |which|
    # remove available disks that are already in the ring
    new_disks[which] = disk_data[:available][which].reject{ |k,v| ring_data[:in_use][which].has_key?(k) }

    # find all in-ring disks that are not in the cluster
    missing_disks[which] = ring_data[:in_use][which].reject{ |k,v| disk_data[:available][which].has_key?(k) }

    Chef::Log.debug("#{which.capitalize} Ring - Missing:  #{PP.pp(missing_disks[which],dump='')}")
    Chef::Log.debug("#{which.capitalize} Ring - New:  #{PP.pp(new_disks[which],dump='')}")

    s << "\n# -- #{which.capitalize} Servers --\n\n"
    disk_data[which].keys.sort.each do |ip|
      s << "# #{ip}\n"
      disk_data[which][ip].keys.sort.each do |k|
        v = disk_data[which][ip][k]
        s << "#  " +  v.keys.sort.select{|x| ["ip", "device", "uuid"].include?(x)}.collect{|x| v[x] }.join(", ")
        if new_disks[which].has_key?(v["mountpoint"])
          s << " (NEW!)"
          new_servers << ip unless new_servers.include?(ip)
        end
        s << "\n"
      end
    end

    # for all those servers, check if they are already in the ring.  If not,
    # then we need to add them to the ring.  For those that *were* in the
    # ring, and are no longer in the ring, we need to delete those.

    s << "\n"

    # add the new disks
    disk_data[which].keys.sort.each do |ip|
      disk_data[which][ip].keys.sort.each do |uuid|
        v = disk_data[which][ip][uuid]
        if new_disks[which].has_key?(v['mountpoint'])
          s << "swift-ring-builder #{ring_path}/#{which}.builder add z#{v['zone']}-#{v['ip']}:#{ports[which]}/#{v['mountpoint']} #{v['size']}\n"
          must_rebalance = true
        end
      end
    end

    # remove the disks -- sort to ensure consistent order
    missing_disks[which].keys.sort.each do |mountpoint|
      diskinfo=ring_data[:parsed][which][:hosts].select{|k,v| v.has_key?(mountpoint)}.collect{|_,v| v[mountpoint]}[0]
      Chef::Log.debug("Missing diskinfo: #{PP.pp(diskinfo,dump='')}")
      description = Hash[diskinfo.select{|k,v| [:zone, :ip, :device].include?(k)}].collect{|k,v| "#{k}: #{v}" }.join(", ")
      s << "# #{description}\n"
      s << "swift-ring-builder #{ring_path}/#{which}.builder remove d#{missing_disks[which][mountpoint]}\n"
      must_rebalance = true
    end

    s << "\n"

    if(must_rebalance)
      s << "swift-ring-builder #{ring_path}/#{which}.builder rebalance\n\n\n"
    else
      s << "# #{which.capitalize} ring has no outstanding changes!\n\n"
    end

    # we'll only rebalance if we meet the minimums for new adds
    if node["swift"].has_key?("wait_for")
      if node["swift"]["wait_for"] > new_servers.count
        Chef::Log.debug("New servers, but not enough to force a rebalance")
        must_rebalance = false
      end
    end
  end
  [ s, must_rebalance ]
end

# Parse the raw output of swift-ring-builder
def parse_ring_output(ring_data)
  output = { :state => {} }

  ring_data.each do |line|
    if line =~ /build version ([0-9]+)/
      output[:state][:build_version] = $1
    elsif line =~ /^Devices:\s+id\s+region\s+zone\s+/
      next
    elsif line =~ /^Devices:\s+id\s+zone\s+/
      next
    elsif line =~ /^\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+\.\d+\.\d+\.\d+)\s+(\d+)\s+(\S+)\s+([0-9.]+)\s+(\d+)\s+([-0-9.]+)\s*$/
      output[:hosts] ||= {}
      output[:hosts][$3] ||= {}

      output[:hosts][$3][$5] = {}

      output[:hosts][$3][$5][:id] = $1
      output[:hosts][$3][$5][:region] = $2
      output[:hosts][$3][$5][:zone] = $3
      output[:hosts][$3][$5][:ip] = $4
      output[:hosts][$3][$5][:port] = $5
      output[:hosts][$3][$5][:device] = $6
      output[:hosts][$3][$5][:weight] = $7
      output[:hosts][$3][$5][:partitions] = $8
      output[:hosts][$3][$5][:balance] = $9
    elsif line =~ /^\s+(\d+)\s+(\d+)\s+(\d+\.\d+\.\d+\.\d+)\s+(\d+)\s+(\S+)\s+([0-9.]+)\s+(\d+)\s+([-0-9.]+)\s*$/
      output[:hosts] ||= {}
      output[:hosts][$3] ||= {}

      output[:hosts][$3][$5] = {}

      output[:hosts][$3][$5][:id] = $1
      output[:hosts][$3][$5][:zone] = $2
      output[:hosts][$3][$5][:ip] = $3
      output[:hosts][$3][$5][:port] = $4
      output[:hosts][$3][$5][:device] = $5
      output[:hosts][$3][$5][:weight] = $6
      output[:hosts][$3][$5][:partitions] = $7
      output[:hosts][$3][$5][:balance] = $8
    elsif line =~ /(\d+) partitions, (\d+\.\d+) replicas, (\d+) regions, (\d+) zones, (\d+) devices, (\d+\.\d+) balance$/
      output[:state][:partitions] = $1
      output[:state][:replicas] = $2
      output[:state][:regions] = $3
      output[:state][:zones] = $4
      output[:state][:devices] = $5
      output[:state][:balance] = $6
    elsif line =~ /(\d+) partitions, (\d+) replicas, (\d+) zones, (\d+) devices, (\d+\.\d+) balance$/
      output[:state][:partitions] = $1
      output[:state][:replicas] = $2
      output[:state][:zones] = $3
      output[:state][:devices] = $4
      output[:state][:balance] = $5
    elsif line =~ /^The minimum number of hours before a partition can be reassigned is (\d+)$/
      output[:state][:min_part_hours] = $1
    else
      raise "Cannot parse ring builder output for #{line}"
    end
  end

  output
end

action :ensure_exists do
  Chef::Log.debug("Ensuring #{new_resource.name}")
  new_resource.updated_by_last_action(false)
  s,must_update = generate_script

  script_file = File new_resource.name do
    owner new_resource.owner
    group new_resource.group
    mode new_resource.mode
    content s
  end

  script_file.run_action(:create)
  new_resource.updated_by_last_action(must_update)
end
