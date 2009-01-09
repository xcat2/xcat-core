#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------
package xCAT::ExtTab;
BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : -d '/opt/xcat' ? '/opt/xcat' : '/usr';
}
use lib "$::XCATROOT/lib/perl";

use xCAT::MsgUtils;
use File::Path;

%ext_tabspec=(); 
$ext_defspec=();


# loads user defined table spec. They are stored under /opt/xcat/lib/perl/xCAT_schema directory
my $path="$::XCATROOT/lib/perl/xCAT_schema";
my @extSchema=glob($path."/*.pm");
   # print "\nextSchema=@extSchema\n";

foreach (@extSchema) {
    /.*\/([^\/]*).pm$/;
    my $file=$_;
    my $modname = $1;
    no strict 'refs';
    eval {require($_)};
    if ($@) { 
	xCAT::MsgUtils->message('ES',"\n  Warning: The user defined database table schema file $file cannot be located or has compiling errors.\n"); 
	next;
    }   
    if (${"xCAT_schema::" . "$modname" . "::"}{tabspec}) {
	my %tabspec=%{${"xCAT_schema::" . "$modname" . "::"}{tabspec}};
	foreach my $tabname (keys(%tabspec)) {
	    $ext_tabspec{$tabname}=$tabspec{$tabname};
	}
    } else {
	xCAT::MsgUtils->message('ES', "\n  Warning: Cannot find \%tabspec variable in the user defined database table schema file $file\n");
    }
   
    #get the defspec from each file and merge them into %ext_defspec
    if (${"xCAT_schema::" . "$modname" . "::"}{defspec}) {
	my %defspec=%{${"xCAT_schema::" . "$modname" . "::"}{defspec}};
	foreach my $objname (keys(%defspec)) {
	    if (exists($defspec{$objname}->{'attrs'})) {
		if (exists($ext_defspec{$objname})) {
                    #print "insert\n";
		    my @attr_new=@{$defspec{$objname}->{'attrs'}};
		    my @attr=@{$ext_defspec{$objname}->{'attrs'}};
		    my %tmp_hash=();
		    foreach my $orig (@attr) {
			my $attrname=$orig->{attr_name};
			$tmp_hash{$attrname}=1;
		    }
		    foreach my $h (@attr_new) {
			my $attrname=$h->{attr_name};
			if (exists($tmp_hash{$attrname})) {
			    xCAT::MsgUtils->message('ES', "\n  Warning: Conflict when adding user defined defspec from file $file. Attribute name $attrname is already defined in object $objname.  \n");
			} else {
			    #print "\ngot here objname=$objname, attrname=" . $h->{attr_name} . "\n";
			    push(@{$ext_defspec{$objname}->{'attrs'}}, $h); 
			}
		    }
		} else {
		    #print "\ngot here objname=$objname, file=$file\n";
		    $ext_defspec{$objname}=$defspec{$objname};
		}	    
	    }
	}
    }   
    
} #foreach  

#print out the defspec
#print "\nexternal defspec:\n";
#foreach(%ext_defspec) {
#    print "  $_:\n";
#    my @attr=@{$ext_defspec{$_}->{'attrs'}};
#    foreach my $h (@attr) {
#	print "    " . $h->{attr_name} . "\n";
#    }
#}  

#-------------------------------------------------------
=head1 xCAT::ExtTab

    Handles user defined database tables.

=cut
#------------------------------------------------------

#-------------------------------------------------------

=head3  updateTables

     It is called by xcatd to generate the user-defined tables 
  if they do not exist, it also updates the tables if there is 
  Schmea change. 


=cut
#-------------------------------------------------------

sub updateTables
{
    #print "\nupdateTables\n";
    foreach (keys %ext_tabspec) {
	my $table= xCAT::Table->new($_,-create=>1,-autocommit=>1);
    }
}

1;
