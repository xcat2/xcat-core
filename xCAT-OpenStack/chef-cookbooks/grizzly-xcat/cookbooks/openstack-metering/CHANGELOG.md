openstack-metering Cookbook CHANGELOG
==============================
This file is used to list changes made in each version of the openstack-metering cookbook.

v7.0.4
------
### Bug
- Ubuntu package dependency for python-mysqldb missing for ceilometer-collector

v7.0.3
------
### Bug
- Ubuntu cloud archive dpkg failing to install init script properly for agent-compute

v7.0.2
------
### Improvement
- Add optional host to the ceilometer.conf

v7.0.1
------
### Bug
- Fix naming inconsistency for db password databag. This makes the metering cookbook consistent with all the others.
