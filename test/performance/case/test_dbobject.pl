BEGIN {
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : -d '/opt/xcat' ? '/opt/xcat' : '/usr';
}
use lib "$::XCATROOT/lib/perl";

use xCAT::Utils;
use xCAT::MsgUtils;
use xCAT::State;
use Data::Dumper;
use xCAT::Utils;
use Time::HiRes qw/time/;
use File::Copy;

use constant CACHE_XCATD_PATH   => '/opt/xcat/sbin/xcatd.cache';
use constant NOCACHE_XCATD_PATH => '/opt/xcat/sbin/xcatd.nocache';
use constant DEST_XCATD_PATH    => '/opt/xcat/sbin/xcatd';

use constant CACHE_TABLE_PATH   => '/opt/xcat/lib/perl/xCAT/Table.pm.cache';
use constant NOCACHE_TABLE_PATH => '/opt/xcat/lib/perl/xCAT/Table.pm.nocache';
use constant DEST_TABLE_PATH    => '/opt/xcat/lib/perl/xCAT/Table.pm';

my $number = $ARGV[0];

sub get_subroutine_name {
    return (caller(1))[3];
}

sub setup_nocache_xcat {
    copy(NOCACHE_XCATD_PATH, DEST_XCATD_PATH) or die "Copy failed: $!";
    copy(NOCACHE_TABLE_PATH, DEST_TABLE_PATH) or die "Copy failed: $!";
}

sub setup_cache_xcat {
    copy(CACHE_XCATD_PATH, DEST_XCATD_PATH) or die "Copy failed: $!";
    copy(CACHE_TABLE_PATH, DEST_TABLE_PATH) or die "Copy failed: $!";
}

sub restart_xcat_service {
    xCAT::Utils->runcmd("service xcatd restart ", -1);
    if ($::RUNCMD_RC != 0) {
        die "Failed to restart xcatd service";
    }
}

sub test_xcat_with_cache {
    setup_cache_xcat();
    restart_xcat_service();
    prepare_data($number);
}

sub test_xcat_without_cache {
    setup_nocache_xcat();
    restart_xcat_service();
    prepare_data($number);
}


sub cleanup_data {
    my $count = shift;
    if (!defined($count)) {
        $count = 100;
    }
    xCAT::Utils->runcmd("rmdef node[1-$count]", -1);
    if ($::RUNCMD_RC != 0) {
        die "Failed to destroy data";
    }
}

sub prepare_data {
    my $count = shift;
    if (!defined($count)) {
        $count = 100;
    }
    xCAT::Utils->runcmd("chdef node[1-$count] mgt=ipmi groups=all arch=x86_64 os=rhels7.0"
          . " nodetype=osi profile=service netboot=kvm installnic=mac"
          . " primarynic=mac provmethod=rhels7-x86_64-install-service"
          . " bmcpassword=abc123 bmcusername=ADMIN ", -1);
    if ($::RUNCMD_RC != 0) {
        die "Failed to create data";
    }
}

sub test_lsdef {
    my $count = shift;
    if (!defined($count)) {
        $count = 1;
    }
    for (my $i = 0 ; $i < $count ; $i++) {
        xCAT::Utils->runcmd("lsdef", -1);
        if ($::RUNCMD_RC != 0) {
            die "Failed run lsdef command";
        }
    }
    return get_subroutine_name() . "_$count";
}

sub test_lsdef_node {
    my $count = shift;
    if (!defined($count)) {
        $count = 1;
    }
    for (my $i = 0 ; $i < $count ; $i++) {
        xCAT::Utils->runcmd("lsdef node10", -1);
        if ($::RUNCMD_RC != 0) {
            die "Failed run lsdef node command";
        }
    }
    return get_subroutine_name() . "_$count";
}

sub test_dbobject {
    my $obj_func   = shift;
    my $params_ptr = shift;
    my $start_time = time();
    my $subroutine;

    if (defined($params_ptr)) {
        $subroutine = &$obj_func($params_ptr);
    }
    else {
        $subroutine = &$obj_func();
    }
    if (defined($subroutine)) {
        my $end_time     = time();
        my $elapsed_time = $end_time - $start_time;
        print "$subroutine elapsed time:$elapsed_time\n";
    }
}

sub main() {
    print "\nTesting with cache version\n";
    test_xcat_with_cache();
    test_dbobject(\&test_lsdef);
    test_dbobject(\&test_lsdef_node);
    test_dbobject(\&test_lsdef);
    test_dbobject(\&test_lsdef_node);
    test_dbobject(\&test_lsdef,      10);
    test_dbobject(\&test_lsdef_node, 10);

    print "\nNow testing with no cache version\n";
    test_xcat_without_cache();
    test_dbobject(\&test_lsdef);
    test_dbobject(\&test_lsdef_node);
    test_dbobject(\&test_lsdef);
    test_dbobject(\&test_lsdef_node);

    test_dbobject(\&test_lsdef,      10);
    test_dbobject(\&test_lsdef_node, 10);

    print "\nClean up data\n";
    cleanup_data($number);
}
main();
1;
