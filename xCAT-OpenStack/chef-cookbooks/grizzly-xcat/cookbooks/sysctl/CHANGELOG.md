## v0.3.2

* [GH-5] Fixed ImmutableAttributeModification (Mark Pimentel)
* Added LWRP integration tests for test kitchen
* LWRP now sets attributes on the node via node.default, not node.set allowing easier overrides by other cookbooks

## v0.3.1

* Added attribute integration tests for test kitchen
* Added alpha RHEL/CentOS support
* Added Travis CI Builds
* Cleaned up foodcritic and tailor complaints

## v0.3.0

There is a lot of talk about making one sysctl cookbook. Let's make it happen.

* BREAKING CHANGE: use sysctl.params instead of sysctl.attributes to match LWRP and sysctl standard naming
* [GH-1] Remove 69-chef-static.conf
* New Maintainer: Sander van Zoest, OneHealth
* Update Development environment with Berkshelf, Vagrant, Test-Kitchen

## v0.2.0:

* [FB-3] - Notify procps start immediately
* [FB-4] - Dynamic configuration file. Add LWRP.
* [FB-5] - Allow Bignums as values
