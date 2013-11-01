# IBM(c) 2013 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_schema::Clouds;

################################################################################
#
# xCAT database Schema for representing OpenStack clouds in an xCAT cluster
#
################################################################################
%tabspec = (
    clouds => {      
	cols => [qw(name controller hostip pubinterface mgtinterface datainterface template repository virttype comments disable)],  #do not change 'disable' and 'comments', it is required by xCAT
	keys => [qw(name)],
        required => [qw(name)],
	table_desc => 'OpenStack clouds managed by this xCAT cluster',
	descriptions => {
        name => 'The name of the cloud.  This is referred to by the nodes in the cloud table.',
	    controller => 'The xCAT node name of the controller node',
	    hostip => 'The host IP is in openstack management network on the controller node. It is always the rabbitmq host IP and nova_metadata_ip.',
	    pubinterface => 'Interface to use for external bridge. The default value is eth1.',
	    mgtinterface => 'Interface to use for openstack management. It is supposed that the mgtinterface for all the nodes are the same, and in the same network.',
	    datainterface => 'Interface to use for OpenStack nova vm communication. It is supposed that the datainterface for all the nodes are the same, and in the same network.',
	    template => 'Every cloud should be related to one environment template file. The absolute path is required.',
	    repository => 'Every could should be related to the openstack-chef-cookbooks. The absolute path is required. In the repository, there are cookbooks, environments, roles and on on.',
            virttype => 'What hypervisor software layer to use with libvirt (e.g., kvm, qemu).',
	    comments => 'Any user-written notes.',
	    disable => "Set to 'yes' or '1' to comment out this row.",
	},
    },
    cloud => {     
        cols => [qw(node cloudname comments disable)],
        keys => [qw(node)],
        required => [qw(node cloudname)],
        table_desc => 'xCAT nodes that are used in OpenStack clouds',
        descriptions => {
            node=> 'The xCAT node name',
            cloudname => 'The name of the cloud in the xCAT clouds table that is using this node',
	    comments => 'Any user-written notes.',
	    disable => "Set to 'yes' or '1' to comment out this row.",
        },
    },
); # end of tabspec definition







##################################################################
# 
#  Cloud object and attributes for *def commands 
# 
################################################################## 

# cloud object
%defspec = (
    cloud => { attrs => [], attrhash => {}, objkey => 'name' },  
);

# cloud attributes
@{$defspec{cloud}->{'attrs'}} = 
(
    {   attr_name => 'name',
        tabentry => 'clouds.name',
        access_tabentry => 'clouds.name=attr:name',
    },
    {   attr_name => 'controller',
	tabentry => 'clouds.controller',
	access_tabentry => 'clouds.name=attr:name',
    },
    {   attr_name => 'hostip',
	tabentry => 'clouds.hostip',
	access_tabentry => 'clouds.name=attr:name',
    },
    {   attr_name => 'pubinterface',
	tabentry => 'clouds.pubinterface',
	access_tabentry => 'clouds.name=attr:name',
    },
    {   attr_name => 'mgtinterface',
	tabentry => 'clouds.mgtinterface',
	access_tabentry => 'clouds.name=attr:name',
    },
    {   attr_name => 'datainterface',
	tabentry => 'clouds.datainterface',
	access_tabentry => 'clouds.name=attr:name',
    },
    {   attr_name => 'template',
	tabentry => 'clouds.template',
	access_tabentry => 'clouds.name=attr:name',
    },
    {   attr_name => 'repository',
	tabentry => 'clouds.repository',
	access_tabentry => 'clouds.name=attr:name',
    },
    {   attr_name => 'virttype',
	tabentry => 'clouds.virttype',
	access_tabentry => 'clouds.name=attr:name',
    }
);

#  node attributes for clouds
@{$defspec{node}->{'attrs'}} = 
(
    {	attr_name => 'cloud',
	tabentry => 'cloud.cloudname',
	access_tabentry => 'cloud.node=attr:node',
    },
);
1;


