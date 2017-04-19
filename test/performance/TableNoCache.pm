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
package xCAT::TableNoCache;
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
my $cachethreshold = 16; #How many nodes in 'getNodesAttribs' before switching to full DB retrieval

#TODO: dynamic tracking/adjustment, the point where cache is cost effective differs based on overall db size

use DBI;
$DBI::dbi_debug = 9;     # increase the debug output

use strict;
use Scalar::Util qw/weaken/;
use xCAT::Utils;
require xCAT::Schema;
require xCAT::NodeRange;
use Text::Balanced qw(extract_bracketed);
require xCAT::NotifHandler;

my $dbworkerpid;         #The process id of the database worker
my $dbworkersocket;
my $dbsockpath = "/var/run/xcat/dbworker.sock." . $$;
my $exitdbthread;
my $dbobjsforhandle;
my $intendedpid;
my %opentables; #USED ONLY BY THE DB WORKER TO TRACK OPEN DATABASES


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
            open($cfgl, "<", "/etc/xcat/cfgloc");
            $xcatcfg = <$cfgl>;
            close($cfgl);
            chomp($xcatcfg);
            $ENV{'XCATCFG'} = $xcatcfg; #Store it in env to avoid many file reads
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
    my @args  = @_;
    my $self  = {};
    my $proto = shift;
    $self->{tabname} = shift;
    unless (defined($xCAT::Schema::tabspec{ $self->{tabname} })) { return undef; }
    $self->{schema}       = $xCAT::Schema::tabspec{ $self->{tabname} };
    $self->{colnames}     = \@{ $self->{schema}->{cols} };
    $self->{descriptions} = \%{ $self->{schema}->{descriptions} };
    my %otherargs = @_;
    my $create    = 1;
    if (exists($otherargs{'-create'}) && ($otherargs{'-create'} == 0)) { $create = 0; }
    $self->{autocommit} = $otherargs{'-autocommit'};

    unless (defined($self->{autocommit}))
    {
        $self->{autocommit} = 1;
    }
    $self->{realautocommit} = $self->{autocommit}; #Assume requester autocommit behavior maps directly to DBI layer autocommit
    my $class = ref($proto) || $proto;
    if ($dbworkerpid) {
        my $request = {
            function   => "new",
            tablename  => $self->{tabname},
            autocommit => $self->{autocommit},
            args       => \@args,
        };
        unless (dbc_submit($request)) {
            return undef;
        }
    } else {                                       #direct db access mode
        if ($opentables{ $self->{tabname} }->{ $self->{autocommit} }) { #if we are inside the db worker and asked to create a new table that is already open, just return a reference to that table
             #generally speaking, this should cause a lot of nodelists to be shared
            return $opentables{ $self->{tabname} }->{ $self->{autocommit} };
        }
        $self->{dbuser} = "";
        $self->{dbpass} = "";

        my $xcatcfg = get_xcatcfg();
        my $xcatdb2schema;
        if ($xcatcfg =~ /^DB2:/) {    # for DB2 , get schema name
            my @parts = split('\|', $xcatcfg);
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
        else    #Generic DBI
        {
            ($self->{connstring}, $self->{dbuser}, $self->{dbpass}) = split(/\|/, $xcatcfg);
            $self->{connstring} =~ s/^dbi://;
            $self->{connstring} =~ s/^/dbi:/;

            #return undef;
        }
        if ($xcatcfg =~ /^DB2:/) {    # for DB2 ,export the INSTANCE name
            $ENV{'DB2INSTANCE'} = $self->{dbuser};
        }

        my $oldumask = umask 0077;
        unless ($::XCAT_DBHS->{ $self->{connstring}, $self->{dbuser}, $self->{dbpass}, $self->{realautocommit} }) { #= $self->{tabname};
            $::XCAT_DBHS->{ $self->{connstring}, $self->{dbuser}, $self->{dbpass}, $self->{realautocommit} } =
              DBI->connect($self->{connstring}, $self->{dbuser}, $self->{dbpass}, { AutoCommit => $self->{realautocommit} });
        }
        umask $oldumask;

        $self->{dbh} = $::XCAT_DBHS->{ $self->{connstring}, $self->{dbuser}, $self->{dbpass}, $self->{realautocommit} };

#Store the Table object reference as afflicted by changes to the DBH
#This for now is ok, as either we aren't in DB worker mode, in which case this structure would be short lived...
#or we are in db worker mode, in which case Table objects live indefinitely
#TODO: be able to reap these objects sanely, just in case
        push @{ $dbobjsforhandle->{ $::XCAT_DBHS->{ $self->{connstring}, $self->{dbuser}, $self->{dbpass}, $self->{realautocommit} } } }, \$self;

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
                        $xCAT::Schema::tabspec{ $self->{tabname} },
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
            $self->{dbh}->{'csv_tables'}->{ $self->{tabname} } =
              { 'file' => $self->{tabname} . ".csv" };
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
                    $xCAT::Schema::tabspec{ $self->{tabname} },
                    $xcatcfg);
                $self->{dbh}->do($str);
            }
        } else {    #generic DBI
            if (!$self->{dbh})
            {
                xCAT::MsgUtils->message("S", "Could not connect to the database. Database handle not defined.");

                return undef;
            }
            my $tbexistq;
            my $dbtablename = $self->{tabname};
            my $found       = 0;
            if ($xcatcfg =~ /^DB2:/) {    # for DB2
                $dbtablename =~ tr/a-z/A-Z/;    # convert to upper
                $tbexistq = $self->{dbh}->table_info(undef, $xcatdb2schema, $dbtablename, 'TABLE');
            } else {
                $tbexistq = $self->{dbh}->table_info('', '', $self->{tabname}, 'TABLE');
            }
            while (my $data = $tbexistq->fetchrow_hashref) {
                if ($data->{'TABLE_NAME'} =~ /^\"?$dbtablename\"?\z/) {
                    if ($xcatcfg =~ /^DB2:/) {    # for DB2
                        if ($data->{'TABLE_SCHEM'} =~ /^\"?$xcatdb2schema\"?\z/) {

                            # must check schema also with db2
                            $found = 1;
                            last;
                        }
                    } else {                      # not db2
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
                    $xCAT::Schema::tabspec{ $self->{tabname} },
                    $xcatcfg);
                $self->{dbh}->do($str);
                if (!$self->{dbh}->{AutoCommit}) {
                    $self->{dbh}->commit;    #  commit the create
                }

            }
        }    # end Generic DBI


    }    #END DB ACCESS SPECIFIC SECTION
    if ($self->{tabname} eq 'nodelist')
    {
        weaken($self->{nodelist} = $self);
    }
    else
    {
        $self->{nodelist} = xCAT::Table->new('nodelist', -create => 1);
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
    my $self  = shift;
    my $descr = $xCAT::Schema::tabspec{ $self->{tabname} };
    my $tn    = $self->{tabname};
    my $xcatdb2schema;
    my $xcatcfg = get_xcatcfg();
    my $rc      = 0;
    my $msg;

    if ($xcatcfg =~ /^DB2:/) {    # for DB2 , get schema name
        my @parts = split('\|', $xcatcfg);
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
        my $tn = $self->{tabname};
        while (my $col_info = $sth->fetchrow_hashref) {

            #print Dumper($col_info);
            my $tmp_col = $col_info->{name};
            $tmp_col =~ s/"//g;
            push @columns, $tmp_col;
            if ($col_info->{pk}) {
                $dbkeys{$tmp_col} = 1;
            }
        }
        $sth->finish;
    } else {    #Attempt generic dbi..
                #my $sth = $self->{dbh}->column_info('','',$self->{tabname},'');
        my $sth;
        if ($xcatcfg =~ /^DB2:/) {    # for DB2
            my $db2table = $self->{tabname};
            $db2table =~ tr/a-z/A-Z/;    # convert to upper for db2
            $sth = $self->{dbh}->column_info(undef, $xcatdb2schema, $db2table, '%');
        } else {
            $sth = $self->{dbh}->column_info(undef, undef, $self->{tabname}, '%');
        }
        while (my $cd = $sth->fetchrow_hashref) {

            #print Dumper($cd);
            push @columns, $cd->{'COLUMN_NAME'};

            #special code for old version of perl-DBD-mysql
            if (defined($cd->{mysql_is_pri_key}) && ($cd->{mysql_is_pri_key} == 1)) {
                my $tmp_col = $cd->{'COLUMN_NAME'};
                $tmp_col =~ s/"//g;
                $dbkeys{$tmp_col} = 1;
            }
        }
        foreach (@columns) {   #Column names may end up quoted by database engin
            s/"//g;
        }

        #get primary keys
        if ($xcatcfg =~ /^DB2:/) {    # for DB2
            my $db2table = $self->{tabname};
            $db2table =~ tr/a-z/A-Z/;    # convert to upper for db2
            $sth = $self->{dbh}->primary_key_info(undef, $xcatdb2schema, $db2table);
        } else {
            $sth = $self->{dbh}->primary_key_info(undef, undef, $self->{tabname});
        }
        if ($sth) {
            my $data = $sth->fetchall_arrayref;

            #print "data=". Dumper($data);
            foreach my $cd (@$data) {
                my $tmp_col = $cd->[3];
                $tmp_col =~ s/"//g;
                $dbkeys{$tmp_col} = 1;
            }
        }
    }

    #Now @columns reflects the *actual* columns in the database
    my $dcol;
    my $types = $descr->{types};

    foreach $dcol (@{ $self->{colnames} })
    {
        unless (grep /^$dcol$/, @columns)
        {
            #TODO: log/notify of schema upgrade?
            my $datatype;
            if ($xcatcfg =~ /^DB2:/) {
                $datatype = get_datatype_string_db2($dcol, $types, $tn, $descr);
            } else {
                $datatype = get_datatype_string($dcol, $xcatcfg, $types);
            }
            if ($datatype eq "TEXT") {    # keys cannot be TEXT
                if (isAKey(\@{ $descr->{keys} }, $dcol)) {    # keys
                    $datatype = "VARCHAR(128) ";
                }
            }

            if (grep /^$dcol$/, @{ $descr->{required} })
            {
                $datatype .= " NOT NULL";
            }

            # delimit the columns of the table
            my $tmpcol = &delimitcol($dcol);

            my $tablespace;
            my $stmt =
              "ALTER TABLE " . $self->{tabname} . " ADD $tmpcol $datatype";
            $self->{dbh}->do($stmt);
            $msg = "updateschema: Running $stmt";
            xCAT::MsgUtils->message("S", $msg);
            if ($self->{dbh}->errstr) {
                xCAT::MsgUtils->message("S", "Error adding columns for table " . $self->{tabname} . ":" . $self->{dbh}->errstr);
                if ($xcatcfg =~ /^DB2:/) {    # see if table space error
                    my $error = $self->{dbh}->errstr;
                    if ($error =~ /54010/) {

                        # move the table to the next tablespace
                        if ($error =~ /USERSPACE1/) {
                            $tablespace = "XCATTBS16K";
                        } else {
                            $tablespace = "XCATTBS32K";
                        }
                        my $tablename = $self->{tabname};
                        $tablename =~ tr/a-z/A-Z/;    # convert to upper
                        $msg = "Moving table $self->{tabname} to $tablespace";
                        xCAT::MsgUtils->message("S", $msg);
                        my $stmt2 = "Call sysproc.admin_move_table('XCATDB',\'$tablename\',\'$tablespace\',\'$tablespace\',\'$tablespace\','','','','','','MOVE')";
                        $self->{dbh}->do($stmt2);
                        if ($self->{dbh}->errstr) {
                            xCAT::MsgUtils->message("S", "Error on tablespace move  for table " . $self->{tabname} . ":" . $self->{dbh}->errstr);
                        } else {    # tablespace move try column add again
                            if (!$self->{dbh}->{AutoCommit}) { # commit tbsp move
                                $self->{dbh}->commit;
                            }
                            $self->{dbh}->do($stmt);
                        }

                    }    # if tablespace error

                }    # if db2
            }    # error on add column
            if (!$self->{dbh}->{AutoCommit}) {    # commit add column
                $self->{dbh}->commit;
            }
        }
    }

    #for existing columns that are new keys now
    # note new keys can only be created from existing columns
    # since keys cannot be null, the copy from the backup table will fail if
    # the old value was null.

    my @new_dbkeys = @{ $descr->{keys} };
    my @old_dbkeys = keys %dbkeys;

   #print "new_dbkeys=@new_dbkeys;  old_dbkeys=@old_dbkeys; columns=@columns\n";
    my $change_keys = 0;

    #Add the new key columns to the table
    foreach my $dbkey (@new_dbkeys) {
        if (!exists($dbkeys{$dbkey})) {
            $change_keys = 1;

            # Call tabdump plugin to create a CSV file
            # can be used in case the restore fails
            # put in /tmp/<tablename.csv.pid>
            my $backuptable = "/tmp/$tn.csv.$$";
            my $cmd         = "$::XCATROOT/sbin/tabdump $tn > $backuptable";
            `$cmd`;
            $msg = "updateschema: Backing up table before key change, $cmd";
            xCAT::MsgUtils->message("S", $msg);

#for my sql, we do not have to recreate table, but we have to make sure the type is correct,
            my $datatype;
            if ($xcatcfg =~ /^mysql:/) {
                $datatype = get_datatype_string($dbkey, $xcatcfg, $types);
            } else {    # db2
                $datatype = get_datatype_string_db2($dbkey, $types, $tn, $descr);
            }
            if ($datatype eq "TEXT") {
                if (isAKey(\@{ $descr->{keys} }, $dbkey)) { # keys need defined length
                    $datatype = "VARCHAR(128) ";
                }
            }

            # delimit the columns
            my $tmpkey = &delimitcol($dbkey);
            if (($xcatcfg =~ /^DB2:/) || ($xcatcfg =~ /^Pg:/)) {

                # get rid of NOT NULL, cannot modify with NOT NULL
                my ($tmptype, $nullvalue) = split('NOT NULL', $datatype);
                $datatype = $tmptype;

            }
            my $stmt;
            if ($xcatcfg =~ /^DB2:/) {
                $stmt =
"ALTER TABLE " . $self->{tabname} . " ALTER COLUMN $tmpkey SET DATA TYPE $datatype";
            } else {
                $stmt =
"ALTER TABLE " . $self->{tabname} . " MODIFY COLUMN $tmpkey $datatype";
            }
            $msg = "updateschema: Running $stmt";
            xCAT::MsgUtils->message("S", $msg);

            #print "stmt=$stmt\n";
            $self->{dbh}->do($stmt);
            if ($self->{dbh}->errstr) {
                xCAT::MsgUtils->message("S", "Error changing the keys for table " . $self->{tabname} . ":" . $self->{dbh}->errstr);
            }
        }
    }

    #finally  add the new keys
    if ($change_keys) {
        if ($xcatcfg =~ /^mysql:/) {    #for mysql, just alter the table
            my $tmp = join(',', @new_dbkeys);
            my $stmt =
"ALTER TABLE " . $self->{tabname} . " DROP PRIMARY KEY, ADD PRIMARY KEY ($tmp)";

            #print "stmt=$stmt\n";
            $self->{dbh}->do($stmt);
            $msg = "updateschema: Running $stmt";
            xCAT::MsgUtils->message("S", $msg);
            if ($self->{dbh}->errstr) {
                xCAT::MsgUtils->message("S", "Error changing the keys for table " . $self->{tabname} . ":" . $self->{dbh}->errstr);
            }
        } else {                        #for the rest, recreate the table
                                        #print "need to change keys\n";
            my $btn = $tn . "_xcatbackup";

            #remove the backup table just in case;
            # gets error if not there
            #my $str="DROP TABLE $btn";
            #$self->{dbh}->do($str);

            #rename the table name to name_xcatbackup
            my $str;
            if ($xcatcfg =~ /^DB2:/) {
                $str = "RENAME TABLE $tn TO $btn";
            } else {
                $str = "ALTER TABLE $tn RENAME TO $btn";
            }
            $self->{dbh}->do($str);
            if (!$self->{dbh}->{AutoCommit}) {
                $self->{dbh}->commit;
            }
            $msg = "updateschema: Running $str";
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
            $msg = "updateschema: Running $str";
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
    my $self    = shift;
    my $node    = shift;
    my $nodekey = "node";
    if (defined $xCAT::Schema::tabspec{ $self->{tabname} }->{nodecol}) {
        $nodekey = $xCAT::Schema::tabspec{ $self->{tabname} }->{nodecol}
    }
    return $self->setAttribs({ $nodekey => $node }, @_);
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
        return dbc_call($self, 'commit', @_);
    }
    unless ($self->{dbh}->{AutoCommit}) { #caller can now hammer commit function with impunity, even when it makes no sense
        $self->{dbh}->commit;
    }
    if ($self->{intransaction} and not $self->{autocommit} and $self->{realautocommit}) {

#if realautocommit indicates shared DBH between manual and auto commit, put the handle back to autocommit if a transaction
#is committed (aka ended)
        $self->{intransaction} = 0;
        $self->{dbh}->{AutoCommit} = 1;
    }
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
    my $self        = shift;
    my $nodelist    = shift;
    my $keyset      = shift;
    my %cols        = ();
    my @orderedcols = ();
    my $oldac       = $self->{dbh}->{AutoCommit};    #save autocommit state
    $self->{dbh}->{AutoCommit} = 0;    #turn off autocommit for performance
    my $hashrec;
    my $colsmatch = 1;

    if (ref $nodelist eq 'HASH') { # argument of the form  { n001 => { groups => 'something' }, n002 => { groups => 'other' } }
        $hashrec = $nodelist;
        my @nodes = keys %$nodelist;
        $nodelist = \@nodes;
        my $firstpass = 1;
        foreach my $node (keys %$hashrec) { #Determine whether the passed structure is trying to set the same columns
                #for every node to determine if the short path can work or not
            if ($firstpass) {
                $firstpass = 0;
                foreach (keys %{ $hashrec->{$node} }) {
                    $cols{$_} = 1;
                }
            } else {
                foreach (keys %{ $hashrec->{$node} }) { #make sure all columns in this entry are in the first
                    unless (defined $cols{$_}) {
                        $colsmatch = 0;
                        last;
                    }
                }
                foreach my $col (keys %cols) { #make sure this entry does not lack any columns from the first
                    unless (defined $hashrec->{$node}->{$col}) {
                        $colsmatch = 0;
                        last;
                    }
                }
            }
        }

    } else { #the legacy calling style with a list reference and a single hash reference of col=>va/ue pairs
        $hashrec = {};
        foreach (@$nodelist) {
            $hashrec->{$_} = $keyset;
        }
        foreach (keys %$keyset) {
            $cols{$_} = 1;
        }
    }

#this code currently is notification incapable.  It enhances scaled setting by:
#-turning off autocommit if on (done for above code too, but to be clear document the fact here too
#-executing one select statement per set of nodes instead of per node (chopping into 1,000 node chunks for SQL statement length
#-aggregating update statements
#-preparing one insert statement and re-execing it (SQL-92 multi-row insert isn't ubiquitous enough)

    my $nodekey = "node";
    if (defined $xCAT::Schema::tabspec{ $self->{tabname} }->{nodecol}) {
        $nodekey = $xCAT::Schema::tabspec{ $self->{tabname} }->{nodecol}
    }
    @orderedcols = keys %cols; #pick a specific column ordering explicitly to assure consistency
    my @sqlorderedcols = ();

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
    my @currnodes = splice(@$nodelist, 0, $nodesatatime); #Do a few at a time to stay under max sql statement length and max variable count
    my $insertsth; #if insert is needed, this will hold the single prepared insert statement
    my $upsth;

    my $dnodekey = &delimitcol($nodekey);
    while (scalar @currnodes) {
        my %updatenodes = ();
        my %insertnodes = ();
        my $qstring;

        #sort nodes into inserts and updates
        $qstring = "SELECT * FROM " . $self->{tabname} . " WHERE $dnodekey in (";
        $qstring .= '?, ' x scalar(@currnodes);
        $qstring =~ s/, $/)/;
        my $query = $self->{dbh}->prepare($qstring);
        $query->execute(@currnodes);
        my $rec;
        while ($rec = $query->fetchrow_hashref()) {
            $updatenodes{ $rec->{$nodekey} } = 1;
        }
        if (scalar keys %updatenodes < scalar @currnodes) {
            foreach (@currnodes) {
                unless ($updatenodes{$_}) {
                    $insertnodes{$_} = 1;
                }
            }
        }
        my $havenodecol; #whether to put node first in execute arguments or let it go naturally
        if (not $insertsth and keys %insertnodes) { #prepare an insert statement since one will be needed
            my $columns   = "";
            my $bindhooks = "";
            $havenodecol = defined $cols{$nodekey};
            unless ($havenodecol) {
                $columns   = "$dnodekey, ";
                $bindhooks = "?, ";
            }
            $columns .= join(", ", @sqlorderedcols);
            $bindhooks .= "?, " x scalar @sqlorderedcols;
            $bindhooks =~ s/, $//;
            $columns   =~ s/, $//;
            my $instring = "INSERT INTO " . $self->{tabname} . " ($columns) VALUES ($bindhooks)";

            #print $instring;
            $insertsth = $self->{dbh}->prepare($instring);
        }
        foreach my $node (keys %insertnodes) {
            my @args = ();
            unless ($havenodecol) {
                @args = ($node);
            }
            foreach my $col (@orderedcols) {
                push @args, $hashrec->{$node}->{$col};
            }
            $insertsth->execute(@args);
        }
        if (not $upsth and keys %updatenodes) { #prepare an insert statement since one will be needed
            my $upstring = "UPDATE " . $self->{tabname} . " set ";
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
            my $upstring = "UPDATE " . $self->{tabname} . " set ";
            foreach my $node (keys %updatenodes) {
                my @args = ();
                foreach my $col (@orderedcols) { #try aggregating requests.  Could also see about single prepare, multiple executes instead
                    push @args, $hashrec->{$node}->{$col};
                }
                push @args, $node;
                $upsth->execute(@args);
            }
        }
        @currnodes = splice(@$nodelist, 0, $nodesatatime);
    }
    $self->{dbh}->commit;                        #commit pending transactions
    $self->{dbh}->{AutoCommit} = $oldac;         #restore autocommit semantics
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
    my $self     = shift;
    my $nodelist = shift;
    unless ($nodelist) { $nodelist = []; } #common to be invoked with undef seemingly
    my %options = ();
    my @attribs;
    if (ref $_[0]) {
        @attribs = @{ shift() };
        %options = @_;
    } else {
        @attribs = @_;
    }
    my @realattribs = @attribs; #store off the requester attribute list, the cached columns may end up being a superset and we shouldn't return more than asked
    my $rethash;
    my @tmp = @{ dclone(\@$nodelist) };
    @tmp = map { $_ = '"' . $_ . '"'; } @tmp;
    my $clause = "node in (" . join(",", @tmp) . ")";
    my @entries = $self->getAllAttribsWhere($clause, @realattribs);
    foreach my $entry (@entries) {
        $rethash->{ $entry->{node} } = $entry;
    }
    return $rethash;
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
    my $self = shift;
    if (!defined($self->{dbh})) {
        xCAT::MsgUtils->message("S", "xcatd: DBI is missing, Please check the db access process.");
        return undef;
    }
    my $node = shift;
    my @attribs;
    my %options = ();
    if (ref $_[0]) {
        @attribs = @{ shift() };
        %options = @_;
    } else {
        @attribs = @_;
    }
    my $datum;
    my @data = $self->getNodeAttribs_nosub_returnany($node, \@attribs, %options);

    #my ($datum, $extra) = $self->getNodeAttribs_nosub($node, \@attribs);
    #if ($extra) { return undef; }    # return (undef,"Ambiguous query"); }
    defined($data[0])
      || return undef;    #(undef,"No matching entry found in configuration");
    unless (scalar keys %{ $data[0] }) {
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
                if ($arraySize < 2) {    # easy regx, generate lhs from node
                    my $lhs;
                    my @numbers = $node =~ m/[\D0]*(\d+)/g;
                    $lhs = '[\D0]*(\d+)' x scalar(@numbers);
                    $lhs .= '.*$';
                    unshift(@parts, $lhs);
                }
                my $curr;
                my $next;
                my $prev;
                my $retval = $parts[1];
                ($curr, $next, $prev) =
                  extract_bracketed($retval, '()', qr/[^()]*/);

                unless ($curr) { #If there were no paramaters to save, treat this one like a plain regex
                    undef $@; #extract_bracketed would have set $@ if it didn't return, undef $@
                    $retval = $node;
                    $retval =~ s/$parts[0]/$parts[1]/;
                    $datum->{$attrib} = $retval;
                    if ($datum->{$attrib} =~ /^$/) {

                        #If regex forces a blank, act like a normal blank does
                        delete $datum->{$attrib};
                    }
                    next;     #skip the redundancy that follows otherwise
                }
                while ($curr)
                {

                    #my $next = $comps[0];
                    my $value = $node;
                    $value =~ s/$parts[0]/$curr/;
                    $value  = $evalcpt->reval('use integer;' . $value);
                    $retval = $prev . $value . $next;
                    ($curr, $next, $prev) =
                      extract_bracketed($retval, '()', qr/[^()]*/);
                }
                undef $@;

#At this point, $retval is the expression after being arithmetically contemplated, a generated regex, and therefore
#must be applied in total
                my $answval = $node;
                $answval =~ s/$parts[0]/$retval/;
                $datum->{$attrib} = $answval;    #$retval;

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

my $nextRecordAtEnd = qr/\+=NEXTRECORD$/;
my $nextRecord      = qr/\+=NEXTRECORD/;

#this evolved a bit and i intend to rewrite it into something a bit cleaner at some point - cjhardee
#looks for all of the requested attributes, looking into the groups of the node if needed
sub getNodeAttribs_nosub_returnany
{
    my $self    = shift;
    my $node    = shift;
    my @attribs = @{ shift() };
    my %options = @_;
    my @results;

    my $nodekey = "node";
    if (defined $xCAT::Schema::tabspec{ $self->{tabname} }->{nodecol}) {
        $nodekey = $xCAT::Schema::tabspec{ $self->{tabname} }->{nodecol}
    }
    @results = $self->getAttribs({ $nodekey => $node }, @attribs);
    my %attribsToDo;
    for (@attribs) {
        $attribsToDo{$_} = 0
    }

    my $attrib;
    my $result;

    my $data = $results[0];
    if (defined {$data}) { #if there was some data for the node, loop through and check it
        foreach $result (@results) {
            foreach $attrib (keys %attribsToDo) {

          #check each item in the results to see which attributes were satisfied
                if (defined($result) && defined($result->{$attrib}) && $result->{$attrib} !~ $nextRecordAtEnd) {
                    delete $attribsToDo{$attrib};
                }
            }
        }
    }

    if ((keys(%attribsToDo)) == 0) { #if all of the attributes are satisfied, don't look at the groups
        return @results;
    }

    #find the groups for this node
    my ($nodeghash) = $self->{nodelist}->getAttribs({ node => $node }, 'groups');

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
        my @prevResCopy = @{ dclone(\@results) };
        my @expandedResults;
        @groupResults = $self->getAttribs({ $nodekey => $group }, keys(%attribsToDo));

        #print "group results for $group are ".Dumper(\@groupResults)."\n";
        $data = $groupResults[0];
        if (defined($data)) { #if some attributes came back from the query for this group

            foreach $groupResult (@groupResults) {
                my %toPush;
                foreach $attrib (keys %attribsToDo) { #check each unfinished attribute against the results for this group

                    #print "looking for attrib $attrib\n";
                    if (defined($groupResult->{$attrib})) {
                        $attribsDone{$attrib} = 0;

            #print "found attArib $attrib = $groupResult->{$attrib}\n";
            #print "and results look like this:  \n".Dumper(\@results)."\n\n\n";
                        foreach $result (@results) { #loop through our existing results to add or modify the value for this attribute
                            if (defined($result)) {
                                if (defined($result->{$attrib})) {
                                    if ($result->{$attrib} =~ $nextRecordAtEnd) { #if the attribute value should be added
                                        $result->{$attrib} =~ s/$nextRecordAtEnd//; #pull out the existing next record string
                                        $result->{$attrib} .= $groupResult->{$attrib}; #add the group result onto the end of the existing value
                                        if ($groupResult->{$attrib} =~ $nextRecordAtEnd && defined($attribsDone{$attrib})) {
                                            delete $attribsDone{$attrib};
                                        }
                                        if ($options{withattribution} && $attrib ne $nodekey) {
                                            if (defined($result->{'!!xcatgroupattribution!!'})) {
                                                if (defined($result->{'!!xcatgroupattribution!!'}->{$attrib})) {
                                                    $result->{'!!xcatgroupattribution!!'}->{$attrib} .= "," . $group;
                                                }
                                                else {
                                                    $result->{'!!xcatgroupattribution!!'}->{$attrib} = $node . "," . $group;
                                                }
                                            }
                                            else {
                                                $result->{'!!xcatgroupattribution!!'}->{$attrib} = $node . "," . $group;
                                            }
                                        }
                                    }
                                }
                                else {  #attribute did not already have an entry

         #print "attrib $attrib was added with value $groupResult->{$attrib}\n";
                                    $result->{$attrib} = $groupResult->{$attrib};
                                    if ($options{withattribution} && $attrib ne $nodekey) {
                                        $result->{'!!xcatgroupattribution!!'}->{$attrib} = $group;
                                    }
                                    if ($groupResult->{$attrib} =~ $nextRecordAtEnd && defined($attribsDone{$attrib})) {
                                        delete $attribsDone{$attrib};
                                    }
                                }
                            }
                            else {      #no results in the array so far

#print "pushing for the first time.  attr=$attrib groupResults=$groupResult->{$attrib}\n";
                                $toPush{$attrib} = $groupResult->{$attrib};
                                if ($options{withattribution} && $attrib ne $nodekey) {
                                    $toPush{'!!xcatgroupattribution!!'}->{$attrib} = $group;
                                }
                                if ($groupResult->{$nodekey}) {
                                    $toPush{$nodekey} = $node;
                                }
                                if ($groupResult->{$attrib} =~ $nextRecordAtEnd && defined($attribsDone{$attrib})) {
                                    delete $attribsDone{$attrib};
                                }
                            }
                        }
                    }
                }
                if (keys(%toPush) > 0) {

                    #print "pushing ".Dumper(\%toPush)."\n";
                    if (!defined($results[0])) {
                        shift(@results);
                    }
                    push(@results, \%toPush);
                }

                #print "pushing results into expanded results\n";
                #print "results= ".Dumper(\@results)."\n";
                push(@expandedResults, @results);

         #print "expandedResults= ".Dumper(\@expandedResults)."\n";
         #print "setting results to previous:\n".Dumper(\@prevResCopy)."\n\n\n";
                @results = @{ dclone(\@prevResCopy) };
            }
            @results = @expandedResults;
            foreach $attrib (keys %attribsDone) {
                if (defined($attribsToDo{$attrib})) {
                    delete $attribsToDo{$attrib};
                }
            }
            if ((keys(%attribsToDo)) == 0) { #all of the attributes are satisfied, so stop looking at the groups
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
    my $self   = shift;
    my $clause = shift;
    my $whereclause;
    my @attribs = @_;
    my @results = ();
    my $query;
    my $query2;

    if (ref($clause) eq 'ARRAY') {
        $whereclause = &buildWhereClause($clause);
    } else {
        $whereclause = $clause;
    }


    # delimit the disable column based on the DB
    my $disable = &delimitcol("disable");
    $query2 = 'SELECT * FROM ' . $self->{tabname} . ' WHERE (' . $whereclause . ")  and  ($disable  is NULL or $disable in ('0','no','NO','No','nO'))";
    $query = $self->{dbh}->prepare($query2);
    $query->execute();
    while (my $data = $query->fetchrow_hashref())
    {
        my %newrow = ();
        if ($attribs[0] eq "ALL") {    # want all attributes
            foreach (keys %$data) {

                if ($data->{$_} =~ /^$/)
                {
                    $data->{$_} = undef;
                }
            }
            push @results, $data;
        } else {                       # want specific attributes
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
    my $self = shift;

    #print "Being asked to dump ".$self->{tabname}."for something\n";
    my @attribs = @_;
    my @results = ();

    # delimit the disable column based on the DB
    my $disable = &delimitcol("disable");
    my $query;
    my $qstring = "SELECT * FROM " . $self->{tabname}
      . " WHERE " . $disable . " is NULL or " . $disable . " in ('0','no','NO','No','nO')";
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

sub batchDelEntries {
    my $self      = shift;
    my $nodes_ptr = shift;
    my @nodes     = @{$nodes_ptr};
    my @tmp       = map { $_ = '"' . $_ . '"'; } @nodes;
    my $clause    = "node in (" . join(",", @tmp) . ")";
    my $delstring = 'DELETE FROM ' . $self->{tabname} . " WHERE $clause;";
    my $stmt      = $self->{dbh}->prepare($delstring);
    $stmt->execute();
    $stmt->finish;
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
    my $self     = shift;
    my %keypairs = %{ shift() };
    my @attribs;
    if (ref $_[0]) {
        @attribs = @{ shift() };
    } else {
        @attribs = @_;
    }
    my @return;
    my @results;

    #print "Uncached access to ".$self->{tabname}."\n";
    my $statement = 'SELECT * FROM ' . $self->{tabname} . ' WHERE ';
    my @exeargs;
    foreach (keys %keypairs)
    {
        my $dkeypair = &delimitcol($_);
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
            $statement .= $dkeypair . " is NULL and ";
        }
    }

    # delimit the disable column based on the DB
    my $disable = &delimitcol("disable");
    $statement .= "(" . $disable . " is NULL or " . $disable . " in ('0','no','NO','No','nO'))";

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
    my $attrin = shift;    #input attribute name
    my $attrout;           #output attribute name

    my $xcatcfg = get_xcatcfg();    # get database
    $attrout = $attrin;             # for sqlite do nothing
    if (($xcatcfg =~ /^DB2:/) || ($xcatcfg =~ /^Pg:/)) {
        $attrout = "\"$attrin\"";    # use double quotes
    } else {
        if ($xcatcfg =~ /^mysql:/) {    # use backtick
            $attrout = "\`$attrin\`";
        }
    }
    return $attrout;
}

1;

