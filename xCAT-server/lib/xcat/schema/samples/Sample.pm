# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_schema::Sample;

#################################################################################
# This is a sample code that contains the user defined user database schema defination.
# Here is a list of things you can do to add DB tables to xCAT database.
#   1  copy this file to /opt/xcat/lib/perl/xCAT_schema directory, rename it.
#   2  change the word Sample above to be the same as the file name.
#   3  Do NOT change the variable name "%tabspec".
#   4  lljob and llnode are the table names. 
#      jobid, status, node, jobstatus are the column names. Change them to your like.
#      Each table must have a 'disable' column.
#   5 change the keys
#   6 change the table descriptions and column descriptions to your like.
#   7 restart the the xcatd, the tables will be automatically generated. 
#   8 do above steps on all the service nodes. 
# 
###############################################################################
%tabspec = (
    lljob => {
	cols => [qw(jobid status disable)],  #do not change 'disable, it is required by xCAT
	keys => [qw(jobid)],
	table_desc => 'Stores jobs.',
	descriptions => {
	    jobid => 'The job id.',
	    status => 'The status of the job.',
	    disable => "Set to 'yes' or '1' to comment out this row.",
	},
    },
    llnode => {
        cols => [qw(node jobid jobstatus disable)],
        keys => [qw(node)],
        table_desc => 'Stores the node status.',
        descriptions => {
            node=> 'The node.',
            jobid => 'The job that runs on the node.',
            jobstatus => 'The status of the job on the node.',
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
################################################################## 

%defspec = (
    job => { attrs => [], attrhash => {}, objkey => 'jobid' },   #create a new object called 'job', 
);

#define the attribtues in the 'job' object using the lljob talbe columns.
@{$defspec{job}->{'attrs'}} = 
(
    {   attr_name => 'jobid',
	tabentry => 'lljob.jobid',
	access_tabentry => 'lljob.jobid=attr:jobid',
    },
    {   attr_name => 'status',
	tabentry => 'lljob.status',
	access_tabentry => 'lljob.jobid=attr:jobid',
    },
);

#object 'node' already defined in /opt/xcat/lib/perl/xCAT/Schema.pm. 
#Here we just add jobid and jobstatus attributes to the node object
@{$defspec{node}->{'attrs'}} = 
(
    {	attr_name => 'jobid',
	tabentry => 'llnode.jobid',
	access_tabentry => 'llnode.node=attr:node',
    },
    {	attr_name => 'jobstatus',
	tabentry => 'llnode.jobstatus',
	access_tabentry => 'llnode.node=attr:node',
    },
);
1;


