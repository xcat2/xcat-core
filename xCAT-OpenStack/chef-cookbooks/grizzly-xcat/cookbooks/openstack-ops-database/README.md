# Description #

This cookbook provides a reference example of database configuration for the OpenStack **Grizzly** reference deployment provided by Chef for OpenStack. It currently supports MySQL and will soon support PostgreSQL.

# Requirements #

Chef 11 with Ruby 1.9.x required.

# Platforms #

* Ubuntu-12.04
* openSUSE 12.3, SLES 11 SP2

# Cookbooks #

The following cookbooks are dependencies:

* database
* mysql
* openstack-common
* postgresql

# Usage #

The usage of this cookbook is optional, you may choose to set up your own databases without using this cookbook. If you choose to do so, you will need to do the following:

* create the schema specified by the `openstack-db` recipe.
* create and upload encrypted data bags into your chef environment, as
  specified by `#db_password` in the `openstack-db` recipe.

# Resources/Providers #

None

# Templates #

None

# Recipes #

## client ##

- database client configuration, selected by attributes

## server ##

- database server configuration, selected by attributes

## mysql-client ##

- calls mysql::ruby and mysql::client and installs 'mysql_python_packages'

## mysql-server ##

- configures the mysql server for OpenStack

## postgresql-client ##

- calls postgresql::ruby and postgresql::client and installs 'postgresql_python_packages'

## postgresql-server ##

- configures the PostgreSQL server for OpenStack

## openstack-db ##

- creates necessary tables, users, and grants for OpenStack

# Attributes #

* `openstack["db"]["bind_interface"]` - bind to interfaces IPv4 address
* `openstack["db"]["platform"]["mysql_python_packages"]` - platform-specific mysql python packages to install

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
| **Author**           |  Justin Shepherd (<justin.shepherd@rackspace.com>) |
| **Author**           |  Jason Cannavale (<jason.cannavale@rackspace.com>) |
| **Author**           |  Ron Pedde (<ron.pedde@rackspace.com>)             |
| **Author**           |  Joseph Breu (<joseph.breu@rackspace.com>)         |
| **Author**           |  William Kelly (<william.kelly@rackspace.com>)     |
| **Author**           |  Darren Birkett (<darren.birkett@rackspace.co.uk>) |
| **Author**           |  Evan Callicoat (<evan.callicoat@rackspace.com>)   |
| **Author**           |  Matt Thompson (<matt.thompson@rackspace.co.uk>)   |
| **Author**           |  Matt Ray (<matt@opscode.com>)                     |
| **Author**           |  Sean Gallagher (<sean.gallagher@.att.com>)        |
| **Author**           |  John Dewey (<jdewey@att.com>)                     |
| **Author**           |  Ionut Artarisi (<iartarisi@suse.cz>)              |
|                      |                                                    |
| **Copyright**        |  Copyright (c) 2012-2013, Rackspace US, Inc.       |
| **Copyright**        |  Copyright (c) 2012-2013, Opscode, Inc.            |
| **Copyright**        |  Copyright (c) 2013, AT&T Services, Inc.           |
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
