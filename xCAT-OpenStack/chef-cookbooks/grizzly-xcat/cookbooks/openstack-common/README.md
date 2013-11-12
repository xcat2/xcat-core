Description
===========

This cookbook provides common setup recipes, helper methods and attributes that describe an OpenStack deployment as part of the OpenStack reference deployment Chef for OpenStack.

Requirements
============

* Chef 0.10.0 or higher required (for Chef environment use).

Cookbooks
---------

The following cookbooks are dependencies:

* apt
* database

Attributes
==========

Please see the extensive inline documentation in `attributes/default.rb` for descriptions
of all the settable attributes for this cookbook.

Note that all attributes are in the `default["openstack"]` "namespace"

Libraries
=========

This cookbook exposes a set of default library routines:

* `endpoint` -- Used to return a `::URI` object representing the named OpenStack endpoint
* `endpoints` -- Useful for operating on all OpenStack endpoints
* `db` -- Returns a Hash of information about a named OpenStack database
* `db_uri` -- Returns the SQLAlchemy RFC-1738 DB URI (see: http://rfc.net/rfc1738.html) for a named OpenStack database
* `db_create_with_user` -- Creates a database and database user for a named OpenStack database
* `secret` -- Returns the value of an encrypted data bag for a named OpenStack secret key and key-section
* `db_password` -- Ease-of-use helper that returns the decrypted database password for a named OpenStack database
* `service_password` -- Ease-of-use helper that returns the decrypted service password for named OpenStack service
* `user_password` -- Ease-of-use helper that returns the decrypted password for a Keystone user

Usage
-----

default
----

Installs/Configures common recipes

```json
"run_list": [
    "recipe[openstack-common]"
]
```

logging
----

Installs/Configures common logging

```json
"run_list": [
    "recipe[openstack-common::logging]"
]
```

The following are code examples showing the above library routines in action.
Remember when using the library routines exposed by this library to include
the Openstack routines in your recipe's `::Chef::Recipe` namespace, like so:

```ruby
class ::Chef::Recipe
  include ::Openstack
end
```

Example of using the `endpoint` routine:

```ruby
nova_api_ep = endpoint "compute-api"
::Chef::Log.info("Using Openstack Compute API endpoint at #{nova_api_ep.to_s}")

# Note that endpoint URIs may contain variable interpolation markers such
# as `%(tenant_id)s`, so you may need to decode them. Do so like this:

require "uri"

puts ::URI.decode nova_api_ap.to_s
```

Example of using the `db_password` and `db_uri` routine:

```ruby
db_pass = db_password "cinder"
db_user = node["cinder"]["db"]["user"]
sql_connection = db_uri "volume", db_user, db_pass

template "/etc/cinder/cinder.conf" do
  source "cinder.conf.erb"
  owner  node["cinder"]["user"]
  group  node["cinder"]["group"]
  mode   00644
  variables(
    "sql_connection" => sql_connection
  )
end
```

URI Operations
--------------

Use the `Openstack::uri_from_hash` routine to helpfully return a `::URI::Generic`
object for a hash that contains any of the following keys:

* `host`
* `uri`
* `port`
* `path`
* `scheme`

If the `uri` key is in the hash, that will be used as the URI, otherwise the URI will be
constructed from the various parts of the hash corresponding to the keys above.

```ruby
# Suppose node hash contains the following subhash in the :identity_service key:
# {
#   :host => 'identity.example.com',
#   :port => 5000,
#   :scheme => 'https'
# }
uri = ::Openstack::uri_from_hash(node[:identity_service])
# uri.to_s would == "https://identity.example.com:5000"
```

The routine will return nil if neither a `uri` or `host` key exists in the supplied hash.

Using the library without prefixing with ::Openstack
----------------------------------------------------

Don't like prefixing calls to the library's routines with `::Openstack`? Do this:

```ruby
class ::Chef::Recipe
  include ::Openstack
end
```

in your recipe.

Testing
=====

This cookbook uses [bundler](http://gembundler.com/), [berkshelf](http://berkshelf.com/), and [strainer](https://github.com/customink/strainer) to isolate dependencies and run tests.

Tests are defined in Strainerfile.

To run tests:

    $ bundle install # install gem dependencies
    $ bundle exec berks install # install cookbook dependencies
    $ bundle exec strainer test # run tests

License and Author
==================

|                      |                                                    |
|:---------------------|:---------------------------------------------------|
| **Author**           |  Jay Pipes (<jaypipes@att.com>)                    |
| **Author**           |  John Dewey (<jdewey@att.com>)                     |
| **Author**           |  Matt Ray (<matt@opscode.com>)                     |
| **Author**           |  Craig Tracey (<craigtracey@gmail.com>)            |
| **Author**           |  Sean Gallagher (<sean.gallagher@att.com>)         |
| **Author**           |  Ionut Artarisi (<iartarisi@suse.cz>)              |
|                      |                                                    |
| **Copyright**        |  Copyright (c) 2012-2013, AT&T Services, Inc.      |
| **Copyright**        |  Copyright (c) 2013, Opscode, Inc.                 |
| **Copyright**        |  Copyright (c) 2013, Craig Tracey                  |
| **Copyright**        |  Copyright (c) 2013, SUSE Linux GmbH               |

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
