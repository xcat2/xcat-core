# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#####################################################
#
#  xCAT plugin package to handle various commands that work with the
#     xCAT tables for an XML interface 
#
#####################################################
package xCAT_plugin::DButils;
use strict;
use warnings;
use xCAT::Table;
use xCAT::Schema;
use Data::Dumper;
use xCAT::NodeRange qw/noderange abbreviate_noderange/;
use xCAT::Schema;
use xCAT::Utils;
use XML::Simple; #smaller than libxml....
$XML::Simple::PREFERRED_PARSER='XML::Parser';
use Getopt::Long;
1;

#some quick aliases to table/value
my %shortnames = (
                  groups => [qw(nodelist groups)],
                  tags   => [qw(nodelist groups)],
                  mgt    => [qw(nodehm mgt)],
                  #switch => [qw(switch switch)],
                  );

#####################################################
# Return list of commands handled by this plugin
#####################################################
sub handled_commands
{
    return {
            getAllEntries     => "DButils",
            getNodeAttribs    => "DButils"
            };
}


#####################################################
# Process the command
#####################################################
sub process_request
{
    my $request  = shift;
    my $callback = shift;
    my $command  = $request->{command}->[0];
    if ($command eq "getAllEntries")
    {
        return getAllEntries($request,$callback);
    }
    elsif ($command eq "getNodeAttribs") 
    {
        return getNodeAttribs($request,$callback);
    }
    else
    {
        print "$command not implemented yet\n";
        return (1, "$command not written yet");
    }

}
#
# Read all the rows from the input table name and returns the response, so 
# that the XML will look like this
#<xcatresponse>
#<row>
#<attr>attribute1</attr>
#<value>value1</value>
#<attr>attribute2</attr>
#<value>value2</value>
#.
#.
#.
#<attr>attributeN</attr>
#<value>valueN</value>
#</row>
#.
#.
#.
#</xcatresponse>
#  
#
sub getAllEntries
{
    my $request      = shift;
    my $cb = shift;
    my $command  = $request->{command}->[0];
    my $tablename    = $request->{table}->[0];
    my $tab=xCAT::Table->new($tablename);
    my %rsp;
    my $recs        =   $tab->getAllEntries("all");
    unless (@$recs)        # table exists, but is empty.  Show header.
    {
	  if (defined($xCAT::Schema::tabspec{$tablename}))
  	  {
         my $header = "#";
	      my @array =@{$xCAT::Schema::tabspec{$tablename}->{cols}};
         foreach my $arow (@array) {
           $header .= $arow;
           $header .= ",";
         }
         chop $header;
         push @{$rsp{row}}, $header;
	      $cb->(\%rsp);
	      return;
	  }
	}
	# if there are records in the table
    my $i=1;
    my $row;
    foreach my $rec (@$recs){  # for each record from the table
      while ((my $attrname,my $value) = each(%$rec)) { # for each hash element
        $row="row".$i;
        @{$rsp{$row}{$attrname}}= $value; 
      }
      $i++; 
    }
# for checkin XML created
#my  $xmlrec=XMLout(\%rsp,RootName=>'xcatresponse',NoAttr=>1,KeyAttr=>[]);
       $cb->(\%rsp);

        return;
}
# Read all the input attributes for the noderange  from the input table. 
sub getAllNodeEntries
{
    my $request      = shift;
    my $callback = shift;
    my $nodes    = $request->{node};
    my $command  = $request->{command}->[0];
    my $table    = $request->{table}-[0];
    my $attr    = $request->{attr};
        return;
}

