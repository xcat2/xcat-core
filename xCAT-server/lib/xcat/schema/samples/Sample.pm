# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_schema::Sample;

#################################################################################
# This is a sample code that contains the user defined user database schema defination.
# Here is a list of things you can do to add DB tables to xCAT database.
#   1  Copy this file to /opt/xcat/lib/perl/xCAT_schema directory, rename it
#      to your chosen schema name. 
#   2  Change the word Sample above to be the same as the file name you chose.
#   3  Do NOT change the variable name "%tabspec".
#   4  x_lljob and x_llnode are the sample table names. 
#      jobid, status, node, jobstatus are the sample column names. 
#      Change them to your like. Please make sure all table names start with "x_".
#      Each table must have a 'disable' and comments column.
#      Please do not use SQL reserved words for your table names and column names.
#      Use this site to check the reserved words: 
#         http://www.petefreitag.com/tools/sql_reserved_words_checker/  
#   5 Change the keys.
#   6 Change the data types. For SQLite
#           the  default data type is TEXT if not specified.
#     The supported data types are: 
#        REAL,CHAR,TEXT,DATE,TIME,FLOAT,BIGINT,DOUBLE,STRING,
#        BINARY,DECIMAL,BOOLEAN,INTEGER,VARCHAR,SMALLINT,TIMESTAMP
#     Please note that SQLight only supports: INTEGER, REAL, TEXT, BLOB. 
#     xCAT support MySQL, PostgreSQL and DB2 also, supported data types
#     depend on the database you are using. 
#   7 Change the table descriptions and column descriptions to your like.
#   8 Restart the the xcatd, the tables will be automatically generated. 
#   9 If you have service nodes,  copy all the files to those also and restart
#     the daemon.
#   Note compress and tablespace are only supported for DB2
#   engine is only supported for MySQL 
###############################################################################
%tabspec = (
    x_lljob => {      #your table name should start with "x_".
	cols => [qw(jobid status comments disable)],  #do not change 'disable' and 'comments', it is required by xCAT
	keys => [qw(jobid)],
	keys => [qw(jobid)],
        required => [qw(jobid)],
        types => {
	    jobid => 'INTEGER',  
	},
        engine => 'InnoDB',  
	table_desc => 'Stores jobs.',
	descriptions => {
	    jobid => 'The job id.',
	    status => 'The status of the job.',
	    comments => 'Any user-written notes.',
	    disable => "Set to 'yes' or '1' to comment out this row.",
	},
    },
    x_llnode => {     
        cols => [qw(node jobid jobstatus cpu_usage comments disable)],
        keys => [qw(node)],
        required => [qw(node jobid)],
        types => {
	    jobid => 'INTEGER',
	    cpu_usage => 'FLOAT',
	},
        compress =>'YES',  
        tablespace =>'XCATTBS32K', 
        table_desc => 'Stores the node status.',
        descriptions => {
            node=> 'The node.',
            jobid => 'The job that runs on the node.',
            jobstatus => 'The status of the job on the node.',
            cpu_usage => 'The percent of cpu usage on the node.',
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
    x_job => { attrs => [], attrhash => {}, objkey => 'x_jobid' },   #create a new object called 'x_job', 
);

#define the attribtues in the 'x_job' object using the x_lljob talbe columns.
@{$defspec{x_job}->{'attrs'}} = 
(
    {   attr_name => 'x_jobid',
	tabentry => 'x_lljob.jobid',
	access_tabentry => 'x_lljob.jobid=attr:x_jobid',
    },
    {   attr_name => 'x_status',
	tabentry => 'x_lljob.status',
	access_tabentry => 'x_lljob.jobid=attr:x_jobid',
    },
);

#object 'node' already defined in /opt/xcat/lib/perl/xCAT/Schema.pm. 
#Here we just add x_jobid and x_jobstatus attributes to the node object
@{$defspec{node}->{'attrs'}} = 
(
    {	attr_name => 'x_jobid',
	tabentry => 'x_llnode.jobid',
	access_tabentry => 'x_llnode.node=attr:node',
    },
    {	attr_name => 'x_jobstatus',
	tabentry => 'x_llnode.jobstatus',
	access_tabentry => 'x_llnode.node=attr:node',
    },
    {	attr_name => 'x_cpu',
	tabentry => 'x_llnode.cpu_usage',
	access_tabentry => 'x_llnode.node=attr:node',
    },
);
1;


