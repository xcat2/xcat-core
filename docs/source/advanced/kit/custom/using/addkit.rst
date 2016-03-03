Adding a Kit to xCAT
--------------------

Adding a complete Kit to xCAT
`````````````````````````````

A complete kit must be added to the xCAT management node and defined in the xCAT database before its kit components can be added to xCAT osimages or used to update diskful cluster nodes.

To add a kit run the following command: ::

    addkit <complete kit tarfile>

The addkit command will expand the kit tarfile. The default location will be <site.installdir>/kits directory but an alternate location may be specified. (Where site.installdir is the value of the installdir attribute in the xCAT site definition.)

It will also add the kit to the xCAT database by creating xCAT object definitions for the kit as well as any kitrepo or kitcomponent definitions included in the kit.

Kits are added to the kit table in the xCAT database keyed by a combination of kit basename and version values. Therefore, user can add multiple kit definitions for the same product. For example, user could have one definition for release 1.2.0.0 and one for 1.3.0.0 of the product. This means that user will be able to add different versions of the kit components to different osimage definitions if desired.

Listing a kit
`````````````
The xCAT kit object definition may be listed using the xCAT lsdef command.  ::

    lsdef -t kit -l <kit name>

The contents of the kit may be listed by using the lskit command.  ::

    lskit <kit name>

