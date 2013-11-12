#
# Cookbook Name:: openstack-common
# library:: parse
#
# Copyright 2013, Craig Tracey <craigtracey@gmail.com>
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

  # The current state of (at least some) OpenStack CLI tools do not provide a
  # mechanism for outputting data in formats other than PrettyTable output.
  # Therefore this function is intended to parse PrettyTable output into a
  # usable array of hashes. Similarly, it will flatten Property/Value tables
  # into a single element array.
  # table - the raw PrettyTable output of the CLI command
  # output - array of hashes representing the data.
  def prettytable_to_array table
    ret = []
    return ret if table == nil
    indicies = []
    (table.split(/$/).collect{|x| x.strip}).each { |line|
      unless line.start_with?('+--') or line.empty?
        cols = line.split('|').collect{|x| x.strip}
        cols.shift
        if indicies == []
          indicies = cols
          next
        end
        newobj = {}
        cols.each { |val|
          newobj[indicies[newobj.length]] = val
        }
        ret.push(newobj)
      end
    }

    # this kinda sucks, but some prettytable data comes
    # as Property Value pairs. If this is the case, then
    # flatten it as expected.
    newobj = {}
    if indicies == ['Property', 'Value']
      ret.each { |x|
        newobj[x['Property']] = x['Value']
      }
      [newobj]
    else
      ret
    end
  end

end
