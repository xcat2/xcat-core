#
# Copyright 2011, Dell
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
# Author: andi abes
#

require 'chef/mixin/shell_out'
include Chef::Mixin::ShellOut

def load_current_resource
  dev_name = @new_resource.name
  @current = Chef::Resource::OpenstackObjectStorageDisk.new(dev_name)

  parted_partition_parse  dev_name
  parts = @current.part()

  if not @current.blocks
    # parted didn't return anything -- empty disk.
    # get size from sfdisk
    sfdisk_get_size(dev_name)
  end

  Chef::Log.info("About to print partition table")

  s = <<EOF
current state for dev #{dev_name}
  Size in 1K blocks: #{@current.blocks}
EOF

  Chef::Log.info("Printing partition table")

  num = 0
  parts.each { | p |
    s << "partition " << num
    s << " start/end/size (1k): #{p[:start]}/#{p[:end]}/#{p[:size]}"
    s << " type: #{p[:type]}"
    s << "\n"
    num+=1
  } if !parts.nil?
  Chef::Log.info(s)
end

=begin
sample output
# sfdisk /dev/sdb -g
/dev/sdb: 261 cylinders, 255 heads, 63 sectors/track
=end
def sfdisk_get_size(dev_name)
  out = %x{sfdisk #{dev_name} -s}
  Chef::Log.info("updating geo using sfdisk: #{out}")

  # sfdisk sees the world as 1k blocks
  @current.blocks(out.to_i)
end

def parted_partition_parse(dev_name)
  Chef::Log.debug("reading partition table for #{dev_name}")
=begin
Run parted to get basic info about the disk
sample output:
~# parted -m -s /dev/sda unit b print
BYT;
/dev/vda:8589934592B:virtblk:512:512:msdos:Virtio Block Device;
1:1048576B:8589934591B:8588886016B:ext3::;
=end
  pipe= IO.popen("parted -m -s #{dev_name} unit b print") # this can return 1, but it's ok (if no partition table present, we'll create it)
  result = pipe.readlines
  parted_parse_results result
end

def parted_parse_results(input)
  Chef::Log.debug("read:" + input.inspect)
  input = input.to_a
  part_tab = []
  catch (:parse_error) do
    line = input.shift # Error or BYT;
    throw :parse_error if line =~ /^Error:/

    line = input.shift
    throw :parse_error unless line =~ /\/dev\/([^\/]+):([0-9]+)B:(.*):.*$/

    dev = Regexp.last_match(1)
    blocks = Regexp.last_match(2).to_i / 1024

    if(@current.blocks and @current.blocks != blocks)
      throw "Our disk size changed.  Expecting: #{@current.blocks}, got #{blocks}"
    end

    @current.blocks(blocks)

    input.each { |line|
      # 1:1048576B:8589934591B:8588886016B:ext3::;

      throw :parse_error unless line =~ /([0-9]):([0-9]+)B:([0-9]+)B:([0-9]+)B:(.*):(.*):(.*);$/
      part_num = Regexp.last_match(1).to_i
      part_info = {
            :num => part_num,
            :start => Regexp.last_match(2).to_i / 1024,
            :end => Regexp.last_match(3).to_i / 1024,
            :size => Regexp.last_match(4).to_i / 1024,
            :type => Regexp.last_match(5),
            :system => Regexp.last_match(6),
            :flags => Regexp.last_match(7) }
      part_tab << part_info
    }
  end

  @current.part(part_tab)
  part_tab
end

action :list do
  Chef::Log.info("at some point there'll be a list")
end

####
# compare the requested partition table parameters to what exists
# if differences found - remove all current partitions, and create new ones.
# An existing partition is considered a match if:
#  - it has the same serial # (1,2,3)
#  - it has the same size
#
# We also want to start to partition at 1M to be correctly aligned
# even due to 4K sector size and controller stripe sizes.
#
# Plus, then parted doesn't bitch every time you run it.

action :ensure_exists do
  Chef::Log.info("Entering :ensure_exists")

  req = @new_resource.part
  cur = @current.part
  dev_name = @new_resource.name
  update = false

  recreate, delete_existing  = false

  disk_blocks = @current.blocks #1k blocks

  if (cur.nil?)
    recreate = true;
  else
    idx = 0
    current_block=0

    Chef::Log.info("Checking partition #{idx}")

    req.each { |params|
      if (cur[idx].nil?)
        recreate = true
        Chef::Log.info("no current #{idx}")
        next
      end

      req_size = params[:size]   # size in Mb - convert to blocks
      if (req_size == :remaining)
        req_size = disk_blocks - current_block
      else
        req_size = req_size * 1024
      end

      cur_size = cur[idx][:size]

      cur_min, cur_max = req_size*0.9, req_size*1.1
      if !(cur_size > cur_min and cur_size < cur_max)
        recreate = true
      end

      current_block += cur[idx][:size]
      Chef::Log.info("partition #{idx} #{(recreate ? 'differs' : 'is same')}: #{cur_size}/#{req_size}")
      idx+=1
    }
  end

  if !recreate
    Chef::Log.info("partition table matches - not recreating")
  else
    ### make sure to ensure that there are no mounted
    ### filesystems on the device
    re = /^(#{Regexp.escape(dev_name)}[0-9]+)/
    mounted = []
    shell_out!("mount").stdout.each_line { |line|
      md = re.match(line)
      next unless md
      mounted << md[1]
    }
    mounted.each { |m|
      Chef::Log.info("unmounting #{m}")
      shell_out!("umount #{m}")
    }

    # Nuke current partition table.
    execute "create new partition table" do
      command "parted -s -m #{dev_name} mktable gpt"
    end

    # create new partitions
    idx = 0
    req.each { | params |
      start_block = 0

      if idx == 0
        start_block = "1M"
      end

      if (params[:size] == :remaining)
        requested_size = "100%"
      else
        requested_size = "#{params[:size]}M"
      end

      s = "parted -m -s #{dev_name} "
      s << "mkpart #{idx} #{start_block} #{requested_size}" # #{params[:type]}
      Chef::Log.info("creating new partition #{idx+1} with:" + s)
      execute "creating partition #{idx}" do
        command s
      end
      idx+=1

    }
    update = true
  end

  # walk through the partitions and enforce disk format
  idx=1
  req.each do |params|
    device = "#{dev_name}#{idx}"
    Chef::Log.info("Checking #{device}")

    if ::File.exist?(device)
      # FIXME: check the format on the file system.  This should be
      # handled by a disk format provider.  Maybe the xfs/btrfs/etc
      # providers?
      Chef::Log.info("Testing file system on #{device} for type #{params[:type]}")

      case params[:type]
      when "xfs"
        if not system("xfs_admin -l #{device}")
          Mixlib::ShellOut.new("mkfs.xfs -f -i size=512 #{device}").run_command
          update = true
        end
      when "ext4"
        if not system("tune2fs -l #{device} | grep \"Filesystem volume name:\" | awk \'{print $4}\' | grep -v \"<none>\"")
          Mixlib::ShellOut.new("mkfs.ext4 #{device}").run_command
          update = true
        end
      end
    end
  end
  new_resource.updated_by_last_action(update)
end

