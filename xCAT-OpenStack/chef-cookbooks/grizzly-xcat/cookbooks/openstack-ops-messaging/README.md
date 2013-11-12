# Description #

This cookbook provides shared message queue configuration for the OpenStack **Grizzly** reference deployment provided by Chef for OpenStack. The http://github.com/mattray/chef-openstack-repo contains documentation for using this cookbook in the context of a full OpenStack deployment. It currently supports RabbitMQ and will soon other queues.

# Requirements #

Chef 11 with Ruby 1.9.x required.

# Platforms #

* Ubuntu-12.04

# Cookbooks #

The following cookbooks are dependencies:

* openstack-common
* rabbitmq

# Usage #

The usage of this cookbook is optional, you may choose to set up your own messaging service without using this cookbook. If you choose to do so, you will need to provide all of the attributes listed under the [Attributes](#attributes).

# Resources/Providers #

None

# Templates #

None

# Recipes #

## server ##

- message queue server configuration, selected by attributes

## rabbitmq-server ##

- configures the RabbitMQ server for OpenStack

# Attributes #

* `openstack["mq"]["bind_interface"]` - bind to interfaces IPv4 address
* `openstack["mq"]["cluster"]` - whether or not to cluster rabbit, defaults to 'false'

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
| **Author**           |  John Dewey (<john@dewey.ws>)                      |
| **Author**           |  Matt Ray (<matt@opscode.com>)                     |
| **Author**           |  Craig Tracey (<craigtracey@gmail.com>)            |
|                      |                                                    |
| **Copyright**        |  Copyright (c) 2013, Opscode, Inc.                 |
| **Copyright**        |  Copyright (c) 2013, Craig Tracey                  |
| **Copyright**        |  Copyright (c) 2013, AT&T Services, Inc.           |


Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
