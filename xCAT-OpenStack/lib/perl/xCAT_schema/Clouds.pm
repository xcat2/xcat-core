# IBM(c) 2013 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_schema::Clouds;

################################################################################
#
# xCAT database Schema for representing OpenStack clouds in an xCAT cluster
#
################################################################################
%tabspec = (
    clouds => {      
	cols => [qw(name controller publicnet novanet mgtnet vmnet adminpw dbpwcomments disable)],  #do not change 'disable' and 'comments', it is required by xCAT
	keys => [qw(name)],
        required => [qw(name)],
	table_desc => 'OpenStack clouds managed by this xCAT cluster',
	descriptions => {
	    name => 'The name of this cloud',
	    controller => 'The xCAT node name of the controller node',
	    publicnet => 'The name of the network in the xCAT networks table to be used for the OpenStack public network',
	    novanet => 'The name of the network in the xCAT networks table to be used for the OpenStack Nova network',
	    mgtnet => 'The name of the network in the xCAT networks table to be used for the OpenStack management network',
	    vmnet => 'The name of the network in the xCAT networks table to be used for the OpenStack virtual machine network',
	    adminpw => 'The administrative password',
	    dbpw => 'The database password',
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
    {   attr_name => 'publicnet',
	tabentry => 'clouds.publicnet',
	access_tabentry => 'clouds.name=attr:name',
    },
    {   attr_name => 'novanet',
	tabentry => 'clouds.novanet',
	access_tabentry => 'clouds.name=attr:name',
    },
    {   attr_name => 'mgtnet',
	tabentry => 'clouds.mgtnet',
	access_tabentry => 'clouds.name=attr:name',
    },
    {   attr_name => 'vmnet',
	tabentry => 'clouds.vmnet',
	access_tabentry => 'clouds.name=attr:name',
    },
    {   attr_name => 'adminpw',
	tabentry => 'clouds.adminpw',
	access_tabentry => 'clouds.name=attr:name',
    },
    {   attr_name => 'dbpw',
	tabentry => 'clouds.dbpw',
	access_tabentry => 'clouds.name=attr:name',
    },
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


