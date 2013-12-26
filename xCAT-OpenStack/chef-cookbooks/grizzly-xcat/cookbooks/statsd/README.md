Description
===========

Installs and sets up statsd <http://github.com/etsy/statsd>

Requirements
============

Ubuntu 12.04

Attributes
==========

* `node['statsd']['port']` - The port for Statsd to listen for stats on. Defaults to 8125
* `node['statsd']['graphite_host']` - The host to forward processed statistics to. Defaults to localhost.
* `node['statsd']['graphite_port']` - The port to forward processed statistics to. Defaults to 2003
* `node['statsd']['package_version']` - The version to use when creating the package. Defaults to 0.6.0
* `node['statsd']['tmp_dir']` - The temporary directory to while building the package. Defaults to /tmp
* `node['statsd']['repo']` - The gitrepo to use. Defaults to "git://github.com/etsy/statsd.git"
* `node['statsd']['sha']`  - The sha checksum of the repo to use

Usage
=====

Including this recipe will build a dpkg from the statsd git repository and install it.

By default statsd will attempt to send statistics to a graphite instance running on localhost.

Testing
=======

    $ bundle install
    $ bundle exec berks install
    $ bundle exec strainer test

License and Author
==================

Author:: Scott Lampert (<sl724q@att.com>)

Copyright 2012-2013, AT&T Services, Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
