group
=====

XCAT supports both static and dynamic groups. A static group is defined to contain a specific set of cluster nodes. A dynamic node group is one that has its members determined by specifying a selection criteria for node attributes. If a nodes attribute values match the selection criteria then it is dynamically included as a member of the group. The actual group membership will change over time as nodes have attributes set or unset. This provides flexible control over group membership by defining the attributes that define the group, rather than the specific node names that belong to the group. The selection criteria is a list of ``attr<operator>val`` pairs that can be used to determine the members of a group, (see below).

``Note`` : Dynamic node group support is available in xCAT version 2.3 and later.

In xCAT, the definition of a static group has been extended to include additional attributes that would normally be assigned to individual nodes. When a node is part of a static group definition, it can inherit the attributes assigned to the group. This feature can make it easier to define and manage cluster nodes in that you can generally assign nodes to the appropriate group and then just manage the group definition instead of multiple node definitions. This feature is not supported for dynamic groups.

To list all the attributes that may be set for a group definition you can run ::

    lsdef -t group -h

When a node is included in one or more static groups, a particular node attribute could actually be stored in several different object definitions. It could be in the node definition itself or it could be in one or more static group definitions. The precedence for determining which value to use is to choose the attribute value specified in the node definition if it is provided. If not, then each static group that the node belongs to will be checked to see if the attribute is set. The first value that is found is the value that is used. The static groups are checked in the order that they are specified in the ``groups`` attribute of the node definition.

``NOTE`` : In a large cluster environment it is recommended to focus on group definitions as much as possible and avoid setting the attribute values in the individual node definition. (Of course some attribute values, such as a MAC addresses etc., are only appropriate for individual nodes.) Care must be taken to avoid confusion over which values will be inherited by the nodes.

Group definitions can be created using the ``mkdef`` command, changed using the ``chdef`` command, listed using the ``lsdef`` command and removed using the ``rmdef`` command.

Creating a static node group
----------------------------

There are two basic ways to create xCAT static node groups. You can either set the ``groups`` attribute of the node definition or you can create a group definition directly.

You can set the ``groups`` attribute of the node definition when you are defining the node with the ``mkdef`` or ``nodeadd`` command or you can modify the attribute later using the ``chdef`` or ``nodech`` command. For example, if you want a set of nodes to be added to the group "aixnodes",you could run ``chdef`` or ``nodech`` as follows ::

    chdef -t node -p -o node01,node02,node03 groups=aixnodes

or ::

    nodech node01,node02,node03 groups=aixnodes

The ``-p`` (plus) option specifies that "aixnodes" be added to any existing value for the ``groups`` attribute. The ``-p`` (plus) option is not supported by ``nodech`` command.

The second option would be to create a new group definition directly using the ``mkdef`` command as follows ::

    mkdef -t group -o aixnodes members="node01,node02,node03"

These two options will result in exactly the same definitions and attribute values being created in the xCAT database.

Creating a dynamic node group
-----------------------------

The selection criteria for a dynamic node group is specified by providing a list of ``attr<operator>val`` pairs that can be used to determine the members of a group. The valid operators include: ``==``, ``!=``, ``=~`` and ``!~``. The ``attr`` field can be any node definition attribute returned by the ``lsdef`` command. The ``val`` field in selection criteria can be a simple sting or a regular expression. A regular expression can only be specified when using the ``=~`` or ``!~`` operators. See http://www.perl.com/doc/manual/html/pod/perlre.html for information on the format and syntax of regular expressions.

Operator descriptions ::

    == Select nodes where the attribute value is exactly this value.
    != Select nodes where the attribute value is not this specific value.
    =~ Select nodes where the attribute value matches this regular expression.
    !~ Select nodes where the attribute value does not match this regular expression.

The selection criteria can be specified using one or more ``-w attr<operator>val`` options on the command line.

If the ``val`` field includes spaces or any other characters that will be parsed by shell then the ``attr<operator>val`` needs to be quoted.

For example, to create a dynamic node group called "mygroup", where the hardware control point is "hmc01" and the partition profile is not set to service ::

    mkdef -t group -o mygroup -d -w hcp==hmc01 -w pprofile!=service

To create a dynamic node group called "pslesnodes", where the operating system name includes "sles" and the architecture includes "ppc" ::

    mkdef -t group -o pslesnodes -d -w os=~sles[0-9]+ -w arch=~ppc

To create a dynamic node group called nonpbladenodes where the node hardware management method is not set to blade and the architecture does not include ppc ::

    mkdef -t group -o nonpbladenodes -d -w mgt!=blade -w 'arch!~ppc'

