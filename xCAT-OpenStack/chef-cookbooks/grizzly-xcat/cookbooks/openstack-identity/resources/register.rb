#
# Cookbook Name:: openstack-identity
# Resource:: register
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

actions :create_service, :create_endpoint, :create_tenant, :create_user, :create_role, :grant_role, :create_ec2_credentials

# In earlier versions of Chef the LWRP DSL doesn't support specifying
# a default action, so you need to drop into Ruby.
def initialize(*args)
  super
  @action = :create
end

Boolean = [TrueClass, FalseClass]

attribute :auth_uri, :kind_of => String
attribute :bootstrap_token, :kind_of => String

# Used by both :create_service and :create_endpoint
attribute :service_type, :kind_of => String, :equal_to => [ "image", "identity", "compute", "storage", "ec2", "volume", "object-store", "metering", "network" ]

# :create_service specific attributes
attribute :service_name, :kind_of => String
attribute :service_description, :kind_of => String

# :create_endpoint specific attributes
attribute :endpoint_region, :kind_of => String, :default => "RegionOne"
attribute :endpoint_adminurl, :kind_of => String
attribute :endpoint_internalurl, :kind_of => String
attribute :endpoint_publicurl, :kind_of => String

# Used by both :create_tenant and :create_user
attribute :tenant_name, :kind_of => String

# :create_tenant specific attributes
attribute :tenant_description, :kind_of => String
attribute :tenant_enabled, :kind_of => Boolean, :default => true

# :create_user specific attributes
attribute :user_name, :kind_of => String
attribute :user_pass, :kind_of => String
# attribute :user_email, :kind_of => String
attribute :user_enabled, :kind_of => Boolean, :default => true

# Used by :create_role and :grant_role specific attributes
attribute :role_name, :kind_of => String
