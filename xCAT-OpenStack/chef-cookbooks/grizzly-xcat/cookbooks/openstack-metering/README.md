Description
===========

Installs the OpenStack Metering service **Ceilometer** as part of the OpenStack
reference deployment Chef for OpenStack.  Ceilometer is currently installed
from packages.

https://wiki.openstack.org/wiki/Ceilometer

Requirements
============

Cookbooks
---------

Usage
=====

agent-central
----
- Installs agent central service.

agent-compute
----
- Installs agent compute service.

api
----
- Installs API service.

collector
----
- Installs nova network service.

common
----
- Common metering configuration.

identity_registration
----
- Registers the endpoints with Keystone.

Attributes
==========

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
| **Author**           |  Matt Ray (<matt@opscode.com>)                     |
| **Author**           |  John Dewey (<jdewey@att.com>)                     |
|                      |                                                    |
| **Copyright**        |  Copyright (c) 2013, Opscode, Inc.                 |
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
