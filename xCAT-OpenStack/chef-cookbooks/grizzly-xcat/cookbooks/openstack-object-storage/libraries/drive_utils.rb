#
# Cookbook Name:: swift
# Library:: drive_utils
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

module DriveUtils
  def locate_disks(enum_expression, filter_expressions)
    candidate_disks = eval(enum_expression)
    candidate_expression = "candidate_disks.select{|candidate,info| (" +
      filter_expressions.map{|x| "(#{x})"}.join(" and ") + ")}"
    # TODO(mancdaz): fix this properly so the above works in the first place
    candidate_expression.gsub!(/\[\'removable\'\] = 0/, "['removable'].to_i == 0")
    drives = Hash[eval(candidate_expression)]
    Chef::Log.info("Using candidate drives: #{drives.keys.join(", ")}")
    drives.keys
  end
end

