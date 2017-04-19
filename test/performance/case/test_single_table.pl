BEGIN {
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : -d '/opt/xcat' ? '/opt/xcat' : '/usr';
}
use lib "$::XCATROOT/lib/perl";

use xCAT::Table;
use xCAT::TableNoCache;
use xCAT::Utils;
use xCAT::MsgUtils;
use xCAT::State;
use Data::Dumper;
use Time::HiRes qw/time/;

#use strict;

my $number = $ARGV[0];

#exit 1 if $number < 1000;
my $dbmaster;

sub get_subroutine_name {
    return (caller(1))[3];
}

$dbmaster = xCAT::Table::init_dbworker;

sub test_setNodesAttribs_cache {
    my $nodehm_table = xCAT::Table->new('nodehm');
    unless ($nodehm_table) {
        xCAT::MsgUtils->message("S", "Unable to open nodehm table, denying");
        return -1;
    }
    my $data;
    for (my $i = 0 ; $i < $number ; $i++) {
        $data->{"performance_$i"}->{'cons'}            = "ipmi";
        $data->{"performance_$i"}->{'mgt'}             = "ipmi";
        $data->{"performance_$i"}->{'getmac'}          = "true";
        $data->{"performance_$i"}->{'consoleondemand'} = "ssh 127.0.0.1";
        $data->{"performance_$i"}->{'cmdmapping'} = "ipmitool -H 127.0.0.1 -U admin";
        $data->{"performance_$i"}->{'termserver'}  = "127.0.0.1";
        $data->{"performance_$i"}->{'serialspeed'} = 115200;
        $data->{"performance_$i"}->{'serialport'}  = int(rand(6));
    }
    $nodehm_table->setNodesAttribs($data);
    $nodehm_table->close();
    return get_subroutine_name();
}

sub test_getNodesAttribs_cache {
    my $count = shift;
    if ($number < $count) {
        return undef;
    }
    my $factor       = int($number / $count);
    my $nodehm_table = xCAT::Table->new('nodehm');
    unless ($nodehm_table) {
        xCAT::MsgUtils->message("S", "Unable to open nodehm table, denying");
        return -1;
    }
    my @cols = ('node', 'serialspeed', 'mgt');
    my @nodes;
    my $j;
    for (my $i = 0 ; $i < $number ; $i += $factor) {
        $j = $i + int(rand($factor));
        push @nodes, "performance_$j";
    }

    #print Dumper($nodehm_table->getNodesAttribs(\@nodes,\@cols));
    $nodehm_table->getNodesAttribs(\@nodes, \@cols);
    $nodehm_table->close();
    return get_subroutine_name() . "_$count";
}

sub test_getNodesAttribs_nocache {
    my $count = shift;
    if ($number < $count) {
        return undef;
    }
    my $factor       = int($number / $count);
    my $nodehm_table = xCAT::TableNoCache->new('nodehm');
    unless ($nodehm_table) {
        xCAT::MsgUtils->message("S", "Unable to open nodehm table, denying");
        return -1;
    }
    my @cols = ('node', 'serialspeed', 'mgt');
    my @nodes;
    for (my $i = 0 ; $i < $number ; $i += $factor) {
        $j = $i + int(rand($factor));
        push @nodes, "performance_$j";
    }

    #print Dumper($nodehm_table->getNodesAttribs(\@nodes,\@cols));
    $nodehm_table->getNodesAttribs(\@nodes, \@cols);
    $nodehm_table->close();
    return get_subroutine_name() . "_$count";
}

sub test_getAttribs_cache {
    my $count = shift;
    if ($number < $count) {
        return undef;
    }
    my $nodehm_table = xCAT::Table->new('nodehm');
    unless ($nodehm_table) {
        xCAT::MsgUtils->message("S", "Unable to open nodehm table, denying");
        return -1;
    }
    my $j;
    for (my $i = 0 ; $i < $count ; $i++) {
        $port = int(rand(6));

#print Dumper($nodehm_table->getAttribs({serialport=>$port},[qw(node serialspeed serialport)]));
        $nodehm_table->getAttribs({ serialport => $port }, [qw(node serialspeed serialport)]);
    }
    $nodehm_table->close();
    return get_subroutine_name() . "_$count";
}

sub test_getAttribs_nocache {
    my $count = shift;
    if ($number < $count) {
        return undef;
    }
    my $nodehm_table = xCAT::TableNoCache->new('nodehm');
    unless ($nodehm_table) {
        xCAT::MsgUtils->message("S", "Unable to open nodehm table, denying");
        return -1;
    }
    my $j;
    for (my $i = 0 ; $i < $count ; $i++) {
        $port = int(rand(6));

#print Dumper($nodehm_table->getAttribs({serialport=>$port},[qw(node serialspeed serialport)]));
        $nodehm_table->getAttribs({ serialport => $port }, [qw(node serialspeed serialport)]);
    }
    $nodehm_table->close();
    return get_subroutine_name() . "_$count";
}

sub test_getNodeAttribs_cache {
    my $count = shift;
    if ($number < $count) {
        return undef;
    }
    my $nodehm_table = xCAT::Table->new('nodehm');
    unless ($nodehm_table) {
        xCAT::MsgUtils->message("S", "Unable to open nodehm table, denying");
        return -1;
    }
    my $j;
    for (my $i = 0 ; $i < $count ; $i++) {
        $j    = int(rand($number));
        $node = "performance_$j";

#print Dumper($nodehm_table->getNodeAttribs($node,[qw(serialspeed serialport)]));
        $nodehm_table->getNodeAttribs($node, [qw(serialspeed serialport consoleondemand getmac)]);
    }
    $nodehm_table->close();
    return get_subroutine_name() . "_$count";
}

sub test_getNodeAttribs_nocache {
    my $count = shift;
    if ($number < $count) {
        return undef;
    }
    my $nodehm_table = xCAT::TableNoCache->new('nodehm');
    unless ($nodehm_table) {
        xCAT::MsgUtils->message("S", "Unable to open nodehm table, denying");
        return -1;
    }
    my $j;
    for (my $i = 0 ; $i < $count ; $i++) {
        $j    = int(rand($number));
        $node = "performance_$j";
        $nodehm_table->getNodeAttribs($node, [qw(serialspeed serialport consoleondemand getmac)]);
    }
    $nodehm_table->close();
    return get_subroutine_name() . "_$count";
}

sub test_getAllAttribs_cache {
    my $nodehm_table = xCAT::Table->new('nodehm');
    unless ($nodehm_table) {
        xCAT::MsgUtils->message("S", "Unable to open nodehm table, denying");
        return -1;
    }
    my $j;
    my @attrlist = ('node', 'mgt', 'getmac', 'consoleondemand', 'serialspeed', 'serialport');
    $nodehm_table->getAllAttribs(@attrlist);

    #print Dumper($nodehm_table->getAllAttribs(@attrlist))."\n";
    $nodehm_table->close();
    return get_subroutine_name();
}

sub test_getAllAttribs_nocache {
    my $nodehm_table = xCAT::TableNoCache->new('nodehm');
    unless ($nodehm_table) {
        xCAT::MsgUtils->message("S", "Unable to open nodehm table, denying");
        return -1;
    }
    my $j;
    my @attrlist = ('node', 'mgt', 'getmac', 'consoleondemand', 'serialspeed', 'serialport');
    $nodehm_table->getAllAttribs(@attrlist);

    #print Dumper($nodehm_table->getAllAttribs(@attrlist))."\n";
    $nodehm_table->close();
    return get_subroutine_name();
}

sub test_delEntries_cache {
    my $nodehm_table = xCAT::Table->new('nodehm');
    unless ($nodehm_table) {
        xCAT::MsgUtils->message("S", "Unable to open nodehm table, denying");
        return -1;
    }
    for (my $i = 0 ; $i < $number ; $i++) {

        $nodehm_table->delEntries({ 'node' => "performance_$i" });
    }
    $nodehm_table->close();
    return get_subroutine_name();
}

sub test_batchDelEntries_nocache {
    my $nodehm_table = xCAT::TableNoCache->new('nodehm');
    unless ($nodehm_table) {
        xCAT::MsgUtils->message("S", "Unable to open nodehm table, denying");
        return -1;
    }
    my @nodes;
    for (my $i = 0 ; $i < $number ; $i++) {
        push @nodes, "performance_$i";
    }
    $nodehm_table->batchDelEntries(\@nodes);
    $nodehm_table->close();
    return get_subroutine_name();
}



sub test_database {
    my $db_func    = shift;
    my $params_ptr = shift;
    my $start_time = time();
    my $subroutine;

    if (defined($params_ptr)) {
        $subroutine = &$db_func($params_ptr);
    }
    else {
        $subroutine = &$db_func();
    }
    if (defined($subroutine)) {
        my $end_time     = time();
        my $elapsed_time = $end_time - $start_time;
        print "$subroutine elapsed time:$elapsed_time\n";
    }

}

sub db_exit() {
    xCAT::Table->shut_dbworker;
    kill 'INT', $dbmaster;
    while (xCAT::Utils->is_process_exists($dbmaster) != 0) {
        sleep(0.1);
    }
}

# insert data
test_database(\&test_setNodesAttribs_cache);

print "start single query \n*******\n";

test_database(\&test_getNodeAttribs_cache,   1);
test_database(\&test_getNodeAttribs_cache,   1);
test_database(\&test_getNodeAttribs_cache,   1);
test_database(\&test_getNodeAttribs_nocache, 1);    # Long time
test_database(\&test_getNodeAttribs_nocache, 1);
test_database(\&test_getNodeAttribs_nocache, 1);

test_database(\&test_getNodeAttribs_cache,   300);
test_database(\&test_getNodeAttribs_cache,   300);
test_database(\&test_getNodeAttribs_nocache, 300);
test_database(\&test_getNodeAttribs_nocache, 300);

test_database(\&test_getNodeAttribs_cache,   10);
test_database(\&test_getNodeAttribs_cache,   10);
test_database(\&test_getNodeAttribs_nocache, 10);
test_database(\&test_getNodeAttribs_nocache, 10);

test_database(\&test_getNodeAttribs_cache,   800);
test_database(\&test_getNodeAttribs_cache,   800);
test_database(\&test_getNodeAttribs_nocache, 800);
test_database(\&test_getNodeAttribs_nocache, 800);

print "start batch query sleep 7 seconds to make cache up to date\n********\n";

#sleep(7);

test_database(\&test_getNodesAttribs_nocache, 1000);
test_database(\&test_getNodesAttribs_nocache, 1000);
test_database(\&test_getNodesAttribs_cache,   1000);
test_database(\&test_getNodesAttribs_cache,   1000);

test_database(\&test_getNodesAttribs_nocache, 500);
test_database(\&test_getNodesAttribs_nocache, 500);
test_database(\&test_getNodesAttribs_cache,   500);
test_database(\&test_getNodesAttribs_cache,   500);

test_database(\&test_getNodesAttribs_nocache, 3);
test_database(\&test_getNodesAttribs_nocache, 3);
test_database(\&test_getNodesAttribs_cache,   3);
test_database(\&test_getNodesAttribs_cache,   3);

test_database(\&test_getNodesAttribs_nocache, 70);
test_database(\&test_getNodesAttribs_nocache, 70);
test_database(\&test_getNodesAttribs_cache,   70);
test_database(\&test_getNodesAttribs_cache,   70);

test_database(\&test_getNodesAttribs_nocache, 1000);
test_database(\&test_getNodesAttribs_nocache, 1000);
test_database(\&test_getNodesAttribs_cache,   1000);
test_database(\&test_getNodesAttribs_cache,   1000);

test_database(\&test_getNodesAttribs_nocache, 3000);
test_database(\&test_getNodesAttribs_nocache, 3000);
test_database(\&test_getNodesAttribs_cache,   3000);
test_database(\&test_getNodesAttribs_cache,   3000);


print "start getAttribs query sleep 7 seconds to make cache up to date\n********\n";

sleep(7);
test_database(\&test_getAllAttribs_cache);
test_database(\&test_getAllAttribs_cache);
test_database(\&test_getAllAttribs_cache);

test_database(\&test_getAllAttribs_nocache);
test_database(\&test_getAllAttribs_nocache);
test_database(\&test_getAllAttribs_nocache);

print "start getAttribs query sleep 7 seconds to make cache up to date\n********\n";

sleep(7);
test_database(\&test_getAttribs_nocache, 1);
test_database(\&test_getAttribs_nocache, 1);
test_database(\&test_getAttribs_cache,   1);
test_database(\&test_getAttribs_cache,   1);


# DB direct access
db_exit();

print "Now DB process is down \n*********\n";

test_database(\&test_getNodesAttribs_cache, 500);
test_database(\&test_getNodesAttribs_cache, 500);
test_database(\&test_getNodesAttribs_cache, 3);
test_database(\&test_getNodesAttribs_cache, 3);
test_database(\&test_getNodesAttribs_cache, 1000);
test_database(\&test_getNodesAttribs_cache, 1000);

test_database(\&test_getAllAttribs_cache);
test_database(\&test_getAllAttribs_nocache);

# clean up data
test_database(\&test_batchDelEntries_nocache);
1;
