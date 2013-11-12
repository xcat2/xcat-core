# CHANGELOG for cookbook-openstack-common

This file is used to list changes made in each version of cookbook-openstack-common.

## 0.4.3:
* Corrected `#search_for` role and recipe queries.

## 0.4.2:
* Remove hardcoded localhost for mysql host specification.

## 0.4.1:
* Changed endpoint attributes to use http for default scheme.  this is inline with
  default settings in keystone.  fine for dev,  but should be ssl for prod.

## 0.4.0:
* Remove `#config_by_role` as it is no longer used and no longer suits our needs.

## 0.3.5:
* Reverted change made in 8311869e5b99fecefd567ce3f1ad1cbdf8d5c5c6.

## 0.3.4:
* Allow `#search_for` to always returns an array.

## 0.3.3:
* Incorrectly mocked search results, as a result `#search_for` was performing unnecessary
  actions to an array.

## 0.3.2:
* Fix network-api endpoint path

## 0.3.1:
* Corrected a faulty Chef search query with `#config_by_role`.  The search returns a
  Hash, not an array.

## 0.3.0:
* Added `#rabbit_servers` method, which returns a comma-delimited string of rabbit
  servers in the format of host:port.
* The `#memcached_servers` method no longer accepts an environment.
* Re-factored methods which search to a generic `#search_for`.
* Added `#address_for` method, which returns the IPv4 (default) address of the given
  interface.
* Added global mysql setting of port and db type, for use with wrapper cookbooks.
* Add default messaging attributes, for use with wrapper cookbooks.

## 0.2.6:
* Update Chef dependency to Chef 11.

## 0.2.5:
* Moved the default library to database, to better represent its duties.

## 0.2.4:
* Break out #memcached_servers into separate library.

## 0.2.3:
* Sort the results returned by #memcached_servers.

## 0.2.2:
* Provides a mechanism to override memcache_servers search logic through node attributes.

## 0.2.1:
* Adds a prettytable_to_array function for parsing OpenStack CLI output.

## 0.2.0:
* First release of cookbook-openstack-common that aligns with the Grizzly packaging.
* Adds OpenStack Network endpoints.

## 0.1.x:
* Folsom-based packaging.

## 0.0.1:
* Initial release of cookbook-openstack-common.

- - -
Check the [Markdown Syntax Guide](http://daringfireball.net/projects/markdown/syntax) for help with Markdown.

The [Github Flavored Markdown page](http://github.github.com/github-flavored-markdown/) describes the differences between markdown on github and standard markdown.
