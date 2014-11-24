#IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#TODO:
#MEMLEAK fix
# see NodeRange.pm for notes about how to produce a memory leak
# xCAT as it stands at this moment shouldn't leak anymore due to what is 
# described there, but that only hides from the real problem and the leak will
# likely crop up if future architecture changes happen
# in summary, a created Table object without benefit of db worker thread
# to abstract its existance will consume a few kilobytes of memory
# that never gets reused
# just enough notes to remind me of the design that I think would allow for
#   -cache to persist so long as '_build_cache' calls concurrently stack (for NodeRange interpretation mainly) (done)
#   -Allow plugins to define a staleness threshold for getNodesAttribs freshness (complicated enough to postpone...)
#    so that actions requested by disparate managed nodes may aggregate in SQL calls
# cache lifetime is no longer determined strictly by function duration
# now it can live up to 5 seconds.  However, most calls will ignore the cache unless using a special option.
# Hmm, potential issue, getNodesAttribs might return up to 5 second old data even if caller expects brand new data
# if called again, decrement again and clear cache
# for getNodesAttribs, we can put a parameter to request allowable staleneess
# if the cachestamp is too old, build_cache is called
# in this mode, 'use_cache' is temporarily set to 1, regardless of 
# potential other consumers (notably, NodeRange)
#perl errors/and warnings are not currently wrapped.
#  This probably will be cleaned
#up
#Some known weird behaviors
#creating new sqlite db files when only requested to read non-existant table, easy to fix,
#class xcattable
#FYI on emulated AutoCommit:
#SQLite specific behavior has Table layer implementing AutoCommit.  There
#is a significant limitation, 'rollback' may not roll all the way back
#if an intermediate transaction occured on the same table
#TODO: short term, have tabutils implement it's own rollback (the only consumer)
#TODO: longer term, either figure out a way to properly implement it or 
#      document it as a limitation for SQLite configurations
package xCAT::Table;
use xCAT::MsgUtils;
use Sys::Syslog;
use Storable qw/freeze thaw store_fd fd_retrieve/;
use IO::Socket;
#use Data::Dumper;
use POSIX qw/WNOHANG/;
use Time::HiRes qw (sleep);
use Safe;
my $evalcpt = new Safe;
BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : -d '/opt/xcat' ? '/opt/xcat' : '/usr';
}

# if AIX - make sure we include perl 5.8.2 in INC path.
#       Needed to find perl dependencies shipped in deps tarball.
if ($^O =~ /^aix/i) {
	unshift(@INC, qw(/usr/opt/perl5/lib/5.8.2/aix-thread-multi /usr/opt/perl5/lib/5.8.2 /usr/opt/perl5/lib/site_perl/5.8.2/aix-thread-multi /usr/opt/perl5/lib/site_perl/5.8.2));
}

use lib "$::XCATROOT/lib/perl";
my $cachethreshold=16; #How many nodes in 'getNodesAttribs' before switching to full DB retrieval
#TODO: dynamic tracking/adjustment, the point where cache is cost effective differs based on overall db size

use DBI;
$DBI::dbi_debug=9; # increase the debug output

use strict;
use Scalar::Util qw/weaken/;
require xCAT::Schema;
require xCAT::NodeRange;
use Text::Balanced qw(extract_bracketed);
require xCAT::NotifHandler;

my $dbworkerpid; #The process id of the database worker
my $dbworkersocket;
my $dbsockpath = "/var/run/xcat/dbworker.sock.".$$;
my $exitdbthread;
my $dbobjsforhandle;
my $intendedpid;


sub dbc_call {
    my $self = shift;
    my $function = shift;
    my @args = @_;
    my $request = { 
         function => $function,
         tablename => $self->{tabname},
         autocommit => $self->{autocommit},
          args=>\@args,
    };
    return dbc_submit($request);
}

sub dbc_submit {
    my $request = shift;
    $request->{'wantarray'} = wantarray();
    my $clisock;
    my $tries=300;
    while($tries and !($clisock = IO::Socket::UNIX->new(Peer => $dbsockpath, Type => SOCK_STREAM, Timeout => 120) ) ) {
        #print "waiting for clisock to be available\n";
        sleep 0.1;
        $tries--;
    }
    unless ($clisock) {
        use Carp qw/cluck/;
        cluck();
    }
    store_fd($request,$clisock);
    #print $clisock $data;
    my $data="";
    my $lastline="";
    my $retdata = fd_retrieve($clisock);
    close($clisock);
    if (ref $retdata eq "SCALAR") { #bug detected
        #in the midst of the operation, die like it used to die
        my $err;
        $$retdata =~ /\*XCATBUGDETECTED\*:(.*):\*XCATBUGDETECTED\*/s;
        $err = $1;
        die $err;
    }
    my @returndata = @{$retdata};
    if (wantarray) {
        return @returndata;
    } else {
        return $returndata[0];
    }
}

sub shut_dbworker {
    $dbworkerpid = 0; #For now, just turn off usage of the db worker
    #This was created as the monitoring framework shutdown code otherwise seems to have a race condition
    #this may incur an extra db handle per service node to tolerate shutdown scenarios
}
sub init_dbworker {
#create a db worker process
#First, release all non-db-worker owned db handles (will recreate if we have to)
    foreach (values %{$::XCAT_DBHS})
    {    #@{$drh->{ChildHandles}}) {
        if ($_) { $_->disconnect(); }
        $_->{InactiveDestroy} = 1;
        undef $_;
    }
    $::XCAT_DBHS={};
    $dbobjsforhandle={};#TODO: It's not said explicitly, but this means an 
    #existing TABLE object is useless if going into db worker.  Table objects
    #must be recreated after the transition.  Only xcatd should have to
    #worry about it.  This may warrant being done better, making a Table
    #object meaningfully survive in much the same way it survives a DB handle
    #migration in handle_dbc_request


    $dbworkerpid = fork;
    xCAT::NodeRange::reset_db(); #do in both processes, to be sure

    unless (defined $dbworkerpid) {
        die "Error spawining database worker";
    }
    unless ($dbworkerpid) {
        $intendedpid = $$;
        $SIG{CHLD} = sub { while (waitpid(-1,WNOHANG) > 0) {}}; #avoid zombies from notification framework
        #This process is the database worker, it's job is to manage database queries to reduce required handles and to permit cross-process caching
        $0 = "xcatd: DB Access";
        use File::Path;
        mkpath('/var/run/xcat/');
        use IO::Socket;
        $SIG{TERM} = $SIG{INT} = sub {
            $exitdbthread=1;
            $SIG{ALRM} = sub { exit 0; };
            alarm(10);
        };
        unlink($dbsockpath);
        umask(0077);
        $dbworkersocket = IO::Socket::UNIX->new(Local => $dbsockpath, Type => SOCK_STREAM, Listen => 8192);
        unless ($dbworkersocket) {
            die $!;
        }
        my $currcon;
        my $clientset = new IO::Select;
        $clientset->add($dbworkersocket);

        #setup signal in NotifHandler so that the cache can be updated
        xCAT::NotifHandler::setup($$, 0);

        # NOTE: There's a bug that sometimes the %SIG is cleaned up by accident, but we cannot figure out when and why
        # this happens. The temporary fix is to backup the %SIG and recover it when necessary.
        my %SIGbakup = %SIG;

        while (not $exitdbthread) {
            eval {
                my @ready_socks = $clientset->can_read;
                foreach $currcon (@ready_socks) {
                    if ($currcon == $dbworkersocket) { #We have a new connection to register
                        my $dbconn = $currcon->accept;
                        if ($dbconn) {
                            $clientset->add($dbconn);
                        }
                    } else {
                        eval {
                            handle_dbc_conn($currcon,$clientset);
                            unless (%SIG && defined ($SIG{USR1})) { %SIG = %SIGbakup; }
                        };
                        if ($@) { 
                            my $err=$@;
                            xCAT::MsgUtils->message("S","xcatd: possible BUG encountered by xCAT DB worker ".$err);
                            if ($currcon) {
                                eval { #avoid hang by allowin client to die too
                                    store_fd("*XCATBUGDETECTED*:$err:*XCATBUGDETECTED*\n",$currcon);
        			    $clientset->remove($currcon);
			            close($currcon);
                                };
                            }
                        }
                    }
                }
            };
            if ($@) { #this should never be reached, but leave it intact just in case
                my $err=$@;
                eval { xCAT::MsgUtils->message("S","xcatd: possible BUG encountered by xCAT DB worker ".$err); };
            }
            if ($intendedpid != $$) { #avoid redundant fork
                eval { xCAT::MsgUtils->message("S","Pid $$ shutting itself down because only pid $intendedpid is permitted to be in this area"); };
                exit(0);
            }
        }

        # sleep a while to make sure the client process has done
        sleep 1.5;
        close($dbworkersocket);
        unlink($dbsockpath);
        exit 0;
    }
    return $dbworkerpid;
}
sub handle_dbc_conn {
    my $client = shift;
    my $clientset = shift;
    my $data;
    my $request;
    eval { 
	$request = fd_retrieve($client);
    };
    if ($@ and $@ =~ /^Magic number checking on storable file/) { #this most likely means we ran over the end of available input
        $clientset->remove($client);
        close($client);
    } elsif ($request) {
        my $response;
        my @returndata;
        if ($request->{'wantarray'}) {
            @returndata = handle_dbc_request($request);
        } else {
            @returndata = (scalar(handle_dbc_request($request)));
        }
	store_fd(\@returndata,$client);
        $clientset->remove($client);
        close($client);
    }

}

my %opentables; #USED ONLY BY THE DB WORKER TO TRACK OPEN DATABASES
sub handle_dbc_request {
    my $request = shift;
    my $functionname = $request->{function};
    my $tablename = $request->{tablename};
    my @args = @{$request->{args}};
    my $autocommit = $request->{autocommit};
    my $dbindex;
    foreach $dbindex (keys %{$::XCAT_DBHS}) { #Go through the current open DB handles
        unless ($::XCAT_DBHS->{$dbindex}) { next; } #If we have a stale dbindex entry skip it (should no longer happen with additions to init_dbworker
        unless ($::XCAT_DBHS->{$dbindex} and $::XCAT_DBHS->{$dbindex}->ping) {
            #We have a database that we were unable to reach, migrate database 
            #handles out from under table objects
            my @afflictedobjs = (); #Get the list of objects whose database handle needs to be replaced
            if (defined $dbobjsforhandle->{$::XCAT_DBHS->{$dbindex}}) {
                @afflictedobjs = @{$dbobjsforhandle->{$::XCAT_DBHS->{$dbindex}}};
            } else {
                die "DB HANDLE TRACKING CODE HAS A BUG";
            }
            my $oldhandle = $::XCAT_DBHS->{$dbindex}; #store old handle off 
            $::XCAT_DBHS->{$dbindex} = $::XCAT_DBHS->{$dbindex}->clone(); #replace broken db handle with nice, new, working one
	    unless ($::XCAT_DBHS->{$dbindex}) { #this means the clone failed
		#most likely result is the DB is down
		#restore the old broken handle
		#so that future recovery attempts have a shot
		#a broken db handle we can recover, no db handle we cannot
		$::XCAT_DBHS->{$dbindex} = $oldhandle;
		return undef;
	    }
            $dbobjsforhandle->{$::XCAT_DBHS->{$dbindex}} = $dbobjsforhandle->{$oldhandle}; #Move the map of depenednt objects to the new handle
            foreach (@afflictedobjs) {  #migrate afflicted objects to the new DB handle
                $$_->{dbh} = $::XCAT_DBHS->{$dbindex};
            }   
            delete $dbobjsforhandle->{$oldhandle}; #remove the entry for the stale handle
            $oldhandle->disconnect(); #free resources associated with dead handle
        }   
    }   
    if ($functionname eq 'new') {
        unless ($opentables{$tablename}->{$autocommit}) {
            shift @args; #Strip repeat class stuff
            $opentables{$tablename}->{$autocommit} = xCAT::Table->new(@args);
        }
        if ($opentables{$tablename}->{$autocommit}) {
	   if ($opentables{$tablename}->{$autocommit^1}) {
               $opentables{$tablename}->{$autocommit}->{cachepeer}=$opentables{$tablename}->{$autocommit^1};
               $opentables{$tablename}->{$autocommit^1}->{cachepeer}=$opentables{$tablename}->{$autocommit};
           }
           return 1;
        } else {
            return 0;
        }
    } else { 
        unless (defined $opentables{$tablename}->{$autocommit}) {
        #We are servicing a Table object that used to be 
        #non data-worker.  Create a new DB worker side Table like the one
        #that requests this
            $opentables{$tablename}->{$autocommit} = xCAT::Table->new($tablename,-create=>0,-autocommit=>$autocommit);
            unless ($opentables{$tablename}->{$autocommit}) {
                return undef;
            }
	    if ($opentables{$tablename}->{$autocommit^1}) {
               $opentables{$tablename}->{$autocommit}->{cachepeer}=$opentables{$tablename}->{$autocommit^1};
               $opentables{$tablename}->{$autocommit^1}->{cachepeer}=$opentables{$tablename}->{$autocommit};
            }
        }
    }
    if ($functionname eq 'getAllAttribs') {
         return $opentables{$tablename}->{$autocommit}->getAllAttribs(@args);
    } elsif ($functionname eq 'getAttribs') {
         return $opentables{$tablename}->{$autocommit}->getAttribs(@args);
    } elsif ($functionname eq 'getTable') {
         return $opentables{$tablename}->{$autocommit}->getTable(@args);
    } elsif ($functionname eq 'getAllNodeAttribs') {
         return $opentables{$tablename}->{$autocommit}->getAllNodeAttribs(@args);
    } elsif ($functionname eq 'getAllEntries') {
         return $opentables{$tablename}->{$autocommit}->getAllEntries(@args);
    } elsif ($functionname eq 'getMAXMINEntries') {
         return $opentables{$tablename}->{$autocommit}->getMAXMINEntries(@args);
    } elsif ($functionname eq 'writeAllEntries') {
         return $opentables{$tablename}->{$autocommit}->writeAllEntries(@args);
    } elsif ($functionname eq 'getAllAttribsWhere') {
         return $opentables{$tablename}->{$autocommit}->getAllAttribsWhere(@args);
    } elsif ($functionname eq 'writeAllAttribsWhere') {
         return $opentables{$tablename}->{$autocommit}->writeAllAttribsWhere(@args);
    } elsif ($functionname eq 'addAttribs') {
         return $opentables{$tablename}->{$autocommit}->addAttribs(@args);
    } elsif ($functionname eq 'setAttribs') {
         return $opentables{$tablename}->{$autocommit}->setAttribs(@args);
    } elsif ($functionname eq 'setAttribsWhere') {
         return $opentables{$tablename}->{$autocommit}->setAttribsWhere(@args);
    } elsif ($functionname eq 'delEntries') {
         return $opentables{$tablename}->{$autocommit}->delEntries(@args);
    } elsif ($functionname eq 'commit') {
         return $opentables{$tablename}->{$autocommit}->commit(@args);
    } elsif ($functionname eq 'rollback') {
         return $opentables{$tablename}->{$autocommit}->rollback(@args);
    } elsif ($functionname eq 'getNodesAttribs') {
         return $opentables{$tablename}->{$autocommit}->getNodesAttribs(@args);
    } elsif ($functionname eq 'setNodesAttribs') {
         return $opentables{$tablename}->{$autocommit}->setNodesAttribs(@args);
    } elsif ($functionname eq 'getNodeAttribs') {
         return $opentables{$tablename}->{$autocommit}->getNodeAttribs(@args);
    } elsif ($functionname eq '_set_use_cache') {
         return $opentables{$tablename}->{$autocommit}->_set_use_cache(@args);
    } elsif ($functionname eq '_build_cache') {
         return $opentables{$tablename}->{$autocommit}->_build_cache(@args);
    } else {
        die "undefined function $functionname";
    }
}

sub _set_use_cache {
    my $self = shift;
    if ($dbworkerpid) {
        return dbc_call($self,'_set_use_cache',@_);
    }
    
    my $usecache = shift;
    if ($usecache and not $self->{_tablecache}) {
	return; #do not allow cache to be enabled while the cache is broken
    }
    $self->{_use_cache} = $usecache;
}
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

Currently implements the preferred SQLite backend, as well as a CSV backend, postgresql and MySQL, using their respective perl DBD modules.

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
    my $xcatcfg = shift;
    my $retv  = "CREATE TABLE $tabn (\n  ";
    my $col;
    my $types=$descr->{types};
    my $delimitedcol;
    foreach $col (@{$descr->{cols}})
    {
        my $datatype;
        if ($xcatcfg =~ /^DB2:/){
         $datatype=get_datatype_string_db2($col, $types, $tabn,$descr);
        } else {
         $datatype=get_datatype_string($col,$xcatcfg, $types);
        }
        if ($datatype eq "TEXT") {
	    if (isAKey(\@{$descr->{keys}}, $col)) {   # keys need defined length
              
		$datatype = "VARCHAR(128) ";
	    }
	}  
        # delimit the columns of the table
	$delimitedcol= &delimitcol($col);	
	$retv .= $delimitedcol . " $datatype";  # mysql change

        
        if (grep /^$col$/, @{$descr->{required}})
        { 
            # will have already put in NOT NULL, if DB2 and a key
            if (!($xcatcfg =~ /^DB2:/)){   # not a db2 key
              $retv .= " NOT NULL";
            } else { # is DB2
	      if (!(isAKey(\@{$descr->{keys}}, $col))) {   # not a key
                 $retv .= " NOT NULL";
              } 
            }
        }
        $retv .= ",\n  ";
    }
    
    if ($retv =~ /PRIMARY KEY/) {
	$retv =~ s/,\n  $/\n)/;
    } else {
	$retv .= "PRIMARY KEY (";
	foreach (@{$descr->{keys}})
	{

	      $delimitedcol= &delimitcol($_);	
	      $retv .= $delimitedcol . ",";  
	}
	$retv =~ s/,$/)\n)/;
    }
    $retv =~ s/,$/)\n)/;
    # allow engine change for mysql
    if ($descr->{engine}) {
       if ($xcatcfg =~ /^mysql:/) {  #for mysql
	  $retv .= " ENGINE=$descr->{engine} ";
       }
    }
    # allow compression for DB2 
    if ($descr->{compress}) {
       if ($xcatcfg =~ /^DB2:/) {  #for DB2 
	  $retv .= " compress $descr->{compress} ";
       }
    }
    # allow tablespace change for DB2 
    if ($descr->{tablespace}) {
       if ($xcatcfg =~ /^DB2:/) {  #for DB2 
	  $retv .= " in $descr->{tablespace} ";
       }
    }
	#print "retv=$retv\n";
    return $retv; 
}

#--------------------------------------------------------------------------

=head3   

    Description: get_datatype_string ( for mysql,sqlite,postgresql) 

    Arguments:
                Table column,database,types 
    Returns:
              the datatype for the column being defined 
    Globals:

    Error:

    Example:

        my $datatype=get_datatype_string($col,$xcatcfg, $types);

=cut

#--------------------------------------------------------------------------------
sub get_datatype_string {
    my $col=shift;    #column name
    my $xcatcfg=shift;  #db config string
    my $types=shift;  #hash pointer
    my $ret;

    if (($types) && ($types->{$col})) {
	if ($types->{$col} =~ /INTEGER AUTO_INCREMENT/) {
	    if ($xcatcfg =~ /^SQLite:/) {
		$ret = "INTEGER PRIMARY KEY AUTOINCREMENT";
	    } elsif ($xcatcfg =~ /^Pg:/) {
		$ret = "SERIAL";
	    } elsif ($xcatcfg =~ /^mysql:/){
		$ret = "INTEGER AUTO_INCREMENT";
	    } else {
	    }
	} else {
	    $ret = $types->{$col};
	}
    } else {
       $ret = "TEXT";
    }
    return $ret;
}

#--------------------------------------------------------------------------

=head3   

    Description: get_datatype_string_db2 ( for DB2) 

    Arguments:
                Table column,database,types,tablename,table schema 
    Returns:
              the datatype for the column being defined 
    Globals:

    Error:

    Example:

        my $datatype=get_datatype_string_db2($col, $types,$tablename,$descr);

=cut

#--------------------------------------------------------------------------------
sub get_datatype_string_db2 {
    my $col=shift;    #column name
    my $types=shift;  #types field (eventlog)
    my $tablename=shift;  # tablename
    my $descr=shift;  # table schema
    my $ret = "varchar(512)";  # default for most attributes
    if (($types) && ($types->{$col})) {
	if ($types->{$col} =~ /INTEGER AUTO_INCREMENT/) {
		$ret = "INTEGER GENERATED ALWAYS AS IDENTITY";  
	} else {
          # if the column is a key 
          if (isAKey(\@{$descr->{keys}}, $col)) { 
	    $ret = $types->{$col};
            $ret .= " NOT NULL ";  
          } else {
	    $ret = $types->{$col};
            if ($ret eq "TEXT") {  # text not in db2
              $ret = "VARCHAR(512)";  
	    }
	  }
	}
    } else {  # type not specifically define
          if (isAKey(\@{$descr->{keys}}, $col)) { 
            $ret = "VARCHAR(128) NOT NULL ";  
          }
    }
    if ($col eq "disable") {
         
       $ret = "varchar(8)";
    }
    if ($col eq "rawdata") {  # from eventlog table
         
       $ret = "varchar(4098)";
    }
    return $ret;
}

#--------------------------------------------------------------------------

=head3   

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
    ($xcatcfg =~ /^$/) && die "Can't locate xCAT configuration";
    unless ($xcatcfg =~ /:/)
    {
        $xcatcfg = "SQLite:" . $xcatcfg;
    }
    return $xcatcfg;
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
    my @args = @_;
    my $self  = {};
    my $proto = shift;
    $self->{tabname} = shift;
    unless (defined($xCAT::Schema::tabspec{$self->{tabname}})) { return undef; }
    $self->{schema}   = $xCAT::Schema::tabspec{$self->{tabname}};
    $self->{colnames} = \@{$self->{schema}->{cols}};
    $self->{descriptions} = \%{$self->{schema}->{descriptions}};
    my %otherargs  = @_;
    my $create = 1;
    if (exists($otherargs{'-create'}) && ($otherargs{'-create'}==0)) {$create = 0;}
    $self->{autocommit} = $otherargs{'-autocommit'};
    unless (defined($self->{autocommit}))
    {
        $self->{autocommit} = 1;
    }
    $self->{realautocommit} = $self->{autocommit}; #Assume requester autocommit behavior maps directly to DBI layer autocommit
    my $class = ref($proto) || $proto;
    if ($dbworkerpid) {
        my $request = { 
            function => "new",
            tablename => $self->{tabname},
            autocommit => $self->{autocommit},
            args=>\@args,
        };
        unless (dbc_submit($request)) {
            return undef;
        }
    } else { #direct db access mode
        if ($opentables{$self->{tabname}}->{$self->{autocommit}}) { #if we are inside the db worker and asked to create a new table that is already open, just return a reference to that table
								    #generally speaking, this should cause a lot of nodelists to be shared
		return $opentables{$self->{tabname}}->{$self->{autocommit}};
        }
        $self->{dbuser}="";
        $self->{dbpass}="";

	my $xcatcfg =get_xcatcfg();
        my $xcatdb2schema;
        if ($xcatcfg =~ /^DB2:/) {  # for DB2 , get schema name
         my @parts =  split ( '\|', $xcatcfg);
         $xcatdb2schema = $parts[1];
         $xcatdb2schema =~ tr/a-z/A-Z/;    # convert to upper 
        }

        if ($xcatcfg =~ /^SQLite:/)
        {
            $self->{backend_type} = 'sqlite';
            $self->{realautocommit} = 1; #Regardless of autocommit semantics, only electively do autocommit due to SQLite locking difficulties
            #for SQLite, we cannot open the same db twice without deadlock risk, so we cannot have both autocommit on and off via
            #different handles, so we pick one
            #previously, Table.pm tried to imitate autocommit, but evidently was problematic, so now SQLite is just almost always
            #autocommit, turned off very selectively
            #so realautocommit is a hint to say that the handle needs to be set back to autocommit as soon as possible
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
        if ($xcatcfg =~ /^DB2:/) {  # for DB2 ,export the INSTANCE name
           $ENV{'DB2INSTANCE'} = $self->{dbuser};
        } 
        
        my $oldumask= umask 0077;
        unless ($::XCAT_DBHS->{$self->{connstring},$self->{dbuser},$self->{dbpass},$self->{realautocommit}}) { #= $self->{tabname};
          $::XCAT_DBHS->{$self->{connstring},$self->{dbuser},$self->{dbpass},$self->{realautocommit}} =
            DBI->connect($self->{connstring}, $self->{dbuser}, $self->{dbpass}, {AutoCommit => $self->{realautocommit}});
         }
         umask $oldumask;

        $self->{dbh} = $::XCAT_DBHS->{$self->{connstring},$self->{dbuser},$self->{dbpass},$self->{realautocommit}};
        #Store the Table object reference as afflicted by changes to the DBH
        #This for now is ok, as either we aren't in DB worker mode, in which case this structure would be short lived...
        #or we are in db worker mode, in which case Table objects live indefinitely
        #TODO: be able to reap these objects sanely, just in case
        push @{$dbobjsforhandle->{$::XCAT_DBHS->{$self->{connstring},$self->{dbuser},$self->{dbpass},$self->{realautocommit}}}},\$self;
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
                                      $xCAT::Schema::tabspec{$self->{tabname}},
                      $xcatcfg);
                    $self->{dbh}->do($str);
                    if (!$self->{dbh}->{AutoCommit}) {
                        $self->{dbh}->commit;
                    }
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
                                  $xCAT::Schema::tabspec{$self->{tabname}},
                      $xcatcfg);
                $self->{dbh}->do($str);
            }
        } else { #generic DBI
           if (!$self->{dbh})
           {
			   xCAT::MsgUtils->message("S", "Could not connect to the database. Database handle not defined.");

               return undef;
           }
           my $tbexistq;
           my $dbtablename=$self->{tabname};
           my $found = 0;
           if ($xcatcfg =~ /^DB2:/) {  # for DB2 
              $dbtablename  =~ tr/a-z/A-Z/;    # convert to upper 
              $tbexistq = $self->{dbh}->table_info(undef,$xcatdb2schema,$dbtablename,'TABLE');
           } else {  
              $tbexistq = $self->{dbh}->table_info('','',$self->{tabname},'TABLE');
           }
           while (my $data = $tbexistq->fetchrow_hashref) {
            if ($data->{'TABLE_NAME'} =~ /^\"?$dbtablename\"?\z/) {
              if ($xcatcfg =~ /^DB2:/) {  # for DB2
                 if ($data->{'TABLE_SCHEM'}  =~ /^\"?$xcatdb2schema\"?\z/) {
                   # must check schema also with db2
                     $found = 1;
                       last;
                 }
              } else {  # not db2
                 $found = 1;
                 last;
              }
            }
           }

  
           unless ($found) {
              unless ($create)
              {
                 return undef;
              }
              my $str =
               buildcreatestmt($self->{tabname},
                               $xCAT::Schema::tabspec{$self->{tabname}},
                       $xcatcfg);
               $self->{dbh}->do($str);
               if (!$self->{dbh}->{AutoCommit}) {
	         $self->{dbh}->commit;  #  commit the create
               }
              
          }
         } # end Generic DBI


    } #END DB ACCESS SPECIFIC SECTION
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

    Description: Alters table info in the database based on Schema changes
                 Handles adding attributes
                 Handles removing attributes but does not really remove them
                 from the database.
                 Handles adding keys  

    Arguments: Hash containing Database and Table Handle and schema

    Returns: None

    Globals:

    Error:

    Example: my $nodelisttab=xCAT::Table->new('nodelist');
             $nodelisttab->updateschema(); 
	     $nodelisttab->close();
 
    Comments:
        none

=cut

#--------------------------------------------------------------------------------
sub updateschema
{

    #This determines alter table statements required..
    my $self = shift;
    my $descr=$xCAT::Schema::tabspec{$self->{tabname}};
    my $tn=$self->{tabname};
    my $xcatdb2schema;
    my $xcatcfg=get_xcatcfg();
    my $rc=0;
    my $msg;
    if ($xcatcfg =~ /^DB2:/) {  # for DB2 , get schema name
      my @parts =  split ( '\|', $xcatcfg);
      $xcatdb2schema = $parts[1];
      $xcatdb2schema =~ tr/a-z/A-Z/;    # convert to upper 
    }

    my @columns;
    my %dbkeys;
    if ($self->{backend_type} eq 'sqlite')
    {
        my $dbexistq =
          "PRAGMA table_info('$tn')";
        my $sth = $self->{dbh}->prepare($dbexistq);
        $sth->execute;
            my $tn=$self->{tabname};
        while ( my $col_info = $sth->fetchrow_hashref ) {
	    #print Dumper($col_info);
            my $tmp_col=$col_info->{name};
            $tmp_col =~ s/"//g;
	    push @columns, $tmp_col;
	    if ($col_info->{pk}) {
		$dbkeys{$tmp_col}=1;
	    }
	}
        $sth->finish;
    } else { #Attempt generic dbi..
       #my $sth = $self->{dbh}->column_info('','',$self->{tabname},'');
       my $sth;
       if ($xcatcfg =~ /^DB2:/) {  # for DB2 
          my $db2table = $self->{tabname};
          $db2table =~ tr/a-z/A-Z/;    # convert to upper for db2 
          $sth = $self->{dbh}->column_info(undef,$xcatdb2schema,$db2table,'%'); 
       } else {
          $sth = $self->{dbh}->column_info(undef,undef,$self->{tabname},'%'); 
       }
       while (my $cd = $sth->fetchrow_hashref) {
           #print Dumper($cd);
           push @columns,$cd->{'COLUMN_NAME'};

           #special code for old version of perl-DBD-mysql
           if (defined($cd->{mysql_is_pri_key}) && ($cd->{mysql_is_pri_key}==1)) {
               my $tmp_col=$cd->{'COLUMN_NAME'};
               $tmp_col =~ s/"//g;
               $dbkeys{$tmp_col}=1;
 	   }
       }
	foreach (@columns) { #Column names may end up quoted by database engin
		s/"//g;
	}

       #get primary keys
       if ($xcatcfg =~ /^DB2:/) {  # for DB2 
          my $db2table = $self->{tabname};
          $db2table =~ tr/a-z/A-Z/;    # convert to upper for db2 
          $sth = $self->{dbh}->primary_key_info(undef,$xcatdb2schema,$db2table); 
       } else {
          $sth = $self->{dbh}->primary_key_info(undef,undef,$self->{tabname});
       }
       if ($sth) {
           my $data = $sth->fetchall_arrayref;
           #print "data=". Dumper($data);
           foreach my $cd (@$data) {
               my $tmp_col=$cd->[3];
               $tmp_col =~ s/"//g;
               $dbkeys{$tmp_col}=1;
           }      
        }
    }

    #Now @columns reflects the *actual* columns in the database
    my $dcol;
    my $types=$descr->{types};

    foreach $dcol (@{$self->{colnames}})
    {
        unless (grep /^$dcol$/, @columns)
        {
            #TODO: log/notify of schema upgrade?
            my $datatype;
            if ($xcatcfg =~ /^DB2:/){
             $datatype=get_datatype_string_db2($dcol, $types, $tn,$descr);
            } else{
             $datatype=get_datatype_string($dcol, $xcatcfg, $types);
            }
            if ($datatype eq "TEXT") {   # keys cannot be TEXT
	      if (isAKey(\@{$descr->{keys}}, $dcol)) {   # keys 
	         $datatype = "VARCHAR(128) ";
	      }
	    }

	    if (grep /^$dcol$/, @{$descr->{required}})
	    {
	 	    $datatype .= " NOT NULL";
	    }
            # delimit the columns of the table
	    my $tmpcol= &delimitcol($dcol);	

            my $tablespace;
            my $stmt =
                  "ALTER TABLE " . $self->{tabname} . " ADD $tmpcol $datatype";
            $self->{dbh}->do($stmt);
            $msg="updateschema: Running $stmt"; 
	    xCAT::MsgUtils->message("S", $msg);
	    if ($self->{dbh}->errstr) {
	        xCAT::MsgUtils->message("S", "Error adding columns for table " . $self->{tabname} .":" . $self->{dbh}->errstr);
                if ($xcatcfg =~ /^DB2:/){  # see if table space error
                  my $error = $self->{dbh}->errstr;
                  if ($error =~ /54010/) {
                  # move the table to the next tablespace
                    if ($error =~ /USERSPACE1/) {
                      $tablespace="XCATTBS16K";
                    } else { 
                      $tablespace="XCATTBS32K";
                    }
                    my $tablename=$self->{tabname};
                    $tablename=~ tr/a-z/A-Z/; # convert to upper
                    $msg="Moving table $self->{tabname} to $tablespace"; 
	            xCAT::MsgUtils->message("S", $msg);
                    my $stmt2="Call sysproc.admin_move_table('XCATDB',\'$tablename\',\'$tablespace\',\'$tablespace\',\'$tablespace\','','','','','','MOVE')";
                    $self->{dbh}->do($stmt2);
	            if ($self->{dbh}->errstr) {
	             xCAT::MsgUtils->message("S", "Error on tablespace move  for table " . $self->{tabname} .":" . $self->{dbh}->errstr);
                    } else {  # tablespace move try column add again
                       if (!$self->{dbh}->{AutoCommit}) { # commit tbsp move
                         $self->{dbh}->commit;
                       }
                        $self->{dbh}->do($stmt);
                    }

                  }  # if tablespace error
                  
	        } # if db2
	     }  # error on add column
             if (!$self->{dbh}->{AutoCommit}) { # commit add column 
                $self->{dbh}->commit;
             }
        }
    }

    #for existing columns that are new keys now
    # note new keys can only be created from existing columns 
    # since keys cannot be null, the copy from the backup table will fail if
    # the old value was null.

    my @new_dbkeys=@{$descr->{keys}};
    my @old_dbkeys=keys %dbkeys;
    #print "new_dbkeys=@new_dbkeys;  old_dbkeys=@old_dbkeys; columns=@columns\n";
    my $change_keys=0;
    #Add the new key columns to the table
    foreach my $dbkey (@new_dbkeys) {
        if (! exists($dbkeys{$dbkey})) { 
	    $change_keys=1; 
            # Call tabdump plugin to create a CSV file
            # can be used in case the restore fails
            # put in /tmp/<tablename.csv.pid>
            my $backuptable="/tmp/$tn.csv.$$";
            my $cmd="$::XCATROOT/sbin/tabdump $tn > $backuptable";
            `$cmd`;
             $msg="updateschema: Backing up table before key change, $cmd"; 
	     xCAT::MsgUtils->message("S", $msg);
 
            #for my sql, we do not have to recreate table, but we have to make sure the type is correct, 
            my $datatype;
            if ($xcatcfg =~ /^mysql:/) { 
	      $datatype=get_datatype_string($dbkey, $xcatcfg, $types);
            } else {   # db2 
	      $datatype=get_datatype_string_db2($dbkey, $types, $tn,$descr);
            }
            if ($datatype eq "TEXT") { 
		    if (isAKey(\@{$descr->{keys}}, $dbkey)) {   # keys need defined length
		        $datatype = "VARCHAR(128) ";
		    }
            }
		
            # delimit the columns
	    my $tmpkey= &delimitcol($dbkey);	
            if (($xcatcfg =~ /^DB2:/) || ($xcatcfg =~ /^Pg:/)) {  
                  # get rid of NOT NULL, cannot modify with NOT NULL
                  my ($tmptype,$nullvalue)= split('NOT NULL',$datatype );
                  $datatype=$tmptype; 
                   
            } 
	    my $stmt;
            if ($xcatcfg =~ /^DB2:/){
	     $stmt =
		    "ALTER TABLE " . $self->{tabname} . " ALTER COLUMN $tmpkey SET DATA TYPE $datatype";
            } else {
	     $stmt =
		    "ALTER TABLE " . $self->{tabname} . " MODIFY COLUMN $tmpkey $datatype";
            } 
             $msg="updateschema: Running $stmt"; 
	     xCAT::MsgUtils->message("S", $msg);
	     #print "stmt=$stmt\n";
  	     $self->{dbh}->do($stmt);
	     if ($self->{dbh}->errstr) {
		    xCAT::MsgUtils->message("S", "Error changing the keys for table " . $self->{tabname} .":" . $self->{dbh}->errstr);
	     }
        }
    }

    #finally  add the new keys
    if ($change_keys) {
	if ($xcatcfg =~ /^mysql:/) {  #for mysql, just alter the table
	    my $tmp=join(',',@new_dbkeys); 
	    my $stmt =
	        "ALTER TABLE " . $self->{tabname} . " DROP PRIMARY KEY, ADD PRIMARY KEY ($tmp)";
	    #print "stmt=$stmt\n";
	    $self->{dbh}->do($stmt);
            $msg="updateschema: Running $stmt"; 
	    xCAT::MsgUtils->message("S", $msg);
            if ($self->{dbh}->errstr) {
		xCAT::MsgUtils->message("S", "Error changing the keys for table " . $self->{tabname} .":" . $self->{dbh}->errstr);
	    }
	} else { #for the rest, recreate the table
            #print "need to change keys\n";
            my $btn=$tn . "_xcatbackup";
            
            #remove the backup table just in case;
            # gets error if not there
            #my $str="DROP TABLE $btn";
	    #$self->{dbh}->do($str);

	    #rename the table name to name_xcatbackup
            my $str;
            if ($xcatcfg =~ /^DB2:/){
	        $str = "RENAME TABLE $tn TO $btn";
            } else {
	        $str = "ALTER TABLE $tn RENAME TO $btn";
            }
	    $self->{dbh}->do($str);
            if (!$self->{dbh}->{AutoCommit}) {
                 $self->{dbh}->commit;
            }
            $msg="updateschema: Running $str"; 
	    xCAT::MsgUtils->message("S", $msg);
	    if ($self->{dbh}->errstr) {
		xCAT::MsgUtils->message("S", "Error renaming the table from $tn to $btn:" . $self->{dbh}->errstr);
	    }
            if (!$self->{dbh}->{AutoCommit}) {
                 $self->{dbh}->commit;
            }

	    #create the table again
	    $str = 
                  buildcreatestmt($tn,
                                  $descr,
				  $xcatcfg);
	    $self->{dbh}->do($str);
	    if ($self->{dbh}->errstr) {
		xCAT::MsgUtils->message("S", "Error recreating table $tn:" . $self->{dbh}->errstr);
	    }
            if (!$self->{dbh}->{AutoCommit}) {
                 $self->{dbh}->commit;
            }

            #copy the data from backup to the table
            $str = "INSERT INTO $tn SELECT * FROM $btn";
	    $self->{dbh}->do($str);
            $msg="updateschema: Running $str"; 
	    xCAT::MsgUtils->message("S", $msg);
	    if ($self->{dbh}->errstr) {
		xCAT::MsgUtils->message("S", "Error copying data from table $btn to $tn:" . $self->{dbh}->errstr);
	    } else {
		#drop the backup table
		$str = "DROP TABLE $btn";
		$self->{dbh}->do($str);
	    }
 
            if (!$self->{dbh}->{AutoCommit}) {
                $self->{dbh}->commit;
           }

	}
    }
    return $rc;
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
    my $nodekey = "node";
    if (defined $xCAT::Schema::tabspec{$self->{tabname}}->{nodecol}) {
        $nodekey = $xCAT::Schema::tabspec{$self->{tabname}}->{nodecol}
    };
    return $self->setAttribs({$nodekey => $node}, @_);
}

#--------------------------------------------------------------------------

=head3  addNodeAttribs  (not supported)

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
    xCAT::MsgUtils->message("S","addNodeAttribs is not supported");
    die "addNodeAttribs is not supported";
    return $self->addAttribs('node', @_);
}

#--------------------------------------------------------------------------

=head3  addAttribs (not supported)

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
    xCAT::MsgUtils->message("S","addAttribs is not supported");
    die "addAttribs is not supported";
    if ($dbworkerpid) {
        return dbc_call($self,'addAttribs',@_);
    }
    if (not $self->{intransaction} and not $self->{autocommit} and $self->{realautocommit}) {
        #I have realized that this needs some comment work
        #so if we are not in a transaction, *but* the current caller context expects autocommit to be off (i.e. fast performance and rollback
        #however, the DBI layer is set to stick to autocommit on as much as possible (pretty much SQLite) because the single
        #handle is shared, we disable autocommit on that handle until commit or rollback is called
        #yes, that means some table calls coming in with expectation of autocommit during this hopefully short interval
        #could get rolled back along with this transaction, but it's unlikely and moving to a more robust DB solves it
        #so it is intentional that autocommit is left off because it is expected that a commit will come along one day and fix it right up
        #TODO: if caller crashes after inducing a 'begin transaction' without commit or rollback, this could be problematic.
        #calling commit on all table handles if a client goes away uncleanly may be a good enough solution.
        $self->{intransaction}=1;
        $self->{dbh}->{AutoCommit}=0;
    }
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
    $sth->finish();

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
    if ($dbworkerpid) {
        return dbc_call($self,'rollback',@_);
    }
    $self->{dbh}->rollback;
    if ($self->{intransaction} and not $self->{autocommit} and $self->{realautocommit}) {
        #on rollback, if sharing a DB handle for autocommit and non-autocommit, put the handle back to autocommit
        $self->{intransaction}=0;
        $self->{dbh}->{AutoCommit}=1;
    }
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
    if ($dbworkerpid) {
        return dbc_call($self,'commit',@_);
    }
    unless ($self->{dbh}->{AutoCommit}) { #caller can now hammer commit function with impunity, even when it makes no sense
        $self->{dbh}->commit;
    }
    if ($self->{intransaction} and not $self->{autocommit} and $self->{realautocommit}) {
        #if realautocommit indicates shared DBH between manual and auto commit, put the handle back to autocommit if a transaction
        #is committed (aka ended)
        $self->{intransaction}=0;
        $self->{dbh}->{AutoCommit}=1;
    }
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
    my $xcatcfg =get_xcatcfg();
    my $self     = shift;
    if ($dbworkerpid) {
        return dbc_call($self,'setAttribs',@_);
    }
    my $pKeypairs=shift;
    my %keypairs = ();
    if ($pKeypairs != undef) { %keypairs = %{$pKeypairs}; }

    #my $key = shift;
    #my $keyval=shift;
    my $elems = shift;
    my $cols  = "";
    my @bind  = ();
    my $action;
    my @notif_data;
    my $qstring;
    $qstring = "SELECT * FROM " . $self->{tabname} . " WHERE ";
    my @qargs   = ();
    my $query;
    my $data;
    if (not $self->{intransaction} and not $self->{autocommit} and $self->{realautocommit}) {
        #search this code for the other if statement just like it for an explanation of why I do this
        $self->{intransaction}=1;
        $self->{dbh}->{AutoCommit}=0;
    }
    if (($pKeypairs != undef) && (keys(%keypairs)>0)) {
	foreach (keys %keypairs)
	{

            # delimit the columns of the table
	    my $delimitedcol = &delimitcol($_);	
            
            if ($xcatcfg =~ /^DB2:/) { # for DB2
	      $qstring .= $delimitedcol . " LIKE ? AND ";  
            } else {
	      $qstring .= $delimitedcol . " = ? AND ";  
            }  

	    push @qargs, $keypairs{$_};
	    
	}
	$qstring =~ s/ AND \z//;
         #print "this is qstring1: $qstring\n";
	$query = $self->{dbh}->prepare($qstring);
	$query->execute(@qargs);
	
	#get the first row
	$data = $query->fetchrow_arrayref();
	if (defined $data)
	{
	    $action = "u";
	}
	else
	{
	    $action = "a";
	}
    } else { $action = "a";}

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

    if ($query) {
	$query->finish();
    }

    if ($action eq "u")
    {

        #update the rows
        $action = "u";
        for my $col (keys %$elems)
        {
           # delimit the columns of the table
	   my $delimitedcol = &delimitcol($col);	
           $cols = $cols . $delimitedcol . " = ?,";
           push @bind, (($$elems{$col} eq "NULL") ? undef: $$elems{$col});
        }
        chop($cols);
        my $cmd ;

        $cmd = "UPDATE " . $self->{tabname} . " set $cols where ";
        foreach (keys %keypairs)
        {
            if (ref($keypairs{$_}))
            {
                # delimit the columns
	        my $delimitedcol = &delimitcol($_);	
                $cmd .= $delimitedcol . " = '" . $keypairs{$_}->[0] . "' AND ";
            }
            else
            {
	        my $delimitedcol = &delimitcol($_);	
                $cmd .= $delimitedcol . " = '" . $keypairs{$_} . "' AND ";
            }
        }
        $cmd =~ s/ AND \z//;
        my $sth = $self->{dbh}->prepare($cmd);
        unless ($sth) {
            return (undef,"Error attempting requested DB operation");
        }
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
        my $needinsert=0;
        for my $col (keys %$elems)
        {
	        $newpairs{$col} = $$elems{$col};
            if (defined $newpairs{$col} and not $newpairs{$col} eq "") {
               $needinsert=1;
            }
        }
        unless ($needinsert) {  #Don't bother inserting truly blank lines
            return;
        }
	foreach (keys %newpairs) {

	   my $delimitedcol = &delimitcol($_);	
           $cols .= $delimitedcol . ","; 
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

    $self->_refresh_cache(); #cache is invalid, refresh
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
    Warning, because we support mulitiple databases (SQLite,MySQL and DB2) that
    require different syntax.  Any code using this routine,  must call the 
    Utils->getDBName routine and code the where clause that is appropriate for
    each supported database.

    Arguments:
         Where clause.
         Note: if the Where clause contains any reserved keywords like
         keys from the site table,  then you will have to code them in backticks
         for MySQL  and not in backticks for Postgresql.
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
	   $tab->setAttribsWhere( "node in ('node1', 'node2', 'node3')", \%updates );
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
    if ($dbworkerpid) {
        return dbc_call($self,'setAttribsWhere',@_);
    }
    my $where_clause = shift;
    my $elems = shift;
    my $cols  = "";
    my @bind  = ();
    my $action;
    my @notif_data;
    if (not $self->{intransaction} and not $self->{autocommit} and $self->{realautocommit}) {
        #search this code for the other if statement just like it for an explanation of why I do this
        $self->{intransaction}=1;
        $self->{dbh}->{AutoCommit}=0;
    }
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
      # delimit the columns of the table
      my $delimitedcol = &delimitcol($col);	
      $cols = $cols . $delimitedcol . " = ?,";
      push @bind, (($$elems{$col} eq "NULL") ? undef: $$elems{$col});
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
=head3 setNodesAttribs

    Description: Unconditionally assigns the requested values to tables for a list of nodes

    Arguments:
        'self' (implicit in OO style call)
        A reference to a two-level hash similar to:
            {
                'n1' => {
                    comments => 'foo',
                    data => 'foo2'
                },
                'n2' => {
                    comments => 'bar',
                    data => 'bar2'
                }
            }

     Alternative arguments (same set of data to be applied to multiple nodes):
        'self'
        Reference to a list of nodes (no noderanges, just nodes)
        A hash of attributes to set, like in 'setNodeAttribs'

    Returns:
=cut
#--------------------------------------------------------------------------
sub setNodesAttribs {
#This is currently a stub to be filled out with at scale enhancements.  It will be a touch more complex than getNodesAttribs, due to the notification
#The three steps should be:
#-Query table and divide nodes into list to update and list to insert
#-Update intelligently with respect to scale
#-Insert intelligently with respect to scale (prepare one statement, execute many times, other syntaxes not universal)
#Intelligently in this case means folding them to some degree.  Update where clauses will be longer, but must be capped to avoid exceeding SQL statement length restrictions on some DBs.  Restricting even all the way down to 256 could provide better than an order of magnitude better performance though
    my $self = shift;
    if ($dbworkerpid) {
        return dbc_call($self,'setNodesAttribs',@_);
    }
    my $nodelist = shift;
    my $keyset = shift;
    my %cols = ();
    my @orderedcols=();
    my $oldac = $self->{dbh}->{AutoCommit}; #save autocommit state
    $self->{dbh}->{AutoCommit}=0; #turn off autocommit for performance
    my $hashrec;
    my $colsmatch=1;
    if (ref $nodelist eq 'HASH') { # argument of the form  { n001 => { groups => 'something' }, n002 => { groups => 'other' } }
        $hashrec = $nodelist;
        my @nodes = keys %$nodelist;
        $nodelist = \@nodes;
        my $firstpass=1;
        foreach my $node (keys %$hashrec) { #Determine whether the passed structure is trying to set the same columns 
                                   #for every node to determine if the short path can work or not
            if ($firstpass) {
                $firstpass=0;
                foreach (keys %{$hashrec->{$node}}) {
                    $cols{$_}=1;
                }
            } else {
                foreach (keys %{$hashrec->{$node}}) { #make sure all columns in this entry are in the first
                    unless (defined $cols{$_}) {
                        $colsmatch=0;
                        last;
                    }
                }
                foreach my $col (keys %cols) { #make sure this entry does not lack any columns from the first
                    unless (defined $hashrec->{$node}->{$col}) {
                        $colsmatch=0;
                        last;
                    }
                }
            }
        }

    } else { #the legacy calling style with a list reference and a single hash reference of col=>va/ue pairs
        $hashrec = {};
        foreach (@$nodelist) {
            $hashrec->{$_}=$keyset;
        }
        foreach (keys %$keyset) {
            $cols{$_}=1;
        }
    }
    #revert to the old way if notification is required or asymettric setNodesAttribs was requested with different columns
    #for different nodes
    if (not $colsmatch or xCAT::NotifHandler->needToNotify($self->{tabname}, 'u') or xCAT::NotifHandler->needToNotify($self->{tabname}, 'a')) {
        #TODO: enhance performance of this case too, for now just call the notification-capable code per node
        foreach  (keys %$hashrec) {
            $self->setNodeAttribs($_,$hashrec->{$_});
        }
        $self->{dbh}->commit; #commit pending transactions
        $self->{dbh}->{AutoCommit}=$oldac;#restore autocommit semantics
        return;
    }
    #this code currently is notification incapable.  It enhances scaled setting by:
    #-turning off autocommit if on (done for above code too, but to be clear document the fact here too
    #-executing one select statement per set of nodes instead of per node (chopping into 1,000 node chunks for SQL statement length
    #-aggregating update statements
    #-preparing one insert statement and re-execing it (SQL-92 multi-row insert isn't ubiquitous enough)

    my $nodekey = "node";
    if (defined $xCAT::Schema::tabspec{$self->{tabname}}->{nodecol}) {
       $nodekey = $xCAT::Schema::tabspec{$self->{tabname}}->{nodecol}
    };
    @orderedcols = keys %cols; #pick a specific column ordering explicitly to assure consistency
    my @sqlorderedcols=();
    # must quote to protect from reserved DB keywords
    foreach my $col (@orderedcols) {
       my $delimitedcol = &delimitcol($col);	
       push @sqlorderedcols, $delimitedcol; 
    }
    #use Data::Dumper;
    my $nodesatatime = 999; #the update case statement will consume '?' of which we are allowed 999 in the most restricted DB we support
    #ostensibly, we could do 999 at a time for the select statement, and subsequently limit the update aggregation only
    #to get fewer sql statements, but the code is probably more complex than most people want to read
    #at the moment anyway
    my @currnodes = splice(@$nodelist,0,$nodesatatime); #Do a few at a time to stay under max sql statement length and max variable count
    my $insertsth; #if insert is needed, this will hold the single prepared insert statement
    my $upsth;

    my $dnodekey = &delimitcol($nodekey);	
    while (scalar @currnodes) {
       my %updatenodes=();
       my %insertnodes=();
       my $qstring;
       #sort nodes into inserts and updates
       $qstring = "SELECT * FROM " . $self->{tabname} . " WHERE $dnodekey in (";
       $qstring .= '?, ' x scalar(@currnodes);
       $qstring =~ s/, $/)/;
       my $query = $self->{dbh}->prepare($qstring);
       $query->execute(@currnodes);
       my $rec;
	    while ($rec = $query->fetchrow_hashref()) {
            $updatenodes{$rec->{$nodekey}}=1;
       }
       if (scalar keys %updatenodes < scalar @currnodes) {
            foreach (@currnodes) {
                unless ($updatenodes{$_}) {
                    $insertnodes{$_}=1;
                }
            }
       }
        my $havenodecol; #whether to put node first in execute arguments or let it go naturally
        if (not $insertsth and keys %insertnodes) { #prepare an insert statement since one will be needed
            my $columns="";
            my $bindhooks="";
            $havenodecol = defined $cols{$nodekey};
            unless ($havenodecol) {
               $columns = "$dnodekey, ";
               $bindhooks="?, ";
            }
            $columns .= join(", ",@sqlorderedcols);
            $bindhooks .= "?, " x scalar @sqlorderedcols;
            $bindhooks =~ s/, $//;
            $columns =~ s/, $//;
            my $instring = "INSERT INTO ".$self->{tabname}." ($columns) VALUES ($bindhooks)";
            #print $instring;
            $insertsth = $self->{dbh}->prepare($instring);
        }
        foreach my $node (keys %insertnodes) {
            my @args = ();
            unless ($havenodecol) {
                @args = ($node);
            }
            foreach my $col (@orderedcols) {
                push @args,$hashrec->{$node}->{$col};
            }
            $insertsth->execute(@args);
        }
        if (not $upsth and keys %updatenodes) { #prepare an insert statement since one will be needed
            my $upstring = "UPDATE ".$self->{tabname}." set ";
            foreach my $col (@sqlorderedcols) { #try aggregating requests.  Could also see about single prepare, multiple executes instead
              $upstring .= "$col = ?, ";
            }
            if (grep { $_ eq $nodekey } @orderedcols) {
                $upstring =~ s/, \z//;
            } else {
                $upstring =~ s/, \z/ where $dnodekey = ?/;
            }
            $upsth = $self->{dbh}->prepare($upstring);
        }
        if (scalar keys %updatenodes) {
            my $upstring = "UPDATE ".$self->{tabname}." set ";
            foreach my $node (keys %updatenodes) {
                my @args=();
                foreach my $col (@orderedcols) { #try aggregating requests.  Could also see about single prepare, multiple executes instead
                   push @args,$hashrec->{$node}->{$col};
                }
                push @args,$node;
                $upsth->execute(@args);
            }
        }
        @currnodes = splice(@$nodelist,0,$nodesatatime);
    }
    $self->{dbh}->commit; #commit pending transactions
    $self->{dbh}->{AutoCommit}=$oldac;#restore autocommit semantics
    $self->_refresh_cache(); #cache is invalid, refresh
}

#--------------------------------------------------------------------------

=head3 getNodesAttribs

    Description: Retrieves the requested attributes for a node list

    Arguments:
            Table handle ('self')
			List ref of nodes
	        Attribute type array
    Returns:

			two layer hash reference (->{nodename}->{attrib} 
    Globals:

    Error:

    Example:
           my $ostab = xCAT::Table->new('nodetype');
		   my $ent = $ostab->getNodesAttribs(\@nodes,['profile','os','arch']);
           if ($ent) { print $ent->{n1}->{profile}

    Comments:
        Using this function will clue the table layer into the atomic nature of the request, and allow shortcuts to be taken as appropriate to fulfill the request at scale.

=cut

#--------------------------------------------------------------------------------
sub getNodesAttribs {
    my $self = shift;
    if ($dbworkerpid) {
        return dbc_call($self,'getNodesAttribs',@_);
    }
    my $nodelist = shift;
    unless ($nodelist) { $nodelist = []; } #common to be invoked with undef seemingly
    my %options=();
    my @attribs;
    if (ref $_[0]) {
        @attribs = @{shift()};
        %options = @_;
    } else {
        @attribs = @_;
    }
    my @realattribs = @attribs; #store off the requester attribute list, the cached columns may end up being a superset and we shouldn't return more than asked
	#it should also be the case that cache will be used if it already is in play even if below cache threshold.  This would be desired behavior
    if (scalar(@$nodelist) > $cachethreshold) {
        $self->{_use_cache} = 0;
        $self->{nodelist}->{_use_cache}=0;
        if ($self->{tabname} eq 'nodelist') { #a sticky situation
            my @locattribs=@attribs;
            unless (grep(/^node$/,@locattribs)) {
                push @locattribs,'node';
            }
            unless (grep(/^groups$/,@locattribs)) {
                push @locattribs,'groups';
            }
            $self->_build_cache(\@locattribs);
        } else {
            $self->_build_cache(\@attribs);
            $self->{nodelist}->_build_cache(['node','groups']);
        }
        $self->{_use_cache} = 1;
        $self->{nodelist}->{_use_cache}=1;
    }
    my $rethash;
    foreach (@$nodelist) {
        my @nodeentries=$self->getNodeAttribs($_,\@realattribs,%options);
        $rethash->{$_} = \@nodeentries; #$self->getNodeAttribs($_,\@attribs);
    }
    $self->{_use_cache} = 0;
    if ($self->{tabname} ne 'nodelist') { 
	    $self->{nodelist}->{_use_cache} = 0;
    }
    return $rethash;
}

sub _refresh_cache { #if cache exists, force a rebuild, leaving reference counts alone
    my $self = shift; #dbworker check not currently required
    if ($self->{cachepeer}->{_cachestamp}) { $self->{cachepeer}->{_cachestamp}=0; }
    if ($self->{_use_cache}) { #only do things if cache is set up
        $self->_build_cache(1); #for now, rebuild the whole thing.
                    #in the future, a faster cache update may be possible
                    #however, the payoff may not be worth it
                    #as this case is so rare
                    #the only known case that trips over this is:
                    #1st noderange starts being expanded
                    #the nodelist is updated by another process
                    #2nd noderange  starts being expanded (sharing first cache)
                    #   (uses stale nodelist data and misses new nodes, the error)
                    #1st noderange finishes
                    #2nd noderange finishes
    } else { #even if a cache is not in use *right this second*, we need to mark any cached data that may exist as invalid, do so by suggesting the cache is from 1970
	if ($self->{_cachestamp}) { $self->{_cachestamp}=0; }
    }
    return;
}

sub _build_cache { #PRIVATE FUNCTION, PLEASE DON'T CALL DIRECTLY
#TODO: increment a reference counter type thing to preserve current cache
#Also, if ref count is 1 or greater, and the current cache is less than 3 seconds old, reuse the cache?
    my $self = shift;
    if ($dbworkerpid) {
        return dbc_call($self,'_build_cache',@_);
    }
    my $attriblist = shift;
    my %copts = @_;
    my $refresh = not ref $attriblist; #if attriblist is not a reference, it is a refresh request
    if (not ref $attriblist) {
       $attriblist = $self->{_cached_attriblist}; #need attriblist to mean something, don't know how this didn't break horribly already
    }
    
    if (not $refresh and $self->{_cache_ref}) { #we have active cache reference, increment counter and return
	my $currattr;
	my $cachesufficient=1;
	foreach $currattr (@$attriblist) { #if any of the requested attributes are not cached, we must rebuild
	   unless (grep { $currattr eq  $_ } @{$self->{_cached_attriblist}}) {
	      $cachesufficient=0;
	      last;
	   }
	}
        if ($self->{_cachestamp} < (time()-5)) { #NEVER use a cache older than 5 seconds
		$cachesufficient=0;
	}
        
	if ($cachesufficient) { return; }
	#cache is insufficient, now we must do the converse of above
	#must add any currently cached columns to new list if not requested
	foreach $currattr (@{$self->{_cached_attriblist}}) { 
	   unless (grep { $currattr eq $_ } @$attriblist) {
	       push @$attriblist,$currattr;
	   }
	}
    }
    #If here, _cache_ref indicates no cache
    if (not $refresh and not $self->{_cache_ref}) { #we have active cache reference, increment counter and return
        $self->{_cache_ref} = 1;
    }
    my $oldusecache = $self->{_use_cache}; #save previous 'use_cache' setting
    $self->{_use_cache} = 0; #This function must disable cache 
                            #to function
    my $nodekey = "node";
    if (defined $xCAT::Schema::tabspec{$self->{tabname}}->{nodecol}) {
        $nodekey = $xCAT::Schema::tabspec{$self->{tabname}}->{nodecol}
    };
    unless (grep /^$nodekey$/,@$attriblist) {
        push @$attriblist,$nodekey;
    }
    my @tabcache = $self->getAllAttribs(@$attriblist);
    $self->{_tablecache} = \@tabcache;
    $self->{_nodecache}  = {};
    if ($tabcache[0]->{$nodekey}) {
        foreach(@tabcache) {
            push @{$self->{_nodecache}->{$_->{$nodekey}}},$_;
        }
    }
    $self->{_cached_attriblist} = $attriblist;
    $self->{_use_cache} = $oldusecache; #Restore setting to previous value
    $self->{_cachestamp} = time;
}
# This is a utility function to create a number out of a string, useful for things like round robin algorithms on unnumbered nodes
sub mknum {
    my $string = shift;
    my $number=0;
    foreach (unpack("C*",$string)) { #do big endian, then it would make 'fred' and 'free' be one number apart
        $number += $_;
    }
    return $number;
}

$evalcpt->share('&mknum');
$evalcpt->permit('require');
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
    if ($dbworkerpid) { #TODO: should this be moved outside of the DB worker entirely?  I'm thinking so, but I don't dare do so right now...
			#the benefit would be the potentially computationally intensive substitution logic would be moved out and less time inside limited
			#db worker scope
        return dbc_call($self,'getNodeAttribs',@_);
    }
    my $node    = shift;
    my @attribs;
    my %options = ();
    if (ref $_[0]) {
        @attribs = @{shift()};
        %options = @_;
    } else {
        @attribs = @_;
    }
    my $datum;
    my $oldusecache;
    my $nloldusecache;
    if ($options{prefetchcache}) { #TODO: If this *were* split out of DB worker, this logic would have to move *into* returnany
        if ($self->{tabname} eq 'nodelist') { #a sticky situation
            my @locattribs=@attribs;
            unless (grep(/^node$/,@locattribs)) {
                push @locattribs,'node';
            }
            unless (grep(/^groups$/,@locattribs)) {
                push @locattribs,'groups';
            }
            $self->_build_cache(\@locattribs,noincrementref=>1);
        } else {
            $self->_build_cache(\@attribs,noincrementref=>1);
            $self->{nodelist}->_build_cache(['node','groups'],noincrementref=>1);
        }
 	$oldusecache=$self->{_use_cache};
 	$nloldusecache=$self->{nodelist}->{_use_cache};
	$self->{_use_cache}=1;
	$self->{nodelist}->{_use_cache}=1;
    }
    my @data = $self->getNodeAttribs_nosub_returnany($node, \@attribs,%options);
    if ($options{prefetchcache}) {
	$self->{_use_cache}=$oldusecache;
	$self->{nodelist}->{_use_cache}=$nloldusecache;
	#in this case, we just let the cache live, even if it is to be ignored by most invocations
    }
    #my ($datum, $extra) = $self->getNodeAttribs_nosub($node, \@attribs);
    #if ($extra) { return undef; }    # return (undef,"Ambiguous query"); }
    defined($data[0])
      || return undef;    #(undef,"No matching entry found in configuration");
    unless (scalar keys %{$data[0]}) {
        return undef;
    }
    my $attrib;
    foreach $datum (@data) {
    foreach $attrib (@attribs)
    {
        unless (defined $datum->{$attrib}) {
            #skip undefined values, save time
            next;
        }
        if ($datum->{$attrib} =~ /^\/[^\/]*\/[^\/]*\/$/)
        {
            my $exp = substr($datum->{$attrib}, 1);
            chop $exp;
            my @parts = split('/', $exp, 2);
	         my $retval = $node;
            $retval =~ s/$parts[0]/$parts[1]/;
            $datum->{$attrib} = $retval;
        }
        elsif ($datum->{$attrib} =~ /^\|.*\|$/)
        {

            #Perform arithmetic and only arithmetic operations in bracketed issues on the right.
            #Tricky part:  don't allow potentially dangerous code, only eval if
            #to-be-evaled expression is only made up of ()\d+-/%$
            #Futher paranoia?  use Safe module to make sure I'm good
            my $exp = substr($datum->{$attrib}, 1);
            chop $exp;
            my @parts = split('\|', $exp, 2);
            my $arraySize = @parts;
            if ($arraySize < 2) { # easy regx, generate lhs from node
              my $lhs;
              my @numbers = $node =~ m/[\D0]*(\d+)/g;
              $lhs = '[\D0]*(\d+)' x scalar(@numbers);
              $lhs .= '.*$';
              unshift(@parts,$lhs);
            }
            my $curr;
            my $next;
            my $prev;
            my $retval = $parts[1];
            ($curr, $next, $prev) =
              extract_bracketed($retval, '()', qr/[^()]*/);

            unless($curr) { #If there were no paramaters to save, treat this one like a plain regex
               undef $@; #extract_bracketed would have set $@ if it didn't return, undef $@
               $retval = $node;
               $retval =~ s/$parts[0]/$parts[1]/;
               $datum->{$attrib} = $retval;
               if ($datum->{$attrib} =~ /^$/) {
                  #If regex forces a blank, act like a normal blank does
                  delete $datum->{$attrib};
               }
               next; #skip the redundancy that follows otherwise
            }
            while ($curr)
            {

                #my $next = $comps[0];
                my $value = $node;
                $value =~ s/$parts[0]/$curr/;
                $value = $evalcpt->reval('use integer;'.$value);
                $retval = $prev . $value . $next;
                ($curr, $next, $prev) =
                  extract_bracketed($retval, '()', qr/[^()]*/);
            }
            undef $@;
            #At this point, $retval is the expression after being arithmetically contemplated, a generated regex, and therefore
            #must be applied in total
            my $answval = $node;
            $answval =~ s/$parts[0]/$retval/;
            $datum->{$attrib} = $answval; #$retval;

            #print Data::Dumper::Dumper(extract_bracketed($parts[1],'()',qr/[^()]*/));
            #use text::balanced extract_bracketed to parse earch atom, make sure nothing but arith operators, parans, and numbers are in it to guard against code execution
        }
        if ($datum->{$attrib} =~ /^$/) {
            #If regex forces a blank, act like a normal blank does
            delete $datum->{$attrib};
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
sub getNodeAttribs_nosub_old
{
    my $self   = shift;
    my $node   = shift;
    my $attref = shift;
    my %options = @_;
    my @data;
    my $datum;
    my @tents;
    my $return = 0;
    @tents = $self->getNodeAttribs_nosub_returnany($node, $attref,%options);
    my $nodekey = "node";
    if (defined $xCAT::Schema::tabspec{$self->{tabname}}->{nodecol}) {
        $nodekey = $xCAT::Schema::tabspec{$self->{tabname}}->{nodecol}
    }
    foreach my $tent (@tents) {
      $datum={};
      foreach (@$attref)
      {
        if ($tent and defined($tent->{$_}))
        {
           $return = 1;
           $datum->{$_} = $tent->{$_};
           if ($options{withattribution} and $_ ne $nodekey) {
               $datum->{'!!xcatgroupattribution!!'}->{$_} = $tent->{'!!xcatsourcegroup!!'};
           }
        } 
#else { #attempt to fill in gapped attributes
           #unless (scalar(@$attref) <= 1) {
             #my $sent = $self->getNodeAttribs_nos($node, [$_],%options);
             #if ($sent and defined($sent->{$_})) {
                 #$return = 1;
                 #$datum->{$_} = $sent->{$_};
                #if ($options{withattribution} and $_ ne $nodekey) {
                   #$datum->{'!!xcatgroupattribution!!'}->{$_} = $sent->{'!!xcatgroupattribution!!'}->{$_};
               #}
             #}
           #}
        #}
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

    Description:  not used, kept for reference 

    Arguments:

    Returns:

    Globals:

    Error:

    Example:

    Comments:
        none

=cut

#--------------------------------------------------------------------------------
sub getNodeAttribs_nosub_returnany_old
{    #This is the original function
    my $self    = shift;
    my $node    = shift;
    my @attribs = @{shift()};
    my %options = @_;
    my @results;

    #my $recurse = ((scalar(@_) == 1) ?  shift : 1);
    my $nodekey = "node";
    if (defined $xCAT::Schema::tabspec{$self->{tabname}}->{nodecol}) {
        $nodekey = $xCAT::Schema::tabspec{$self->{tabname}}->{nodecol}
    };
    @results = $self->getAttribs({$nodekey => $node}, @attribs);
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
            @results = $self->getAttribs({$nodekey => $group}, @attribs);
	    $data = $results[0];
            if ($data != undef)
            {
                foreach (@results) {
                   if ($_->{$nodekey}) { $_->{$nodekey} = $node; }
                   if ($options{withattribution}) { $_->{'!!xcatgroupattribution!!'} = $group; }
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

my $nextRecordAtEnd = qr/\+=NEXTRECORD$/;
my $nextRecord = qr/\+=NEXTRECORD/;

#this evolved a bit and i intend to rewrite it into something a bit cleaner at some point - cjhardee
#looks for all of the requested attributes, looking into the groups of the node if needed
sub getNodeAttribs_nosub_returnany
{
  my $self    = shift;
  my $node    = shift;
  my @attribs = @{shift()};
  my %options = @_;
  my @results;

  my $nodekey = "node";
  if (defined $xCAT::Schema::tabspec{$self->{tabname}}->{nodecol}) {
    $nodekey = $xCAT::Schema::tabspec{$self->{tabname}}->{nodecol}
  };
  @results = $self->getAttribs({$nodekey => $node}, @attribs);
    
  my %attribsToDo;
  for(@attribs) {
    $attribsToDo{$_} = 0
  };
    
  my $attrib;
  my $result;
    
  my $data = $results[0];
  if(defined{$data}) { #if there was some data for the node, loop through and check it 
    foreach $result (@results) {
      foreach $attrib (keys %attribsToDo) {
        #check each item in the results to see which attributes were satisfied
        if(defined($result) && defined($result->{$attrib}) && $result->{$attrib} !~ $nextRecordAtEnd) {
          delete $attribsToDo{$attrib};
        } 
      }   
    }
  }

  if((keys (%attribsToDo)) == 0) { #if all of the attributes are satisfied, don't look at the groups
    return @results;
  }

  #find the groups for this node
  my ($nodeghash) = $self->{nodelist}->getAttribs({node => $node}, 'groups');
    
  #no groups for the node, we are done
  unless (defined($nodeghash) && defined($nodeghash->{groups})) {
    return @results;
  }
    
  my @nodegroups = split(/,/, $nodeghash->{groups});
  my $group;
  my @groupResults;
  my $groupResult;
  my %attribsDone;
#print "After node results, still missing ".Dumper(\%attribsToDo)."\n";
#print "groups are ".Dumper(\@nodegroups);
  foreach $group (@nodegroups) {
    use Storable qw(dclone);
    my @prevResCopy = @{dclone(\@results)};
    my @expandedResults;
    @groupResults = $self->getAttribs({$nodekey => $group}, keys (%attribsToDo));
#print "group results for $group are ".Dumper(\@groupResults)."\n";
    $data = $groupResults[0];
    if (defined($data)) { #if some attributes came back from the query for this group
      
      foreach $groupResult (@groupResults) {
        my %toPush;
        foreach $attrib (keys %attribsToDo) { #check each unfinished attribute against the results for this group
#print "looking for attrib $attrib\n";
          if(defined($groupResult->{$attrib})){
            $attribsDone{$attrib} = 0;
#print "found attArib $attrib = $groupResult->{$attrib}\n";
#print "and results look like this:  \n".Dumper(\@results)."\n\n\n";
            foreach $result (@results){ #loop through our existing results to add or modify the value for this attribute
              if(defined($result)) {
                if(defined($result->{$attrib})) {
                  if($result->{$attrib} =~$nextRecordAtEnd){ #if the attribute value should be added
                    $result->{$attrib} =~ s/$nextRecordAtEnd//; #pull out the existing next record string
                    $result->{$attrib} .= $groupResult->{$attrib}; #add the group result onto the end of the existing value
                    if($groupResult->{$attrib} =~ $nextRecordAtEnd && defined($attribsDone{$attrib})){
                      delete $attribsDone{$attrib};
                    }
                    if($options{withattribution} && $attrib ne $nodekey) {
                      if(defined($result->{'!!xcatgroupattribution!!'})) {
                        if(defined($result->{'!!xcatgroupattribution!!'}->{$attrib})) {
                          $result->{'!!xcatgroupattribution!!'}->{$attrib} .= "," . $group;
                        }
                        else {
                          $result->{'!!xcatgroupattribution!!'}->{$attrib} = $node.",".$group;
                        }
                      }
                      else {
                        $result->{'!!xcatgroupattribution!!'}->{$attrib} = $node.",".$group;
                      }
                    }
                  }
                }
                else {#attribute did not already have an entry
#print "attrib $attrib was added with value $groupResult->{$attrib}\n";
                  $result->{$attrib} = $groupResult->{$attrib};
                  if($options{withattribution} && $attrib ne $nodekey){
                    $result->{'!!xcatgroupattribution!!'}->{$attrib} = $group;
                  }
                  if($groupResult->{$attrib} =~ $nextRecordAtEnd && defined($attribsDone{$attrib})){
                    delete $attribsDone{$attrib};
                  }
                }
              }
              else {#no results in the array so far
#print "pushing for the first time.  attr=$attrib groupResults=$groupResult->{$attrib}\n";
                $toPush{$attrib} = $groupResult->{$attrib};
                if($options{withattribution} && $attrib ne $nodekey){
                    $toPush{'!!xcatgroupattribution!!'}->{$attrib} = $group;
                }
                if($groupResult->{$nodekey}) {
                  $toPush{$nodekey} = $node;
                }  
                if($groupResult->{$attrib} =~ $nextRecordAtEnd && defined($attribsDone{$attrib})){
                  delete $attribsDone{$attrib};
                }
              }
            }
          }
        }
        if(keys(%toPush) > 0) {
#print "pushing ".Dumper(\%toPush)."\n";
          if(!defined($results[0])) {
            shift(@results);
          }
          push(@results,\%toPush);
        }
#print "pushing results into expanded results\n";
#print "results= ".Dumper(\@results)."\n";
        push(@expandedResults, @results);
#print "expandedResults= ".Dumper(\@expandedResults)."\n";
#print "setting results to previous:\n".Dumper(\@prevResCopy)."\n\n\n";
        @results = @{dclone(\@prevResCopy)};
      }
      @results = @expandedResults;
      foreach $attrib (keys %attribsDone) {
        if(defined($attribsToDo{$attrib})) {
          delete $attribsToDo{$attrib};
        }
      }
      if((keys (%attribsToDo)) == 0) { #all of the attributes are satisfied, so stop looking at the groups
        last;
      }
    }
  }
    
#print "results ".Dumper(\@results);
#run through the results and remove any "+=NEXTRECORD" ocurrances
  for $result (@results) {
    for my $key (keys %$result) {
      $result->{$key} =~ s/\+=NEXTRECORD//g;
    }
  }

  return @results;
}

#--------------------------------------------------------------------------

=head3 getAllEntries

    Description:  Read entire table

    Arguments:
           Table handle
           "all" return all lines ( even disabled)
           Default is to return only lines that have not been disabled

    Returns:
       Hash containing all rows in table
    Globals:

    Error:

    Example:

	 my $tabh = xCAT::Table->new($table);
         my $recs=$tabh->getAllEntries(); # returns entries not disabled
         my $recs=$tabh->getAllEntries("all"); # returns all  entries

    Comments:
        none

=cut

#--------------------------------------------------------------------------------
sub getAllEntries
{
    my $self = shift;
    if ($dbworkerpid) {
        return dbc_call($self,'getAllEntries',@_);
    }
    my $allentries = shift;
    my @rets;
    my $query;

    # delimit the disable column based on the DB 
    my $disable= &delimitcol("disable");	
    if ($allentries) { # get all lines
     $query = $self->{dbh}->prepare('SELECT * FROM ' . $self->{tabname});
    } else {  # get only enabled lines
     my $qstring = 'SELECT * FROM ' . $self->{tabname} . " WHERE " . $disable . " is NULL or " .  $disable . " in ('0','no','NO','No','nO')";
     $query = $self->{dbh}->prepare($qstring);
    }

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

    When using a general Where clause with SQL statement then
    because we support mulitiple databases (SQLite,MySQL and DB2) that
    require different syntax.  Any code using this routine,  must call the 
    Utils->getDBName routine and code the where clause that is appropriate for
    each supported database.

    When the input is the array of attr<operator> val  strings, the routine will
    build the correct Where clause for the database we are running. 

    Arguments:
       Database Handle
       Where clause
       or 
       array of attr<operator>val strings to be build into a Where clause
    Returns:
        Array of attributes
    Globals:

    Error:

    Example:
    General Where clause:

    $nodelist->getAllAttribsWhere("groups like '%".$atom."%'",'node','group');
    returns  node and group attributes
    $nodelist->getAllAttribsWhere("groups like '%".$atom."%'",'ALL');
    returns  all attributes
    
    Input of attr<operator>val strings

    $nodelist->getAllAttribsWhere(array of attr<operator>val,'node','group');
    returns  node and group attributes
    $nodelist->getAllAttribsWhere(array of attr<operator>val,'ALL');
    returns  all attributes
     where operator can be
     (==,!=,=~,!~, >, <, >=,<=)



    Comments:
        none

=cut

#--------------------------------------------------------------------------------
sub getAllAttribsWhere
{

    #Takes a list of attributes, returns all records in the table.
    my $self        = shift;
    if ($dbworkerpid) {
        return dbc_call($self,'getAllAttribsWhere',@_);
    }
    my $clause = shift; 
    my $whereclause; 
    my @attribs     = @_;
    my @results     = ();
    my $query;
    my $query2;
    if(ref($clause) eq 'ARRAY'){
      $whereclause = &buildWhereClause($clause);
    } else {
      $whereclause = $clause;
    }


    # delimit the disable column based on the DB 
    my $disable= &delimitcol("disable");	
    $query2='SELECT * FROM '  . $self->{tabname} . ' WHERE (' . $whereclause . ")  and  ($disable  is NULL or $disable in ('0','no','NO','No','nO'))";
    $query = $self->{dbh}->prepare($query2);
    $query->execute();
    while (my $data = $query->fetchrow_hashref())
    {
        my %newrow = ();
        if ($attribs[0] eq "ALL") {  # want all attributes
           foreach (keys %$data){
           
             if ($data->{$_} =~ /^$/)
             {
                $data->{$_} = undef;
             }
           }
           push @results, $data;
        } else {  # want specific attributes
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
                 optional hash return style
                 ( changes the return hash structure format) 
    Returns:
                 Array of attribute values
    Globals:

    Error:

    Example:
       my @entries = $self->{switchtab}->getAllNodeAttribs(['port','switch']);
       my @entries = $self->{switchtab}->getAllNodeAttribs(['port','switch'],1);
    Comments:
        none

=cut

#--------------------------------------------------------------------------------
sub getAllNodeAttribs
{

    #Extract and substitute every node record, expanding groups and substituting as getNodeAttribs does
    my $self    = shift;
    if ($dbworkerpid) {
        return dbc_call($self,'getAllNodeAttribs',@_);
    }
    my $attribq = shift;
    my $hashretstyle = shift;
    my %options=@_;
    my $rethash;
    my @results = ();
    my %donenodes
      ; #Remember those that have been done once to not return same node multiple times
    my $query;
    my $nodekey = "node";
    if (defined $xCAT::Schema::tabspec{$self->{tabname}}->{nodecol}) {
        $nodekey = $xCAT::Schema::tabspec{$self->{tabname}}->{nodecol}
    };
    # delimit the disable column based on the DB 
    my $disable= &delimitcol("disable");	
    my $dnodekey= &delimitcol($nodekey);	
    my $qstring= 'SELECT '.$dnodekey.' FROM ' 
     . $self->{tabname}
     . " WHERE " . $disable . " is NULL or " .  $disable . " in ('0','no','NO','No','nO')";
    $query = $self->{dbh}->prepare($qstring);
    $query->execute();
    xCAT::NodeRange::retain_cache(1);
    unless ($options{prefetchcache}) {
    $self->{_use_cache} = 0;
    $self->{nodelist}->{_use_cache}=0;
    }
    $self->_build_cache($attribq);
    $self->{nodelist}->_build_cache(['node','groups']);
    $self->{_use_cache} = 1;
    $self->{nodelist}->{_use_cache}=1;
    while (my $data = $query->fetchrow_hashref())
    {

        unless ($data->{$nodekey} =~ /^$/ || !defined($data->{$nodekey}))
        {    #ignore records without node attrib, not possible?
	    
            my @nodes;
	    unless ($self->{nrcache}->{$data->{$nodekey}} and (($self->{nrcache}->{$data->{$nodekey}}->{tstamp} + 5) > time())) {
		my @cnodes = xCAT::NodeRange::noderange($data->{$nodekey});
		$self->{nrcache}->{$data->{$nodekey}}->{value} = \@cnodes; 
		$self->{nrcache}->{$data->{$nodekey}}->{tstamp} = time();
	    }
            @nodes = @{$self->{nrcache}->{$data->{$nodekey}}->{value}};    #expand node entry, to make groups expand

            #If node not in nodelist do not add to the hash (SF 3580)
            #unless (@nodes) { #in the event of an entry not in nodelist, use entry value verbatim
            #    @nodes = ($data->{$nodekey});
            #}  end SF 3580

            #my $localhash = $self->getNodesAttribs(\@nodes,$attribq); #NOTE:  This is stupid, rebuilds the cache for every entry, FIXME

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
                  $self->getNodeAttribs($_, $attribq);#@{$localhash->{$_}} #$self->getNodeAttribs($_, $attribq)
                  ;    #Logic moves to getNodeAttribs
                       #}
                 #populate node attribute by default, this sort of expansion essentially requires it.
                #$attrs->{node} = $_;
		foreach my $att (@attrs) {
			$att->{$nodekey} = $_;
		}
                $donenodes{$_} = 1;

                if ($hashretstyle) {
                    $rethash->{$_} = \@attrs; #$self->getNodeAttribs($_,\@attribs);
                } else {
                    push @results, @attrs;    #$self->getNodeAttribs($_,@attribs);
                }
            }
        }
    }
    $self->{_use_cache} = 0;
    $self->{nodelist}->{_use_cache} = 0;
    $query->finish();
    if ($hashretstyle) {
        return $rethash;
    } else {
        return @results;
    }
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
    if ($dbworkerpid) {
        return dbc_call($self,'getAllAttribs',@_);
    }
    #print "Being asked to dump ".$self->{tabname}."for something\n";
    my @attribs = @_;
    my @results = ();
    if ($self->{_use_cache}) {
        if ($self->{_cachestamp} < (time()-5)) { #NEVER use a cache older than 5 seconds
		$self->_refresh_cache();
	}
        my @results;
        my $cacheline;
        CACHELINE: foreach $cacheline (@{$self->{_tablecache}}) {
            my $attrib;
            my %rethash;
            foreach $attrib (@attribs)
            {
                unless ($cacheline->{$attrib} =~ /^$/ || !defined($cacheline->{$attrib}))
                {    #To undef fields in rows that may still be returned
                    $rethash{$attrib} = $cacheline->{$attrib};
                }
            }
            if (keys %rethash)
            {
                push @results, \%rethash;
            }
        }
        if (@results)
        {
          return @results; #return wantarray ? @results : $results[0];
        }
        return undef;
    }
    # delimit the disable column based on the DB 
    my $disable= &delimitcol("disable");	
    my $query;
    my $qstring =  "SELECT * FROM " . $self->{tabname} 
        . " WHERE " . $disable . " is NULL or " .  $disable . " in ('0','no','NO','No','nO')";
         $query = $self->{dbh}->prepare($qstring);
    #print $query;
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
	my $table=xCAT::Table->new("nodelist");
        my %keyhash;
        $keyhash{node} = "node1";
        $keyhash{groups} = "compute1";
	$table->delEntries(\%keyhash);
         $table->commit;
        Build delete statement and'ing the elements of the hash
        DELETE FROM nodelist WHERE ("groups" = "compute1" AND "node" = "node1")

        If called with no attributes, it will delete all entries in the table. 
          $table->delEntries();
          $table->commit;
    Comments:
        none

=cut

#--------------------------------------------------------------------------------
sub delEntries
{
    my $self   = shift;
    if ($dbworkerpid) {
        return dbc_call($self,'delEntries',@_);
    }
    my $keyref = shift;
    my @all_keyparis;
    my %keypairs;
    if (not $self->{intransaction} and not $self->{autocommit} and $self->{realautocommit}) {
        #search this code for the other if statement just like it for an explanation of why I do this
        $self->{intransaction}=1;
        $self->{dbh}->{AutoCommit}=0;
    }
    if (ref($keyref) eq 'ARRAY')
    {
        @all_keyparis = @{$keyref};
    }else {
        push @all_keyparis, $keyref;
    }

    
    my $notif = xCAT::NotifHandler->needToNotify($self->{tabname}, 'd');

    my $record_num = 100;
    my @pieces = splice(@all_keyparis, 0, $record_num); 
    while (@pieces) {
        my @notif_data;
        if ($notif == 1)
        {
            my $qstring = "SELECT * FROM " . $self->{tabname};
            if ($keyref) { $qstring .= " WHERE "; }
            my @qargs = ();
            foreach my $keypairs (@pieces) {
                $qstring .= "(";
                foreach my $keypair (keys %{$keypairs})
                {
                    # delimit the columns of the table
	            my $dkeypair= &delimitcol($keypair);	
                    $qstring .= "$dkeypair = ? AND ";

                    push @qargs, $keypairs->{$keypair};
                }
                $qstring =~ s/ AND \z//;
                $qstring .= ") OR ";
            }
            $qstring =~ s/\(\)//;
            $qstring =~ s/ OR \z//;

            
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
        foreach my $keypairs (@pieces) {
            $delstring .= "(";
            foreach my $keypair (keys %{$keypairs})
            {
	        my $dkeypair= &delimitcol($keypair);	
                $delstring .= $dkeypair . ' = ? AND ';
                if (ref($keypairs->{$keypair}))
                {   #XML transformed data may come in mangled unreasonably into listrefs
                    push @stargs, $keypairs->{$keypair}->[0];
                }
                else
                {
                    push @stargs, $keypairs->{$keypair};
                }
            }
            $delstring =~ s/ AND \z//;
            $delstring .= ") OR ";
        }
        $delstring =~ s/\(\)//;
        $delstring =~ s/ OR \z//;
        my $stmt = $self->{dbh}->prepare($delstring);
        $stmt->execute(@stargs);
        $stmt->finish;
    
        $self->_refresh_cache(); #cache is invalid, refresh
        #notify the interested parties
        if ($notif == 1)
        {
            xCAT::NotifHandler->notify("d", $self->{tabname}, \@notif_data, {});
        }
        @pieces = splice(@all_keyparis, 0, $record_num); 
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
	@tmp=$table->getAttribs({'key'=>'ipmi'},('username','password'));
    Comments:
        none

=cut

#--------------------------------------------------------------------------------
sub getAttribs
{

    #Takes two arguments:
    #-Key(s) name (will be compared against the table key(s) value)
    #-List reference of attributes for which calling code wants at least one of defined
    # (recurse argument intended only for internal use.)
    # Returns a hash reference with requested attributes defined.
    my $self = shift;
    if ($dbworkerpid) {
        return dbc_call($self,'getAttribs',@_);
    }

    #my $key = shift;
    #my $keyval = shift;
    my %keypairs = %{shift()};
    my @attribs;
    if (ref $_[0]) {
        @attribs = @{shift()};
    } else {
        @attribs  = @_;
    }
    my @return;
    if ($self->{_use_cache}) {
        if ($self->{_cachestamp} < (time()-5)) { #NEVER use a cache older than 5 seconds
		$self->_refresh_cache();
	}
        my @results;
        my $cacheline;
        if (scalar(keys %keypairs) == 1 and $keypairs{node}) { #99.9% of queries look like this, optimized case
            foreach $cacheline (@{$self->{_nodecache}->{$keypairs{node}}}) {
                my $attrib;
                my %rethash;
                foreach $attrib (@attribs)
               {
                   unless ($cacheline->{$attrib} =~ /^$/ || !defined($cacheline->{$attrib}))
                 {    #To undef fields in rows that may still be returned
                     $rethash{$attrib} = $cacheline->{$attrib};
                 }
               }
               if (keys %rethash)
             {
                 push @results, \%rethash;
             }
            }
        } else { #SLOW WAY FOR GENERIC CASE
            CACHELINE: foreach $cacheline (@{$self->{_tablecache}}) {
                foreach (keys %keypairs) {
                    if (not $keypairs{$_} and $keypairs{$_} ne 0 and $cacheline->{$_}) {
                        next CACHELINE;
                    }
                    unless ($keypairs{$_} eq $cacheline->{$_}) {
                        next CACHELINE;
                    }
                }
                my $attrib;
                my %rethash;
                foreach $attrib (@attribs)
               {
                   unless ($cacheline->{$attrib} =~ /^$/ || !defined($cacheline->{$attrib}))
                 {    #To undef fields in rows that may still be returned
                     $rethash{$attrib} = $cacheline->{$attrib};
                 }
               }
               if (keys %rethash)
             {
                 push @results, \%rethash;
             }
            }
        }
        if (@results)
        {
          return wantarray ? @results : $results[0];
        }
        return undef;
    }
    #print "Uncached access to ".$self->{tabname}."\n";
    my $statement = 'SELECT * FROM ' . $self->{tabname} . ' WHERE ';
    my @exeargs;
    foreach (keys %keypairs)
    {
	my $dkeypair= &delimitcol($_);	
        if ($keypairs{$_})
        {
            $statement .= $dkeypair . " = ? and ";
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
	  $statement .= $dkeypair . " is NULL and " ; 
        }
    }
    # delimit the disable column based on the DB 
    my $disable= &delimitcol("disable");	
    $statement .= "(" . $disable . " is NULL or " .  $disable . " in ('0','no','NO','No','nO'))";
    #print "This is my statement: $statement \n";
    my $query = $self->{dbh}->prepare($statement);
    unless (defined $query) {
        return undef;
    }
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
    if ($dbworkerpid) {
        return dbc_call($self,'getTable',@_);
    }
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
#UNSUED FUNCTION
#sub open
#{
#    my $self = shift;
#    $self->{dbh} = DBI->connect($self->{connstring}, "", "");
#}

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

=head3 getTableList
	Description: Returns a list of the table names in the xCAT database.
=cut
sub getTableList { return keys %xCAT::Schema::tabspec; }


=head3 getTableSchema
	Description: Returns the db schema for the specified table.
	Returns: A reference to a hash that contains the cols, keys, etc. for this table. (See Schema.pm for details.)
=cut
sub getTableSchema { return $xCAT::Schema::tabspec{$_[1]}; }


=head3 getTableList
	Description: Returns a summary description for each table.
	Returns: A reference to a hash.  Each key is the table name.
			Each value is the table description.
=cut
sub getDescriptions {
	my $classname = shift;     # we ignore this because this function is static
	# List each table name and the value for table_desc.
	my $ret = {};
	#my @a = keys %{$xCAT::Schema::tabspec{nodelist}};  print 'a=', @a, "\n";
	foreach my $t (keys %xCAT::Schema::tabspec) { $ret->{$t} = $xCAT::Schema::tabspec{$t}->{table_desc}; }
	return $ret;
}

#--------------------------------------------------------------------------
=head3  isAKey 
    Description:  Checks to see if table field is a table key 

    Arguments:
               Table field 
	       List of keys 
    Returns:
               1= is a key
               0 = not a key 
    Globals:

    Error:

    Example:
              if(isaKey($key_list, $col));

=cut
#--------------------------------------------------------------------------------
sub isAKey 
{
    my ($keys,$col)  = @_;
    my @key_list = @$keys;
    foreach my $key (@key_list)
    {
       if ( $col eq $key) {   # it is a key
         return 1;
       } 
    }
    return 0;
}

#--------------------------------------------------------------------------
=head3   getAutoIncrementColumns
    get a list of column names that are of type "INTEGER AUTO_INCREMENT".

    Returns:
        an array of column names that are auto increment.
=cut
#--------------------------------------------------------------------------------
sub getAutoIncrementColumns {
    my $self=shift;
    my $descr=$xCAT::Schema::tabspec{$self->{tabname}};
    my $types=$descr->{types};
    my @ret=();

    foreach my $col (@{$descr->{cols}})
    {
	if (($types) && ($types->{$col})) {
            if ($types->{$col} =~ /INTEGER AUTO_INCREMENT/) { push(@ret,$col); }
	}
    }
    return @ret;
}
#--------------------------------------------------------------------------

=head3   

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
         Note either input a directory path in $directory of an array of
          full path to filenames in $filelist.  See runsqlcmd for example. 

=cut

#--------------------------------------------------------------------------------

sub get_filelist

{
    use File::Basename; 
    my $self=shift;
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
    my @list;
    # check whether input files or a directory
    if (@$files) {
        @list=@$files;
    } else {
         @list = glob($directory . "*.$ext");    # all files
    }   
    my @filelist = ();
    foreach my $file (@list)
    {
          my $filename= basename($file);  # strip filename
          my($name,$ext1) = split '\.', $filename;
          #my($tmpname,$ext2) = split '\_', $name;
          my @parts = split '\_', $name;
          my $ext2 = $parts[-1];  # get last element
          if ($ext2 eq $dbname)
          {
            push @filelist, $file;
          }
          else
          {
            if ($ext2 eq "")
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

    Description: delimitcol 

    Arguments:
                attribute name 
    Returns:
              The attribute(column)
			  delimited appropriately for the runnning Database 
    Globals:

    Error:

    Example:

        my $delimitedcol=delimitcol($col);

=cut

#--------------------------------------------------------------------------------
sub delimitcol {
    my $attrin=shift;   #input attribute name
    my $attrout;        #output attribute name

    my $xcatcfg =get_xcatcfg(); # get database
    $attrout=$attrin; # for sqlite do nothing
    if (($xcatcfg =~ /^DB2:/) || ($xcatcfg =~ /^Pg:/)) {  
      $attrout="\"$attrin\"";   # use double quotes
    } else {
      if ($xcatcfg =~ /^mysql:/) {  # use backtick
        $attrout="\`$attrin\`";
      } 
    } 
    return $attrout;
}
#--------------------------------------------------------------------------

=head3   

    Description: buildwhereclause 

    Arguments:
                 Array of the following
                   attr<operator> val  where the operator can be the following:
                == 
                != 
                =~ 
                !~ 
                 >   
                 <   
                 >=  
                 <=  

    Returns:
             Where clause with SQL appropriate for the running DB 
    Globals:

    Error:

    Example:

        my $whereclause=buildWhereClause(@array);

=cut

#--------------------------------------------------------------------------------
sub buildWhereClause {
    my $attrvalstr=shift;   # array of atr<op>val strings
    my $whereclause;        # Where Clause
    my $firstpass=1;
    foreach my $m (@{$attrvalstr})
    {
        my $attr;
        my $val;
        my $operator;
        if ($firstpass == 1) { # first pass no AND
           $firstpass = 0; 
        } else {   # add an AND
            $whereclause .=" AND ";
        }
        
        if ($m =~ /^[^=]*\==/) { #attr==val
            ($attr, $val) = split /==/,$m,2;
            $operator=' = ';
        } elsif ($m =~ /^[^=]*=~/) { #attr=~val
            ($attr, $val) = split /=~/,$m,2;
            $val =~ s/^\///;
            $val =~ s/\/$//;
            $operator=' like ';
        } elsif ($m =~ /^[^=]*\!=/) { #attr!=val
             ($attr,$val) = split /!=/,$m,2;
            $operator=' != ';
        } elsif ($m =~ /[^=]*!~/) { #attr!~val
            ($attr,$val) = split /!~/,$m,2;
            $val =~ s/^\///;
            $val =~ s/\/$//;
            $operator=' not like ';
        } elsif ($m =~ /^[^=]*\<=/) { #attr<=val
            ($attr, $val) = split /<=/,$m,2;
            $operator=' <= ';
        } elsif ($m =~ /^[^=]*\</) { #attr<val
            ($attr, $val) = split /</,$m,2;
            $operator=' < ';
        } elsif ($m =~ /^[^=]*\>=/) { #attr>=val
            ($attr, $val) = split />=/,$m,2;
            $operator=' >= ';
        } elsif ($m =~ /^[^=]*\>/) { #attr>val
            ($attr, $val) = split />/,$m,2;
            $operator=' > ';
        } else {
	   xCAT::MsgUtils->message("S", "Unsupported operator:$m  on -w flag input, could not build a Where Clause.");
           $whereclause="";
           return $whereclause;  
        }
	my $delimitedattr= &delimitcol($attr);	
        $whereclause .=$delimitedattr;
        $whereclause .=$operator;
        #$whereclause .="(\'";
        $whereclause .="\'";
        $whereclause .=$val;
        #$whereclause .="\')";
        $whereclause .="\'";
        
    }  
    return $whereclause;
     
}
#--------------------------------------------------------------------------

=head3 writeAllEntries

    Description:  Read entire table and writes all entries to file
                  This routine was written specifically for the tabdump 
                  command.

    Arguments:
          filename or path 

    Returns:
       0=good
       1=bad 
    Globals:

    Error:

    Example:

	 my $tabh = xCAT::Table->new($table);
         my $recs=$tabh->writeAllEntries($filename);

    Comments:
        none

=cut

#--------------------------------------------------------------------------------
sub writeAllEntries
{
    my $self = shift;
    if ($dbworkerpid) {
        return dbc_call($self,'writeAllEntries',@_);
    }
    my $filename = shift;
    my $fh;
    my $rc = 0;
    # open the file for write
    unless (open($fh," > $filename")) {
     my $msg="Unable to open $filename for write \n.";
       `logger -p local4.err  -t xcat $msg`;
        return 1;  
    }
    my $query;
    my $header;
    my $tabdump_header = sub {
        $header = "#" . join(",", @_);
    };
    $tabdump_header->(@{$self->{colnames}});
    # write the header to the file
    print $fh $header;    # write line to file
    print $fh "\n";

    # delimit the disable column based on the DB 
    my $disable= &delimitcol("disable");	
    $query = $self->{dbh}->prepare('SELECT * FROM ' . $self->{tabname});

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
        $rc=output_table($self->{tabname},$fh,$self,$data);
    }
    $query->finish();
    CORE::close($fh);
    return $rc;
}

#--------------------------------------------------------------------------

=head3 writeAllAttribsWhere

    Description:  writes all attributes to file using the "where" clause
                  written for the tabdump command


    Arguments:
       array of attr<operator>val strings to be build into a Where clause
       filename or path
    Returns:
       Outputs to filename the table header and rows
    Globals:

    Error:

    Example:

    $nodelist->getAllAttribsWhere(array of attr<operator>val,$filename);
     where operator can be
     (==,!=,=~,!~, >, <, >=,<=)



    Comments:
        none

=cut

#--------------------------------------------------------------------------------
sub writeAllAttribsWhere
{

    #Takes a list of attributes, returns all records in the table.
    my $self        = shift;
    if ($dbworkerpid) {
        return dbc_call($self,'writeAllAttribsWhere',@_);
    }
    my $clause = shift; 
    my $filename        = shift;
    my $whereclause; 
    my @attribs     = @_;
    my @results     = ();
    my $query;
    my $query2;
    my $fh;
    my $rc;
    # open the file for write
    unless (open($fh," > $filename")) {
     my $msg="Unable to open $filename for write \n.";
       `logger -p local4.err -t xcat $msg`;
        return 1;  
    }
    my $header;
    my $tabdump_header = sub {
        $header = "#" . join(",", @_);
    };
    $tabdump_header->(@{$self->{colnames}});
    # write the header to the file
    print $fh $header;    # write line to file
    print $fh "\n";
    $whereclause = &buildWhereClause($clause);


    # delimit the disable column based on the DB 
    my $disable= &delimitcol("disable");	
    $query2='SELECT * FROM '  . $self->{tabname} . ' WHERE (' . $whereclause . ")  and  ($disable  is NULL or $disable in ('0','no','NO','No','nO'))";
    $query = $self->{dbh}->prepare($query2);
    $query->execute();
    while (my $data = $query->fetchrow_hashref())
    {
       foreach (keys %$data){
           
         if ($data->{$_} =~ /^$/)
         {
                $data->{$_} = undef;
         }
       }
       $rc=output_table($self->{tabname},$fh,$self,$data);
    }
    $query->finish();
    CORE::close($fh);
    return $rc ;
}
#--------------------------------------------------------------------------

=head3 output_table

    Description:  writes table rows to file
                  written for the tabdump command

=cut

#--------------------------------------------------------------------------------
sub output_table {
   my $table = shift;
   my $fh  = shift;
   my $tabh=shift;
   my $rec=shift;
   my $line = '';
   foreach (@{$tabh->{colnames}})
   {
            if (defined $rec->{$_})
            {
                $rec->{$_} =~ s/"/""/g;
                $line = $line . '"' . $rec->{$_} . '",';
            }
            else
            {
                $line .= ',';
            }
   }
   $line =~ s/,$//;    # remove the extra comma at the end
   print $fh $line;    # write line to file
   print $fh "\n";
   return 0;
}
#--------------------------------------------------------------------------

=head3 getMAXMINEntries

    Description: Select the rows in  the Table which has the MAX and the row with the 
                 Min value for the input attribute.
                 Currently only the auditlog and evenlog are setup to have such an attribute (recid). 

    Arguments:
           Table handle
           attribute name ( e.g. recid)

    Returns:
        HASH 
            max=>  max value
            min=>  min value 
    Globals:

    Error:

    Example:

	 my $tabh = xCAT::Table->new($table);
         my $recs=$tabh->getEntries("recid"); # returns row with recid max value in database 
                                              # and the row with the min value.

    Comments:
        none

=cut

#--------------------------------------------------------------------------------
sub getMAXMINEntries
{
    my $self = shift;
    if ($dbworkerpid) {
        return dbc_call($self,'getMAXMINEntries',@_);
    }
    my $attr = shift;
    my $rets;
    my $query;
    my $xcatcfg=get_xcatcfg();

    # delimit the disable column based on the DB 
    my $disable= &delimitcol("disable");	
    my $qstring;
    if ($xcatcfg =~ /^DB2:/) {  # for DB2
       $qstring = "SELECT MAX (\"$attr\") FROM " . $self->{tabname} . " WHERE " . $disable . " is NULL or " .  $disable . " in ('0','no','NO','No','nO')";
    } else {
     $qstring = "SELECT MAX($attr) FROM " . $self->{tabname} . " WHERE " . $disable . " is NULL or " .  $disable . " in ('0','no','NO','No','nO')";
    }
    $query = $self->{dbh}->prepare($qstring);

    $query->execute();
    while (my $data = $query->fetchrow_hashref())
    {
        foreach (keys %$data)
        {
            if ($data->{$_} =~ /^$/)
            {
                $rets->{"max"} = undef;
            } else {
                $rets->{"max"} = $data->{$_};

            }
            last;   # better only be one value for max
            
        }
    }
    $query->finish();
    if ($xcatcfg =~ /^DB2:/) {  # for DB2
       $qstring = "SELECT MIN (\"$attr\") FROM " . $self->{tabname} . " WHERE " . $disable . " is NULL or " .  $disable . " in ('0','no','NO','No','nO')";
    } else {
      $qstring = "SELECT MIN($attr) FROM " . $self->{tabname} . " WHERE " . $disable . " is NULL or " .  $disable . " in ('0','no','NO','No','nO')";
    }
    $query = $self->{dbh}->prepare($qstring);

    $query->execute();
    while (my $data = $query->fetchrow_hashref())
    {
        foreach (keys %$data)
        {
            if ($data->{$_} =~ /^$/)
            {
                $rets->{"min"} = undef;
            } else {
                $rets->{"min"} = $data->{$_};
            }
            last;    # better be only one value for min
        }
    }
    return $rets;
}
1;

