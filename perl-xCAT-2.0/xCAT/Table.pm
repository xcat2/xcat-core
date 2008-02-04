# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#Note that at the moment it only implements SQLite.  This will probably be extended.
#Also, ugly perl errors/and warnings are not currently wrapped.  This probably will be cleaned
#up
#Some known weird behaviors
#creating new sqlite db files when only requested to read non-existant table, easy to fix,
#but going for prototype
#class xcattable
package xCAT::Table;
use Sys::Syslog;
BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : -d '/opt/xcat' ? '/opt/xcat' : '/usr';
}
use lib "$::XCATROOT/lib/perl";

use DBI;

#use strict;
use Data::Dumper;
use Scalar::Util qw/weaken/;
use xCAT::Schema;
use xCAT::NodeRange;
use Text::Balanced qw(extract_bracketed);
use xCAT::NotifHandler;

#--------------------------------------------------------------------------------

=head1 xCAT::Table 

xCAT::Table - Perl module for xCAT configuration access

=head2 SYNOPSIS

use xCAT::Table;
my $table = xCAT::Table->new("tablename");

my $hashref=$table->getNodeAttribs("nodename","columname1","columname2");
printf $hashref->{columname1};


=head2 DESCRIPTION

This module provides convenience methods that abstract the backend specific configuration to a common API.

Currently implements the preferred SQLite backend, as well as a CSV backend, using their respective perl DBD modules.

NOTES

The CSV backend is really slow at scale.  Room for optimization is likely, but in general DBD::CSV is slow, relative to xCAT 1.2.x.
The SQLite backend, on the other hand, is significantly faster on reads than the xCAT 1.2.x way, so it is recommended.

BUGS

This module is not thread-safe, due to underlying DBD thread issues.  Specifically in testing, SQLite DBD leaks scalars if a thread
where a Table object exists spawns a child and that child exits.  The recommended workaround for now is to spawn a thread to contain
all Table objects if you intend to spawn threads from your main thread.  As long as no thread in which the new method is called spawns
child threads, it seems to work fine.

AUTHOR

Jarrod Johnson <jbjohnso@us.ibm.com>

xCAT::Table is released under an IBM license....


=cut

#--------------------------------------------------------------------------

=head2   Subroutines 

=cut

#--------------------------------------------------------------------------

=head3   buildcreatestmt 

    Description:  Build create table statement ( see new)

    Arguments:
                Table name
				Table schema ( hash of column names)
    Returns:
                Table creation SQL 
    Globals:
        
    Error:
        
    Example:
        
                my $str =
                  buildcreatestmt($self->{tabname},
                                  $xCAT::Schema::tabspec{$self->{tabname}});

=cut

#--------------------------------------------------------------------------------
sub buildcreatestmt
{
    my $tabn  = shift;
    my $descr = shift;
    my $retv  = "CREATE TABLE $tabn (\n  ";
    my $col;
    foreach $col (@{$descr->{cols}})
    {
        $retv .= "$col TEXT";

        if (grep /^$col$/, @{$descr->{required}})
        {
            $retv .= " NOT NULL";
        }
        $retv .= ",\n  ";
    }
    $retv .= "PRIMARY KEY (";
    foreach (@{$descr->{keys}})
    {
        $retv .= "$_,";
    }
    $retv =~ s/,$/)\n)/;
    return $retv;
}

#--------------------------------------------------------------------------

=head3   new 

    Description: Constructor: Connects to  or Creates Database Table
 

    Arguments:  Table name
                0 = Connect to table
				1 = Create table
    Returns:
               Hash: Database Handle, Statement Handle, nodelist
    Globals:
        
    Error:
        
    Example:
       $nodelisttab = xCAT::Table->new("nodelist"); 
    Comments:
        none

=cut

#--------------------------------------------------------------------------------
sub new
{

    #Constructor takes table name as argument
    #Also takes a true/false value, or assumes 0.  If something true is passed, create table
    #is requested
    my $self  = {};
    my $proto = shift;
    $self->{tabname} = shift;
    unless (defined($xCAT::Schema::tabspec{$self->{tabname}})) { return undef; }
    $self->{schema}   = $xCAT::Schema::tabspec{$self->{tabname}};
    $self->{colnames} = \@{$self->{schema}->{cols}};
    my %otherargs  = @_;
    my $create     = $otherargs{'-create'};      #(scalar(@_) == 1 ? shift : 0);
    $self->{autocommit} = $otherargs{'-autocommit'};

    unless (defined($self->{autocommit}))
    {
        $self->{autocommit} = 1;
    }

    my $class = ref($proto) || $proto;
    $self->{dbuser}="";
    $self->{dbpass}="";

    my $xcatcfg = (defined $ENV{'XCATCFG'} ? $ENV{'XCATCFG'} : '');
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
    ($xcatcfg =~ /^$/) && die "Can't locate xCAT configuration";
    unless ($xcatcfg =~ /:/)
    {
        $xcatcfg = "SQLite:" . $xcatcfg;
    }
    if ($xcatcfg =~ /^SQLite:/)
    {
        $self->{backend_type} = 'sqlite';
        my @path = split(':', $xcatcfg, 2);
        unless (-e $path[1] . "/" . $self->{tabname} . ".sqlite" || $create)
        {
            return undef;
        }
        $self->{connstring} =
          "dbi:" . $xcatcfg . "/" . $self->{tabname} . ".sqlite";
    }
    elsif ($xcatcfg =~ /^CSV:/)
    {
        $self->{backend_type} = 'csv';
        $xcatcfg =~ m/^.*?:(.*)$/;
        my $path = $1;
        $self->{connstring} = "dbi:CSV:f_dir=" . $path;
    }
    else #Generic DBI
    {
       ($self->{connstring},$self->{dbuser},$self->{dbpass}) = split(/\|/,$xcatcfg);
       $self->{connstring} =~ s/^dbi://;
       $self->{connstring} =~ s/^/dbi:/;
        #return undef;
    }
    unless ($::XCAT_DBHS->{$self->{connstring},$self->{dbuser},$self->{dbpass},$self->{autocommit}}) { #= $self->{tabname};
      $::XCAT_DBHS->{$self->{connstring},$self->{dbuser},$self->{dbpass},$self->{autocommit}} = 
        DBI->connect($self->{connstring}, $self->{dbuser}, $self->{dbpass}, {AutoCommit => $self->{autocommit}});
     }

    $self->{dbh} = $::XCAT_DBHS->{$self->{connstring},$self->{dbuser},$self->{dbpass},$self->{autocommit}};
      #DBI->connect($self->{connstring}, $self->{dbuser}, $self->{dbpass}, {AutoCommit => $autocommit});
    if ($xcatcfg =~ /^SQLite:/)
    {
        my $dbexistq =
          "SELECT name from sqlite_master WHERE type='table' and name = ?";
        my $sth = $self->{dbh}->prepare($dbexistq);
        $sth->execute($self->{tabname});
        my $result = $sth->fetchrow();
        $sth->finish;
        unless (defined $result)
        {
            if ($create)
            {
                my $str =
                  buildcreatestmt($self->{tabname},
                                  $xCAT::Schema::tabspec{$self->{tabname}});
                $self->{dbh}->do($str);
            }
            else { return undef; }
        }
    }
    elsif ($xcatcfg =~ /^CSV:/)
    {
        $self->{dbh}->{'csv_tables'}->{$self->{tabname}} =
          {'file' => $self->{tabname} . ".csv"};
        $xcatcfg =~ m/^.*?:(.*)$/;
        my $path = $1;
        if (!-e $path . "/" . $self->{tabname} . ".csv")
        {
            unless ($create)
            {
                return undef;
            }
            my $str =
              buildcreatestmt($self->{tabname},
                              $xCAT::Schema::tabspec{$self->{tabname}});
            $self->{dbh}->do($str);
        }
    } else { #generic DBI
       my $tbexistq = $self->{dbh}->table_info('','',$self->{tabname},'TABLE');
	my $found = 0;
       while (my $data = $tbexistq->fetchrow_hashref) {
	if ($data->{'TABLE_NAME'} =~ /^\"?$self->{tabname}\"?\z/) {
		$found = 1;
		last;
	}
	}
	unless ($found) {
	    unless ($create)
	    {
	       return undef;
	    }
	    my $str =
	       buildcreatestmt($self->{tabname},
	                       $xCAT::Schema::tabspec{$self->{tabname}});
	    $self->{dbh}->do($str);
	}
     }

	
    updateschema($self);
    if ($self->{tabname} eq 'nodelist')
    {
        weaken($self->{nodelist} = $self);
    }
    else
    {
        $self->{nodelist} = xCAT::Table->new('nodelist',-create=>1);
    }
    bless($self, $class);
    return $self;
}

#--------------------------------------------------------------------------

=head3  updateschema 

    Description: Alters table schema

    Arguments: Hash containing Database and Table Handle and schema
        
    Returns: None
        
    Globals:
        
    Error:
        
    Example:
		  $self->{tabname} = shift;
          $self->{schema}   = $xCAT::Schema::tabspec{$self->{tabname}};
          $self->{colnames} = \@{$self->{schema}->{cols}};
          updateschema($self);        
    Comments:
        none

=cut

#--------------------------------------------------------------------------------
sub updateschema
{

    #This determines alter table statements required..
    my $self = shift;
    my @columns;
    if ($self->{backend_type} eq 'sqlite')
    {
        my $dbexistq =
          "SELECT sql from sqlite_master WHERE type='table' and name = ?";
        my $sth = $self->{dbh}->prepare($dbexistq);
        $sth->execute($self->{tabname});
        my $cstmt = $sth->fetchrow();
        $sth->finish;

        #my $cstmt = $result->{sql};
        $cstmt =~ s/.*\(//;
        $cstmt =~ s/\)$//;
        my @entries = split /,/, $cstmt;
        foreach (@entries)
        {
            unless (/\(/)
            {    #Filter out the PRIMARY KEY statement, but not if on a col
                my $colname = $_;
                $colname =~ s/^\s*(\S+)\s+.*\s*$/$1/
                  ; #I don't understand why it won't work otherwise for "    colname TEXT     "
                push @columns, $colname;
            }
        }
    } else { #Attempt generic dbi..
       my $sth = $self->{dbh}->column_info('','',$self->{tabname},'');
       while (my $cd = $sth->fetchrow_hashref) {
           push @columns,$cd->{'COLUMN_NAME'};
       }
	foreach (@columns) { #Column names may end up quoted by database engin
		s/"//g;
	}
    }

        #Now @columns reflects the *actual* columns in the database
        my $dcol;
        foreach $dcol (@{$self->{colnames}})
        {
            unless (grep /^$dcol$/, @columns)
            {

                #TODO: log/notify of schema upgrade?
                my $stmt =
                  "ALTER TABLE " . $self->{tabname} . " ADD $dcol TEXT";
                $self->{dbh}->do($stmt);
            }
        }
}

#--------------------------------------------------------------------------

=head3  setNodeAttribs

    Description: Set attributes values on the node input to the routine

    Arguments:
               Hash: Database Handle, Statement Handle, nodelist
               Node name
			   Attribute hash
    Returns:
        
    Globals:
        
    Error:
        
    Example:
       my $mactab = xCAT::Table->new('mac',-create=>1);
	   $mactab->setNodeAttribs($node,{mac=>$mac});
	   $mactab->close();

    Comments:
        none

=cut

#--------------------------------------------------------------------------------
sub setNodeAttribs
{
    my $self = shift;
    my $node = shift;
    return $self->setAttribs({'node' => $node}, @_);
}

#--------------------------------------------------------------------------

=head3  addNodeAttribs

    Description: Add new attributes input to the routine to the nodes

    Arguments:
           Hash of new attributes          
    Returns:
        
    Globals:
        
    Error:
        
    Example:
        
    Comments:
        none

=cut

#--------------------------------------------------------------------------------
sub addNodeAttribs
{
    my $self = shift;
    return $self->addAttribs('node', @_);
}

#--------------------------------------------------------------------------

=head3  addAttribs

    Description: add new attributes

    Arguments: 
               Hash: Database Handle, Statement Handle, nodelist
               Key name
		       Key value
			   Hash reference of column-value pairs to set
    Returns:
        
    Globals:
        
    Error:
        
    Example:
        
    Comments:
        none

=cut

#--------------------------------------------------------------------------------
sub addAttribs
{
    my $self   = shift;
    my $key    = shift;
    my $keyval = shift;
    my $elems  = shift;
    my $cols   = "";
    my @bind   = ();
    @bind = ($keyval);
    $cols = "$key,";

    for my $col (keys %$elems)
    {
        $cols = $cols . $col . ",";
        if (ref($$elems{$col}))
        {
            push @bind, ${$elems}{$col}->[0];
        }
        else
        {
            push @bind, $$elems{$col};
        }
    }
    chop($cols);
    my $qstring = 'INSERT INTO ' . $self->{tabname} . " ($cols) VALUES (";
    for (@bind)
    {
        $qstring = $qstring . "?,";
    }
    $qstring =~ s/,$/)/;
    my $sth = $self->{dbh}->prepare($qstring);
    $sth->execute(@bind);

    #$self->{dbh}->commit;

    #notify the interested parties
    my $notif = xCAT::NotifHandler->needToNotify($self->{tabname}, 'a');
    if ($notif == 1)
    {
        my %new_notif_data;
        $new_notif_data{$key} = $keyval;
        foreach (keys %$elems)
        {
            $new_notif_data{$_} = $$elems{$_};
        }
        xCAT::NotifHandler->notify("a", $self->{tabname}, [0],
                                          \%new_notif_data);
    }

}

#--------------------------------------------------------------------------

=head3 rollback 

    Description:  rollback changes

    Arguments:
              Database Handle
    Returns:
           none 
    Globals:
        
    Error:
        
    Example:

       my $tab = xCAT::Table->new($table,-create =>1,-autocommit=>0);
	   $tab->rollback();	

    Comments:
        none

=cut

#--------------------------------------------------------------------------------
sub rollback
{
    my $self = shift;
    $self->{dbh}->rollback;
}

#--------------------------------------------------------------------------

=head3 commit 

    Description:
             Commit changes
    Arguments:
        Database Handle
    Returns:
       none 
    Globals:
        
    Error:
        
    Example:
       my $tab = xCAT::Table->new($table,-create =>1,-autocommit=>0);
	   $tab->commit();	
        
    Comments:
        none

=cut

#--------------------------------------------------------------------------------
sub commit
{
    my $self = shift;
    $self->{dbh}->commit;
}

#--------------------------------------------------------------------------

=head3 setAttribs 

    Description:

    Arguments:
         Key name
		 Key value
		 Hash reference of column-value pairs to set

    Returns:
         None    
    Globals:
        
    Error:
        
    Example:
       my $tab = xCAT::Table->new( 'ppc', -create=>1, -autocommit=>0 );
	   $keyhash{'node'}    = $name;
	   $updates{'type'}    = lc($type);
	   $updates{'id'}      = $lparid;
	   $updates{'hcp'}     = $server;
	   $updates{'profile'} = $prof;
	   $updates{'frame'}   = $frame;
	   $updates{'mtms'}    = "$model*$serial";
	   $tab->setAttribs( \%keyhash,\%updates );
	   $tab->commit;

    Comments:
        none

=cut

#--------------------------------------------------------------------------------
sub setAttribs
{

    #Takes three arguments:
    #-Key name
    #-Key value
    #-Hash reference of column-value pairs to set
    my $self     = shift;
    my %keypairs = %{shift()};

    #my $key = shift;
    #my $keyval=shift;
    my $elems = shift;
    my $cols  = "";
    my @bind  = ();
    my $action;
    my @notif_data;
    my $qstring = "SELECT * FROM " . $self->{tabname} . " WHERE ";
    my @qargs   = ();
    foreach (keys %keypairs)
    {
        $qstring .= "$_ = ? AND ";
        push @qargs, $keypairs{$_};
    }
    $qstring =~ s/ AND \z//;
    my $query = $self->{dbh}->prepare($qstring);
    $query->execute(@qargs);

    #get the first row
    my $data = $query->fetchrow_arrayref();
    if (defined $data)
    {
        $action = "u";
    }
    else
    {
        $action = "a";
    }

    #prepare the notification data
    my $notif =
      xCAT::NotifHandler->needToNotify($self->{tabname}, $action);
    if ($notif == 1)
    {
        if ($action eq "u")
        {

            #put the column names at the very front
            push(@notif_data, $query->{NAME});

            #copy the data out because fetchall_arrayref overrides the data.
            my @first_row = @$data;
            push(@notif_data, \@first_row);

            #get the rest of the rows
            my $temp_data = $query->fetchall_arrayref();
            foreach (@$temp_data)
            {
                push(@notif_data, $_);
            }
        }
    }

    $query->finish();

    if ($action eq "u")
    {

        #update the rows
        $action = "u";
        for my $col (keys %$elems)
        {
            $cols = $cols . $col . " = ?,";
            push @bind, (($$elems{$col} =~ /NULL/) ? undef: $$elems{$col});
        }
        chop($cols);
        my $cmd = "UPDATE " . $self->{tabname} . " set $cols where ";
        foreach (keys %keypairs)
        {
            if (ref($keypairs{$_}))
            {
                $cmd .= $_ . " = '" . $keypairs{$_}->[0] . "' AND ";
            }
            else
            {
                $cmd .= $_ . " = '" . $keypairs{$_} . "' AND ";
            }
        }
        $cmd =~ s/ AND \z//;
        my $sth = $self->{dbh}->prepare($cmd);
        my $err = $sth->execute(@bind);
        if (not defined($err))
        {
            return (undef, $sth->errstr);
        }
	$sth->finish;
    }
    else
    {

        #insert the rows
        $action = "a";
        @bind   = ();
        $cols   = "";
	my %newpairs;
	#first, merge the two structures to a single hash
        foreach (keys %keypairs)
        {
	    $newpairs{$_} = $keypairs{$_};
	}
        for my $col (keys %$elems)
        {
	    $newpairs{$col} = $$elems{$col};
        }
	foreach (keys %newpairs) {
            $cols .= $_ . ",";
            push @bind, $newpairs{$_};
        }
        chop($cols);
        my $qstring = 'INSERT INTO ' . $self->{tabname} . " ($cols) VALUES (";
        for (@bind)
        {
            $qstring = $qstring . "?,";
        }
        $qstring =~ s/,$/)/;
        my $sth = $self->{dbh}->prepare($qstring);
        my $err = $sth->execute(@bind);
        if (not defined($err))
        {
            return (undef, $sth->errstr);
        }
	$sth->finish;
    }

    #notify the interested parties
    if ($notif == 1)
    {
        #create new data ref
        my %new_notif_data = %keypairs;
        foreach (keys %$elems)
        {
            $new_notif_data{$_} = $$elems{$_};
        }
        xCAT::NotifHandler->notify($action, $self->{tabname},
                                          \@notif_data, \%new_notif_data);
    }
    return 0;
}

#--------------------------------------------------------------------------

=head3 setAttribsWhere 

    Description:
       This function sets the attributes for the rows selected by the where clause.
    Arguments:
         Where clause.
	 Hash reference of column-value pairs to set
    Returns:
         None    
    Globals:        
    Error:        
    Example:
       my $tab = xCAT::Table->new( 'ppc', -create=>1, -autocommit=>1 );
	   $updates{'type'}    = lc($type);
	   $updates{'id'}      = $lparid;
	   $updates{'hcp'}     = $server;
	   $updates{'profile'} = $prof;
	   $updates{'frame'}   = $frame;
	   $updates{'mtms'}    = "$model*$serial";
	   $tab->setAttribs( "node in ('node1', 'node2', 'node3')", \%updates );
    Comments:
        none
=cut
#--------------------------------------------------------------------------------
sub setAttribsWhere
{
    #Takes three arguments:
    #-Where clause
    #-Hash reference of column-value pairs to set
    my $self     = shift;
    my $where_clause = shift;
    my $elems = shift;
    my $cols  = "";
    my @bind  = ();
    my $action;
    my @notif_data;
    my $qstring = "SELECT * FROM " . $self->{tabname} . " WHERE " . $where_clause;
    my @qargs   = ();
    my $query = $self->{dbh}->prepare($qstring);
    $query->execute(@qargs);

    #get the first row
    my $data = $query->fetchrow_arrayref();
    if (defined $data){  $action = "u";}
    else { return (0, "no rows selected."); }

    #prepare the notification data
    my $notif =
      xCAT::NotifHandler->needToNotify($self->{tabname}, $action);
    if ($notif == 1)
    {
      #put the column names at the very front
      push(@notif_data, $query->{NAME});

      #copy the data out because fetchall_arrayref overrides the data.
      my @first_row = @$data;
      push(@notif_data, \@first_row);
      #get the rest of the rows
      my $temp_data = $query->fetchall_arrayref();
      foreach (@$temp_data) {
        push(@notif_data, $_);
      }
    }

    $query->finish();

    #update the rows
    for my $col (keys %$elems)
    {
      $cols = $cols . $col . " = ?,";
      push @bind, (($$elems{$col} =~ /NULL/) ? undef: $$elems{$col});
    }
    chop($cols);
    my $cmd = "UPDATE " . $self->{tabname} . " set $cols where " . $where_clause;
    my $sth = $self->{dbh}->prepare($cmd);
    my $err = $sth->execute(@bind);
    if (not defined($err))
    {
      return (undef, $sth->errstr);
    }

    #notify the interested parties
    if ($notif == 1)
    {
      #create new data ref
      my %new_notif_data = ();
      foreach (keys %$elems)
      {
        $new_notif_data{$_} = $$elems{$_};
      }
      xCAT::NotifHandler->notify($action, $self->{tabname},
                                 \@notif_data, \%new_notif_data);
    }
    $sth->finish;
    return 0;
}



#--------------------------------------------------------------------------

=head3 getNodeAttribs 

    Description: Retrieves the requested attribute 

    Arguments:
            Table handle
			Noderange
	        Attribute type array	
    Returns:
       
			Attribute hash ( key attribute type) 
    Globals:
        
    Error:
        
    Example:
           my $ostab = xCAT::Table->new('nodetype');
		   my $ent = $ostab->getNodeAttribs($node,['profile','os','arch']);	

    Comments:
        none

=cut

#--------------------------------------------------------------------------------
sub getNodeAttribs
{
    my $self    = shift;
    my $node    = shift;
    my @attribs = @{shift()};
    my $datum;
    my @data = $self->getNodeAttribs_nosub($node, \@attribs);
    #my ($datum, $extra) = $self->getNodeAttribs_nosub($node, \@attribs);
    if ($extra) { return undef; }    # return (undef,"Ambiguous query"); }
    defined($data[0])
      || return undef;    #(undef,"No matching entry found in configuration");
    my $attrib;
    foreach $datum (@data) {
    foreach $attrib (@attribs)
    {

        if ($datum->{$attrib} =~ /^\/.*\/.*\//)
        {
            my $exp = substr($datum->{$attrib}, 1);
            chop $exp;
            my @parts = split('/', $exp, 2);
            $node =~ s/$parts[0]/$parts[1]/;
            $datum->{$attrib} = $node;
        }
        elsif ($datum->{$attrib} =~ /^\|.*\|.*\|$/)
        {

            #Perform arithmetic and only arithmetic operations in bracketed issues on the right.
            #Tricky part:  don't allow potentially dangerous code, only eval if
            #to-be-evaled expression is only made up of ()\d+-/%$
            #Futher paranoia?  use Safe module to make sure I'm good
            my $exp = substr($datum->{$attrib}, 1);
            chop $exp;
            my @parts = split('\|', $exp, 2);
            my $curr;
            my $next;
            my $prev;
            my $retval = $parts[1];
            ($curr, $next, $prev) =
              extract_bracketed($retval, '()', qr/[^()]*/);

            while ($curr)
            {

                #my $next = $comps[0];
                if ($curr =~ /^[\{\}()\-\+\/\%\*\$\d]+$/)
                {
                    use integer
                      ; #We only allow integer operations, they are the ones that make sense for the application
                    my $value = $node;
                    $value =~ s/$parts[0]/$curr/ee;
                    $retval = $prev . $value . $next;
                }
                else
                {
                    print "$curr is bad\n";
                }
                ($curr, $next, $prev) =
                  extract_bracketed($retval, '()', qr/[^()]*/);
            }
            $datum->{$attrib} = $retval;

            #print Dumper(extract_bracketed($parts[1],'()',qr/[^()]*/));
            #use text::balanced extract_bracketed to parse earch atom, make sure nothing but arith operators, parans, and numbers are in it to guard against code execution
        }
    }
    }
    return wantarray ? @data : $data[0];
}

#--------------------------------------------------------------------------

=head3 getNodeAttribs_nosub  

    Description:

    Arguments:
        
    Returns:
        
    Globals:
        
    Error:
        
    Example:
        
    Comments:
        none

=cut

#--------------------------------------------------------------------------------
sub getNodeAttribs_nosub
{
    my $self   = shift;
    my $node   = shift;
    my $attref = shift;
    my @data;
    my $datum;
    my @tents;
    my $return = 0;
    @tents = $self->getNodeAttribs_nosub_returnany($node, $attref);
    foreach my $tent (@tents) {
      $datum={};
      foreach (@$attref)
      {
        if ($tent and defined($tent->{$_}))
        {
           $return = 1;
           $datum->{$_} = $tent->{$_};
        } else { #attempt to fill in gapped attributes
           my $sent = $self->getNodeAttribs_nosub_returnany($node, [$_]);
           if ($sent and defined($sent->{$_})) {
              $return = 1;
              $datum->{$_} = $sent->{$_};
           }
        }
      }
      push(@data,$datum);
    }
    if ($return)
    {
        return wantarray ? @data : $data[0];
    }
    else
    {
        return undef;
    }
}

#--------------------------------------------------------------------------

=head3 getNodeAttribs_nosub_returnany  

    Description:

    Arguments:
        
    Returns:
        
    Globals:
        
    Error:
        
    Example:
        
    Comments:
        none

=cut

#--------------------------------------------------------------------------------
sub getNodeAttribs_nosub_returnany
{    #This is the original function
    my $self    = shift;
    my $node    = shift;
    my @attribs = @{shift()};
    my @results;

    #my $recurse = ((scalar(@_) == 1) ?  shift : 1);
    @results = $self->getAttribs({node => $node}, @attribs);
    my $data = $results[0];
    if (!defined($data))
    {
        my ($nodeghash) =
          $self->{nodelist}->getAttribs({node => $node}, 'groups');
        unless (defined($nodeghash) && defined($nodeghash->{groups}))
        {
            return undef;
        }
        my @nodegroups = split(/,/, $nodeghash->{groups});
        my $group;
        foreach $group (@nodegroups)
        {
            @results = $self->getAttribs({node => $group}, @attribs);
	    $data = $results[0];
            if ($data != undef)
            {
                foreach (@results) {
                   if ($_->{node}) { $_->{node} = $node; }
                };
                return @results;
            }
        }
    }
    else
    {

        #Don't need to 'correct' node attribute, considering result of the if that governs this code block?
        return @results;
    }
    return undef;    #Made it here, config has no good answer
}

#--------------------------------------------------------------------------

=head3 getAllEntries  

    Description:  Read entire table

    Arguments:
           Table handle 
    Returns:
       Hash containing all rows in table  
    Globals:
        
    Error:
        
    Example:

	 my $tabh = xCAT::Table->new($table);
	 my $recs=$tabh->getAllEntries();
        
    Comments:
        none

=cut

#--------------------------------------------------------------------------------
sub getAllEntries
{
    my $self = shift;
    my @rets;
    my $query = $self->{dbh}->prepare('SELECT * FROM ' . $self->{tabname});
    $query->execute();
    while (my $data = $query->fetchrow_hashref())
    {
        foreach (keys %$data)
        {
            if ($data->{$_} =~ /^$/)
            {
                $data->{$_} = undef;
            }
        }
        push @rets, $data;
    }
    $query->finish();
    return \@rets;
}

#--------------------------------------------------------------------------

=head3 getAllAttribsWhere  

    Description:  Get all attributes with "where" clause

    Arguments:
       Database Handle
       Where clause
    Returns:
        Array of attributes     
    Globals:
        
    Error:
        
    Example:
    $nodelist->getAllAttribsWhere("groups like '%".$atom."%'",'node','group'); 
    Comments:
        none

=cut

#--------------------------------------------------------------------------------
sub getAllAttribsWhere
{

    #Takes a list of attributes, returns all records in the table.
    my $self        = shift;
    my $whereclause = shift;
    my @attribs     = @_;
    my @results     = ();
    my $query       =
      $self->{dbh}->prepare('SELECT * FROM '
                . $self->{tabname}
                . ' WHERE ('
                . $whereclause
                . ") and (\"disable\" is NULL or \"disable\" in ('0','no','NO','no'))");
    $query->execute();
    while (my $data = $query->fetchrow_hashref())
    {
        my %newrow = ();
        foreach (@attribs)
        {
            unless ($data->{$_} =~ /^$/ || !defined($data->{$_}))
            { #The reason we do this is to undef fields in rows that may still be returned..
                $newrow{$_} = $data->{$_};
            }
        }
        if (keys %newrow)
        {
            push(@results, \%newrow);
        }
    }
    $query->finish();
    return @results;
}

#--------------------------------------------------------------------------

=head3 getAllNodeAttribs   

    Description: Get all the node attributes values for the input table on the
				 attribute list

    Arguments:
                 Table handle
				 Attribute list
    Returns:
                 Array of attribute values
    Globals:
        
    Error:
        
    Example:
         my @entries = $self->{switchtab}->getAllNodeAttribs(['port','switch']);
    Comments:
        none

=cut

#--------------------------------------------------------------------------------
sub getAllNodeAttribs
{

    #Extract and substitute every node record, expanding groups and substituting as getNodeAttribs does
    my $self    = shift;
    my $attribq = shift;
    my @results = ();
    my %donenodes
      ; #Remember those that have been done once to not return same node multiple times
    my $query =
      $self->{dbh}->prepare('SELECT node FROM '
              . $self->{tabname}
              . " WHERE \"disable\" is NULL or \"disable\" in ('','0','no','NO','no')");
    $query->execute();
    while (my $data = $query->fetchrow_hashref())
    {

        unless ($data->{node} =~ /^$/ || !defined($data->{node}))
        {    #ignore records without node attrib, not possible?
            my @nodes =
              noderange($data->{node})
              ;    #expand node entry, to make groups expand
            foreach (@nodes)
            {
                if ($donenodes{$_}) { next; }
                my $attrs;
                my $nde = $_;

                #if ($self->{giveand}) { #software requests each attribute be independently inherited
                #  foreach (@attribs) {
                #    my $attr = $self->getNodeAttribs($nde,$_);
                #    $attrs->{$_}=$attr->{$_};
                #  }
                #} else {
                my @attrs =
                  $self->getNodeAttribs($_, $attribq)
                  ;    #Logic moves to getNodeAttribs
                       #}
                 #populate node attribute by default, this sort of expansion essentially requires it.
                #$attrs->{node} = $_;
		foreach my $att (@attrs) {
			$att->{node} = $_;
		}
                $donenodes{$_} = 1;
                push @results, @attrs;    #$self->getNodeAttribs($_,@attribs);
            }
        }
    }
    $query->finish();
    return @results;
}

#--------------------------------------------------------------------------

=head3 getAllAttribs   

    Description: Returns a list of records in the input table for the input
				 list of attributes.

    Arguments:
             Table handle
			 List of attributes
    Returns:
        Array of attribute values
    Globals:
        
    Error:
        
    Example:
        $nodelisttab = xCAT::Table->new("nodelist");
		my @attribs = ("node");
		@nodes = $nodelisttab->getAllAttribs(@attribs);
    Comments:
        none

=cut

#--------------------------------------------------------------------------------
sub getAllAttribs
{

    #Takes a list of attributes, returns all records in the table.
    my $self    = shift;
    my @attribs = @_;
    my @results = ();
    my $query   =
      $self->{dbh}->prepare('SELECT * FROM '
              . $self->{tabname}
              . " WHERE \"disable\" is NULL or \"disable\" in ('','0','no','NO','no')");
    $query->execute();
    while (my $data = $query->fetchrow_hashref())
    {
        my %newrow = ();
        foreach (@attribs)
        {
            unless ($data->{$_} =~ /^$/ || !defined($data->{$_}))
            { #The reason we do this is to undef fields in rows that may still be returned..
                $newrow{$_} = $data->{$_};
            }
        }
        if (keys %newrow)
        {
            push(@results, \%newrow);
        }
    }
    $query->finish();
    return @results;
}

#--------------------------------------------------------------------------

=head3 delEntries    

    Description:  Delete table entries

    Arguments:
                Table Handle
                Entry to delete
    Returns:
        
    Globals:
        
    Error:
        
    Example:
	my $table=xCAT::Table->new("notification", -create => 1,-autocommit => 0);
	my %key_col = (filename=>$fname);
	$table->delEntries(\%key_col);
	$table->commit;

    Comments:
        none

=cut

#--------------------------------------------------------------------------------
sub delEntries
{
    my $self   = shift;
    my $keyref = shift;
    my %keypairs;
    if ($keyref)
    {
        %keypairs = %{$keyref};
    }

    my $notif = xCAT::NotifHandler->needToNotify($self->{tabname}, 'd');
    my @notif_data;
    if ($notif == 1)
    {
        my $qstring = "SELECT * FROM " . $self->{tabname};
        if ($keyref) { $qstring .= " WHERE "; }
        my @qargs = ();
        foreach (keys %keypairs)
        {
            $qstring .= "$_ = ? AND ";
            push @qargs, $keypairs{$_};
        }
        $qstring =~ s/ AND \z//;
        my $query = $self->{dbh}->prepare($qstring);
        $query->execute(@qargs);

        #prepare the notification data
        #put the column names at the very front
        push(@notif_data, $query->{NAME});
        my $temp_data = $query->fetchall_arrayref();
        foreach (@$temp_data)
        {
            push(@notif_data, $_);
        }
        $query->finish();
    }

    my @stargs    = ();
    my $delstring = 'DELETE FROM ' . $self->{tabname};
    if ($keyref) { $delstring .= ' WHERE '; }
    foreach (keys %keypairs)
    {
        $delstring .= $_ . ' = ? AND ';
        if (ref($keypairs{$_}))
        {   #XML transformed data may come in mangled unreasonably into listrefs
            push @stargs, $keypairs{$_}->[0];
        }
        else
        {
            push @stargs, $keypairs{$_};
        }
    }
    $delstring =~ s/ AND \z//;
    my $stmt = $self->{dbh}->prepare($delstring);
    $stmt->execute(@stargs);
    $stmt->finish;

    #notify the interested parties
    if ($notif == 1)
    {
        xCAT::NotifHandler->notify("d", $self->{tabname}, \@notif_data,
                                          {});
    }
}

#--------------------------------------------------------------------------

=head3 getAttribs    

    Description:

    Arguments:
               key
			   List of attributes
    Returns:
               Hash of requested attributes 
    Globals:
        
    Error:
        
    Example:
        $table = xCAT::Table->new('passwd');
		@tmp=$table->getAttribs({'key'=>'ipmi'},('username','password');
    Comments:
        none

=cut

#--------------------------------------------------------------------------------
sub getAttribs
{

    #Takes two arguments:
    #-Node name (will be compared against the 'Node' column)
    #-List reference of attributes for which calling code wants at least one of defined
    # (recurse argument intended only for internal use.)
    # Returns a hash reference with requested attributes defined.
    my $self = shift;

    #my $key = shift;
    #my $keyval = shift;
    my %keypairs = %{shift()};
    my @attribs  = @_;
    my @return;
    my $statement = 'SELECT * FROM ' . $self->{tabname} . ' WHERE ';
    my @exeargs;
    foreach (keys %keypairs)
    {

        if ($keypairs{$_})
        {
            $statement .= "\"".$_ . "\" = ? and ";
            if (ref($keypairs{$_}))
            {    #correct for XML process mangling if occurred
                push @exeargs, $keypairs{$_}->[0];
            }
            else
            {
                push @exeargs, $keypairs{$_};
            }
        }
        else
        {
            $statement .= "$_ is NULL and ";
        }
    }
    $statement .= "(\"disable\" is NULL or \"disable\" in ('0','no','NO','No','nO'))";
    my $query = $self->{dbh}->prepare($statement);
    $query->execute(@exeargs);
    my $data;
    while ($data = $query->fetchrow_hashref())
    {
        my $attrib;
        my %rethash;
        foreach $attrib (@attribs)
        {
            unless ($data->{$attrib} =~ /^$/ || !defined($data->{$attrib}))
            {    #To undef fields in rows that may still be returned
                $rethash{$attrib} = $data->{$attrib};
            }
        }
        if (keys %rethash)
        {
            push @return, \%rethash;
        }
    }
    $query->finish();
    if (@return)
    {
      return wantarray ? @return : $return[0];
    }
    return undef;
}

#--------------------------------------------------------------------------

=head3 getTable    

    Description:  Read entire Table

    Arguments:
                Table Handle

    Returns:
                Array of table rows       
    Globals:
        
    Error:
        
    Example:
                  my $table=xCAT::Table->new("notification", -create =>0);
				  my @row_array= $table->getTable;
    Comments:
        none

=cut

#--------------------------------------------------------------------------------
sub getTable
{

    # Get contents of table
    # Takes no arguments
    # Returns an array of hashes containing the entire contents of this
    #   table.  Each array entry contains a pointer to a hash which is
    #   one row of the table.  The row hash is keyed by attribute name.
    my $self = shift;
    my @return;
    my $statement = 'SELECT * FROM ' . $self->{tabname};
    my $query     = $self->{dbh}->prepare($statement);
    $query->execute();
    my $data;
    while ($data = $query->fetchrow_hashref())
    {
        my $attrib;
        my %rethash;
        foreach $attrib (keys %{$data})
        {
            $rethash{$attrib} = $data->{$attrib};
        }
        if (keys %rethash)
        {
            push @return, \%rethash;
        }
    }
    $query->finish();
    if (@return)
    {
        return @return;
    }
    return undef;
}

#--------------------------------------------------------------------------

=head3 close    

    Description: Close out Table transaction

    Arguments:
                Table Handle       
    Returns:
        
    Globals:
        
    Error:
        
    Example:
                  my $mactab = xCAT::Table->new('mac');
				  $mactab->setNodeAttribs($macmap{$mac},{mac=>$mac});
				  $mactab->close();
    Comments:
        none

=cut

#--------------------------------------------------------------------------------
sub close
{
    my $self = shift;
    #if ($self->{dbh}) { $self->{dbh}->disconnect(); }
    #undef $self->{dbh};
    if ($self->{tabname} eq 'nodelist') {
       undef $self->{nodelist};
    } else {
       $self->{nodelist}->close();
    }
}

#--------------------------------------------------------------------------

=head3 open    

    Description: Connect to Database

    Arguments:
           Empty Hash        
    Returns:
           Data Base Handle       
    Globals:
        
    Error:
        
    Example:
        
    Comments:
        none

=cut

#--------------------------------------------------------------------------------
sub open
{
    my $self = shift;
    $self->{dbh} = DBI->connect($self->{connstring}, "", "");
}

#--------------------------------------------------------------------------

=head3 DESTROY    

    Description:  Disconnect from Database

    Arguments:
              Database Handle     
    Returns:
        
    Globals:
        
    Error:
        
    Example:
        
    Comments:
        none

=cut

#--------------------------------------------------------------------------------
sub DESTROY
{
    my $self = shift;
    $self->{dbh} = '';
    undef $self->{dbh};
    #if ($self->{dbh}) { $self->{dbh}->disconnect(); undef $self->{dbh};}
    undef $self->{nodelist};    #Could be circular
}

1;

