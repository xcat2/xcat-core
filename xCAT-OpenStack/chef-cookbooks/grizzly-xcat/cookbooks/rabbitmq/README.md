rabbitmq Cookbook
=================
This is a cookbook for managing RabbitMQ with Chef. It is intended for 2.6.1 or later releases.

**Version 2.0 Changes**

The 2.0 release of the cookbook defaults to using the latest version available from RabbitMQ.com via direct download of the package. This was done to simplify the installation options to either distro package or direct download. The attributes `use_apt` and `use_yum` have been removed as have the `apt` and `yum` cookbook dependencies. The user LWRP action `:set_user_tags` was changed to `:set_tags` for consistency with other actions.


Requirements
------------
This cookbook depends on the `erlang` cookbook.

Please refer to the [TESTING file](TESTING.md) to see the currently (and passing) tested platforms. The release was tested with (rabbitmq.com/distro version):
- CentOS 5.9: 3.1.5 (distro release unsupported)
- CentOS 6.4: 3.1.5/2.6.1 (no lwrps support)
- Fedora 18: 3.1.5 (distro release unsupported)
- Ubuntu 10.04: 3.1.5 (distro release unsupported)
- Ubuntu 12.04: 3.1.5/2.7.1 (no lwrps support)
- Ubuntu 13.04: 3.1.5/3.0.2


Recipes
-------
### default
Installs `rabbitmq-server` from RabbitMQ.com via direct download of the installation package or using the distribution version. Depending on your distribution, the provided version may be quite old so they are disabled by default. If you want to use the distro version, set the attribute `['rabbitmq']['use_distro_version']` to `true`. You may override the download URL attribute `['rabbitmq']['package']` if you wish to use a local mirror.

The cluster recipe is now combined with the default and will now auto-cluster. Set the `['rabbitmq']['cluster']` attribute to `true`, `['rabbitmq']['cluster_disk_nodes']` array of `node@host` strings that describe which you want to be disk nodes and then set an alphanumeric string for the `erlang_cookie`.

To enable SSL turn `ssl` to `true` and set the paths to your cacert, cert and key files.

### mgmt_console
Installs the `rabbitmq_management` and `rabbitmq_management_visualiser` plugins.
To use https connection to management console, turn `['rabbitmq']['web_console_ssl']` to true. The SSL port for web management console can be configured by setting attribute `['rabbitmq']['web_console_ssl_port']`, whose default value is 15671.

### plugin_management
Enables any plugins listed in the `node['rabbitmq']['enabled_plugins']` and disables any listed in `node['rabbitmq'][disabled_plugins']` attributes.

### policy_management
Enables any policies listed in the `node['rabbitmq'][policies]` and disables any listed in `node['rabbitmq'][disabled_policies]` attributes.

### user_management
Enables any users listed in the `node['rabbitmq']['enabled_users]` and disables any listed in `node['rabbitmq'][disabled_users]` attributes.

### virtualhost_management
Enables any vhosts listed in the `node['rabbitmq'][virtualhosts]` and disables any listed in `node['rabbitmq'][disabled_virtualhosts]` attributes.


Resources/Providers
-------------------
There are 4 LWRPs for interacting with RabbitMQ.

### plugin
Enables or disables a rabbitmq plugin. Plugins are not supported for releases prior to 2.7.0.

- `:enable` enables a `plugin`
- `:disable` disables a `plugin`

#### Examples
```ruby
rabbitmq_plugin "rabbitmq_stomp" do
  action :enable
end
```

```ruby
rabbitmq_plugin "rabbitmq_shovel" do
  action :disable
end
```

### policy
sets or clears a rabbitmq policy.

- `:set` sets a `policy`
- `:clear` clears a `policy`
- `:list` lists `policy`s

#### Examples
```ruby
rabbitmq_policy "ha-all" do
  pattern "^(?!amq\\.).*"
  params {"ha-mode"=>"all"}
  priority 1
  action :set
end
```

```ruby
rabbitmq_policy "ha-all" do
  action :clear
end
```

### user
Adds and deletes users, fairly simplistic permissions management.

- `:add` adds a `user` with a `password`
- `:delete` deletes a `user`
- `:set_permissions` sets the `permissions` for a `user`, `vhost` is optional
- `:clear_permissions` clears the permissions for a `user`
- `:set_tags` set the tags on a user
- `:clear_tags` clear any tags on a user
- `:change_password` set the `password` for a `user`

#### Examples
```ruby
rabbitmq_user "guest" do
  action :delete
end
```

```ruby
rabbitmq_user "nova" do
  password "sekret"
  action :add
end
```

```ruby
rabbitmq_user "nova" do
  vhost "/nova"
  permissions ".* .* .*"
  action :set_permissions
end
```

```ruby
rabbitmq_user "joe" do
  tag "admin,lead"
  action :set_tags
end
```

### vhost
Adds and deletes vhosts.

- `:add` adds a `vhost`
- `:delete` deletes a `vhost`

#### Examples
``` ruby
rabbitmq_vhost "/nova" do
  action :add
end
```


Limitations
-----------
For an already running cluster, these actions still require manual intervention:
- changing the :erlang_cookie
- turning :cluster from true to false


License & Authors
-----------------
- Author:: Benjamin Black <b@b3k.us>
- Author:: Daniel DeLeo <dan@kallistec.com>
- Author:: Matt Ray (<matt@opscode.com>)

```text
Copyright (c) 2009-2013, Opscode, Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```
