#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------
package xCAT::ExtTab;
BEGIN
{
$::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : -d '/opt/xcat' ? '/opt/xcat' : '/usr';

}
#  
#NO xCAT perl library routines should be used in this begin block
#(i.e. MsgUtils,Utils, etc) 
#  
#use lib "$::XCATROOT/lib/perl";

use File::Path;
%ext_tabspec=(); 
%ext_defspec=();


# loads user defined table spec. They are stored under /opt/xcat/lib/perl/xCAT_schema directory
my $path="$::XCATROOT/lib/perl/xCAT_schema";
my $filelist;  # no specific files
my @extSchema = &get_filelist($path, $filelist,"pm");
#   print "\nextSchema=@extSchema\n";

foreach (@extSchema) {
    /.*\/([^\/]*).pm$/;
    my $file=$_;
    my $modname = $1;
    no strict 'refs';
    my $warning;
    # `logger -t xcat processing $_`; 
    eval {require($_)};
    if ($@) { 
	$warning ="Warning: The user defined database table schema file $file cannot be located or has compiling errors.\n";
        print $warning;
        `logger -p local4.warning -t xcat $warning`; 
	next;
    }   
    if (${"xCAT_schema::" . "$modname" . "::"}{tabspec}) {
	my %tabspec=%{${"xCAT_schema::" . "$modname" . "::"}{tabspec}};
	foreach my $tabname (keys(%tabspec)) {
            if (exists($ext_tabspec{$tabname})) {
		$warning = "Warning: File $file: the table name $tabname is used by other applications. Please rename the table.\n";
                print $warning;
               `logger -p local4.warning -t xcat $warning`; 
	    } else {
		$ext_tabspec{$tabname}=$tabspec{$tabname};
	    }
	}
    } else {
	$warning ="\n  Warning: Cannot find \%tabspec variable in the user defined database table schema file $file\n";
         print $warning;
         `logger -p local4.warning -t xcat $warning`; 
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
			    $warning= "  Warning: Conflict when adding user defined defspec from file $file. Attribute name $attrname is already defined in object $objname.  \n";
                            print $warning;
                           `logger  -p local4.warning  -t xcat $warning`; 
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

#-------------------------------------------------------

=head3  updateTables

     It is called by xcatd to generate the user-defined tables 
  if they do not exist, it also updates the tables if there is 
  a schema change. 


=cut
#-------------------------------------------------------

sub updateTables
{
    #print "\nupdateTables\n";
    #print "\n";
    foreach (keys %ext_tabspec) {
	my $table= xCAT::Table->new($_,-create=>1);
        my $rc=$table->updateschema();
        $table->close();
    }
}
#--------------------------------------------------------------------------

=head3   
    Note this is a copy of the one in Table.pm but we cannot use any of the
    xCAT perl libraries in this routine,since the function was done in the
    Begin block.
    Description: get_filelist 

    Arguments:
             directory,filelist,type 
    Returns:
            The list of sql files to be processed which consists of all the
			files with <name>.sql  and <name>_<databasename>.sql
		        or 	
			files with <name>.pm  and <name>_<databasename>.pm
    Globals:

    Error:

    Example:
	my @filelist =get_filelist($directory,$filelist,$type);
            where type = "sql" or "pm"

=cut

#--------------------------------------------------------------------------------

sub get_filelist

{
    use File::Basename; 
    my $directory = shift;
    my $files     = shift;
    my $ext       = shift;
    my $dbname    = "sqlite";
    my $xcatcfg   = get_xcatcfg();

    if ($xcatcfg =~ /^DB2:/)
    {
        $dbname = "db2";
    }
    else
    {
        if ($xcatcfg =~ /^mysql:/)
        {
            $dbname = "mysql";
        }
        else
        {
            if ($xcatcfg =~ /^Pg:/)
            {
                $dbname = "pgsql";
            }
        }
    }
    $directory .= "/";

    my @filelist = ();

    my @list = glob($directory . "*.$ext");    # all files
    foreach my $file (@list)
    {
        my $filename= basename($file);  # strip filename
        my($name,$ext1) = split '\.', $filename;
        my($tmpname,$ext2) = split '\_', $name;
        if ($ext2 eq $dbname)   # matches the database
        {
            push @filelist, $file;
        }
        else
        {
            if ($ext2 eq "") # no database designated
            {
                push @filelist, $file;
            } else { # if not one of the databases, they just have _ in
                     # the file name
               if ($ext2 ne "db2" && $ext2 ne "mysql" && $ext2 ne "pgsql" && $ext2 ne "sqlite" ) {
                    push @filelist, $file;
               }
            }
        } 
         $ext2 = "";
         $ext1 = "";
    }
    return @filelist;
}
#--------------------------------------------------------------------------

=head3   

    Note this is a copy of the one in Table.pm but we cannot use any of the
    xCAT perl libraries in this routine,since the function was done in the

    Description: get_xcatcfg 

    Arguments:
              none 
    Returns:
              the database name from /etc/xcat/cfgloc or sqlite
    Globals:

    Error:

    Example:
	my $xcatcfg =get_xcatcfg();


=cut

#--------------------------------------------------------------------------------

sub get_xcatcfg
{
    my $xcatcfg = (defined $ENV{'XCATCFG'} ? $ENV{'XCATCFG'} : '');
    unless ($xcatcfg) {
        if (-r "/etc/xcat/cfgloc") {
	    my $cfgl;
	    open($cfgl,"<","/etc/xcat/cfgloc");
	    $xcatcfg = <$cfgl>;
	    close($cfgl);
	    chomp($xcatcfg);
	    $ENV{'XCATCFG'}=$xcatcfg; #Store it in env to avoid many file reads
        }
    }
    if ($xcatcfg =~ /^$/)
    {
        if (-d "/opt/xcat/cfg")
        {
            $xcatcfg = "SQLite:/opt/xcat/cfg";
        }
        else
        {
            if (-d "/etc/xcat")
            {
                $xcatcfg = "SQLite:/etc/xcat";
            }
        }
    }
    unless ($xcatcfg =~ /:/)
    {
        $xcatcfg = "SQLite:" . $xcatcfg;
    }
    return $xcatcfg;
}


1;
