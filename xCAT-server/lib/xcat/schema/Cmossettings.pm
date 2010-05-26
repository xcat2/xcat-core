# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_schema::Cmossettings;

#################################################################################
# This is a simple node to cmos batch file mapping to be used by asu
# 
###############################################################################
%tabspec = (
    cmossettings => {
	cols => [qw(node file comments disable)],  #do not change 'disable' and 'comments', it is required by xCAT
	keys => [qw(node)],
        required => [qw(node)],
        types => {
	    node => 'TEXT',  
	},
	table_desc => 'Maps node to CMOS values to be used for setup at node discovery',
	descriptions => {
	    node => 'The node id.',
	    file => 'The asu batch file to use.',
	    comments => 'Any user-written notes.',
	    disable => "Set to 'yes' or '1' to comment out this row.",
	},
    },
); # end of tabspec definition



##################################################################
# The following %defspec is OPTIONAL. You only need to define it 
# if you want your tables to work with xCAT object abstraction layer
# commands such as lsdef, mkdef, chdef and rmdef.
#
# Note: The xCAT database accessting commands such as
#       tabdump, chtab, gettab, nodels, nodeadd, nodech, etc. 
#       still work without it.
# 
#       Please make sure that any new object name and attribute name
#       should start with "x_". 
################################################################## 

%defspec = (
    cmos => { attrs => [], attrhash => {}, objkey => 'cmos' },   #create a new object called 'cmos', 
);

#define the attribtues in the 'x_job' object using the cmossettings table columns.
@{$defspec{cmos}->{'attrs'}} = 
(
    {   attr_name => 'cmos',
	tabentry => 'cmossettings.file',
	access_tabentry => 'cmossettings.file=attr:cmos',
    }
);

1;


