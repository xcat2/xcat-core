Description
===========

This cookbook installs the OpenStack Image service **Glance** as part of an OpenStack reference deployment Chef for OpenStack. The http://github.com/mattray/chef-openstack-repo contains documentation for using this cookbook in the context of a full OpenStack deployment. Glance is installed from packages, optionally populating the repository with default images.

http://glance.openstack.org/

Requirements
============

Chef 0.10.0 or higher required (for Chef environment use).

Cookbooks
---------

The following cookbooks are dependencies:

* openstack-common
* openstack-identity

Usage
=====

api
------
- Installs the image-api server

registry
--------
- Installs the image-registry server

keystone-registration
---------------------
- Registers the API endpoint and glance service Keystone user

The Glance cookbook currently supports file, swift, and Rackspace Cloud Files (swift API compliant) backing stores.  NOTE: changing the storage location from cloudfiles to swift (and vice versa) requires that you manually export and import your stored images.

To enable these features set the following in the default attributes section in your environment:

Files
-----

```json
"openstack": {
    "image": {
        "api": {
            "default_store": "file"
        },
        "upload_images": [
            "cirros"
        ],
        "image_upload": true
    }
}
```

Swift
-----

```json
"openstack": {
    "image": {
        "api": {
            "default_store": "swift"
        },
        "upload_images": [
            "cirros"
        ],
        "image_upload": true
    }
}
```

Providers
=========

image
-----

Action: `:upload`

- `:image_url`: Location of the image to be loaded into Glance.
- `:image_name`: A name for the image.
- `:image_type`: `qcow2` or `ami`. Defaults to `qcow2`.
- `:identity_user`: Username of the Keystone admin user.
- `:identity_pass`: Password for the Keystone admin user.
- `:identity_tenant`: Name of the Keystone admin user's tenant.
- `:identity_uri`: URI of the Identity API endpoint.

Attributes
==========

Attributes for the Image service are in the ['openstack']['image'] namespace.

* `openstack['image']['verbose']` - Enables/disables verbose output for glance services.
* `openstack['image']['debug']` - Enables/disables debug output for glance services.
* `openstack['image']['identity_service_chef_role']` - The name of the Chef role that installs the Keystone Service API
* `openstack['image']['user'] - User glance runs as
* `openstack['image']['group'] - Group glance runs as
* `openstack['image']['db']['username']` - Username for glance database access
* `openstack['image']['api']['adminURL']` - Used when registering image endpoint with keystone
* `openstack['image']['api']['internalURL']` - Used when registering image endpoint with keystone
* `openstack['image']['api']['publicURL']` - Used when registering image endpoint with keystone
* `openstack['image']['service_tenant_name']` - Tenant name used by glance when interacting with keystone - used in the API and registry paste.ini files
* `openstack['image']['service_user']` - User name used by glance when interacting with keystone - used in the API and registry paste.ini files
* `openstack['image']['service_role']` - User role used by glance when interacting with keystone - used in the API and registry paste.ini files
* `openstack['image']['api']['auth']['cache_dir']` - Defaults to `/var/cache/glance/api`. Directory where `auth_token` middleware writes certificates for glance-api
* `openstack['image']['registry']['auth']['cache_dir']` - Defaults to `/var/cache/glance/registry`. Directory where `auth_token` middleware writes certificates for glance-registry
* `openstack['image']['image_upload']` - Toggles whether to automatically upload images in the `openstack['image']['upload_images']` array
* `openstack['image']['upload_images']` - Default list of images to upload to the glance repository as part of the install
* `openstack['image']['upload_image']['<imagename>']` - URL location of the `<imagename>` image. There can be multiple instances of this line to define multiple imagess (eg natty, maverick, fedora17 etc)
--- example `openstack['image']['upload_image']['natty']` - "http://c250663.r63.cf1.rackcdn.com/ubuntu-11.04-server-uec-amd64-multinic.tar.gz"
* `openstack['image']['api']['default_store']` - Toggles the backend storage type.  Currently supported is "file" and "swift"
* `openstack['image']['api']['swift']['store_container']` - Set the container used by glance to store images and snapshots.  Defaults to "glance"
* `openstack['image']['api']['swift']['store_large_object_size']` - Set the size at which glance starts to chunnk files.  Defaults to "200" MB
* `openstack['image']['api']['swift']['store_large_object_chunk_size']` - Set the chunk size for glance.  Defaults to "200" MB
* `openstack['image']['api']['rbd']['rbd_store_ceph_conf']` - Default location of ceph.conf
* `openstack['image']['api']['rbd']['rbd_store_user']` - User for connecting to ceph store
* `openstack['image']['api']['rbd']['rbd_store_pool']` - RADOS pool for images
* `openstack['image']['api']['rbd']['rbd_store_chunk_size']` - Size in MB of chunks for RADOS Store, should be a power of 2

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

Author:: Justin Shepherd (<justin.shepherd@rackspace.com>)
Author:: Jason Cannavale (<jason.cannavale@rackspace.com>)
Author:: Ron Pedde (<ron.pedde@rackspace.com>)
Author:: Joseph Breu (<joseph.breu@rackspace.com>)
Author:: William Kelly (<william.kelly@rackspace.com>)
Author:: Darren Birkett (<darren.birkett@rackspace.co.uk>)
Author:: Evan Callicoat (<evan.callicoat@rackspace.com>)
Author:: Matt Ray (<matt@opscode.com>)
Author:: Jay Pipes (<jaypipes@att.com>)
Author:: John Dewey (<jdewey@att.com>)
Author:: Craig Tracey (<craigtracey@gmail.com>)
Author:: Sean Gallagher (<sean.gallagher@att.com>)

Copyright 2012, Rackspace US, Inc.
Copyright 2012-2013, Opscode, Inc.
Copyright 2012-2013, AT&T Services, Inc.
Copyright 2013, Craig Tracey <craigtracey@gmail.com>

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
