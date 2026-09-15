#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use XCAT::Test::Source qw(slurp_repo_file);

use File::Path qw(make_path);
use File::Slurper qw(read_lines write_text);
use File::Temp qw(tempdir);
use Test::More;
use XCAT::Test::Sandbox qw(replace_required assert_no_host_paths stub_bin run_confined);

# bmcsetup reads its BMC settings from /tmp/ipmicfg.xml, caches ipmitool output in
# /tmp/xcat.ipmitool.mcinfo and reads the kernel command line. The staged copy points each of them
# into a scratch root, and ipmitool, getipmi and the other genesis helpers are stubs.
my $tmpdir = tempdir( CLEANUP => 1 );
my $root   = "$tmpdir/root";
make_path( "$root/tmp", "$root/proc" );
write_text( "$root/proc/cmdline", "quiet\n" );

my $script = slurp_repo_file('xCAT-genesis-scripts/usr/bin/bmcsetup');
replace_required( \$script, '/tmp/ipmicfg.xml',          "$root/tmp/ipmicfg.xml" );
replace_required( \$script, '/tmp/xcat.ipmitool.mcinfo', "$root/tmp/xcat.ipmitool.mcinfo" );
replace_required( \$script, '/proc/cmdline',             "$root/proc/cmdline" );
assert_no_host_paths( $script, root => $root, prefixes => [qw(/etc /var /root /home /boot /opt /srv /install /tftpboot /xcatpost /proc /tmp /sys)] );
my $bmcsetup = "$tmpdir/bmcsetup";
write_text( $bmcsetup, $script );

my $bin = stub_bin(
    dir   => "$tmpdir/bin",
    tools => [qw(bash awk grep sed cut cat rm wc uname)],
    stubs => {
        ipmitool => <<'EOF',
echo "$@" >> "$IPMITOOL_CALL_LOG"

if [ "$1" = "-V" ]; then
    echo "ipmitool version 1.8.19"
    exit 0
fi

if [ "$1" = "-d" ]; then
    shift 2
fi

case "$1" in
    mc)
        if [ "$2" = "info" ]; then
            cat <<MCINFO
IPMI Version              : 2.0
Manufacturer ID          : 10876
Product ID               : 2437
MCINFO
            exit 0
        fi
        ;;
    channel)
        if [ "$2" = "info" ]; then
            echo "Channel Medium Type   : 802.3"
            exit 0
        fi
        if [ "$2" = "getaccess" ]; then
            echo "Fixed Name            : No"
            exit 0
        fi
        ;;
    user)
        case "$2" in
            list)
                cat "$IPMITOOL_USER_LIST"
                exit 0
                ;;
            disable)
                echo "$3" >> "$IPMITOOL_DISABLE_LOG"
                exit 0
                ;;
            enable|priv|set)
                exit 0
                ;;
        esac
        ;;
    raw|lan|chassis)
        exit 0
        ;;
esac

exit 0
EOF
        logger            => 'exit 0',
        modprobe          => 'exit 0',
        sleep             => 'exit 0',
        'updateflag.awk'  => 'exit 0',
        remoteimmsetup    => 'exit 0',
        'allowcred.awk'   => 'exit 0',
        getipmi           => <<"EOF",
cat > '$root/tmp/ipmicfg.xml' <<IPMICFG
<bmcip>10.0.0.2</bmcip>
<taggedvlan>off</taggedvlan>
<gateway>10.0.0.1</gateway>
<netmask>255.255.255.0</netmask>
<username>USERID</username>
<password>passw0rd</password>
<ipcfgmethod>static</ipcfgmethod>
IPMICFG
exit 0
EOF
    },
);

my $user_list = "$tmpdir/user-list.txt";
write_text(
    $user_list,
    <<'EOF'
ID  Name             Callin  Link Auth  IPMI Msg   Channel Priv Limit
1                    true    false      false      NO ACCESS
2   USERID           true    true       true       ADMINISTRATOR
3                    true    false      false      NO ACCESS
4   olduser          true    true       true       ADMINISTRATOR
5   viewer           true    true       false      NO ACCESS
EOF
);

my $call_log    = "$tmpdir/ipmitool-calls.log";
my $disable_log = "$tmpdir/disabled-users.log";

my ( $rc, $output ) = run_confined(
    cmd => [ 'bash', $bmcsetup ],
    bin => $bin,
    env => {
        IPMITOOL_USER_LIST   => $user_list,
        IPMITOOL_CALL_LOG    => $call_log,
        IPMITOOL_DISABLE_LOG => $disable_log,
    },
    writable => [$tmpdir],
    dir      => $tmpdir,
);
is( $rc, 0, 'bmcsetup exits successfully with stubbed IPMI commands' )
  or diag($output);

my @disabled = -e $disable_log ? read_lines($disable_log) : ();
is_deeply( \@disabled, ['4'], 'bmcsetup disables only enabled non-target user slots' );

my @calls = -e $call_log ? read_lines($call_log) : ();
ok(
    !grep( { /user disable (1|3|5)\b/ } @calls ),
    'bmcsetup does not retry user disable for slots that are already disabled'
);
ok( -s $call_log, 'bmcsetup talked to the ipmitool stub' );
ok( -e "$root/tmp/xcat.ipmitool.mcinfo", 'bmcsetup caches the ipmitool output in the scratch root' );
ok( !-e "$root/tmp/ipmicfg.xml", 'bmcsetup removes the settings getipmi wrote into the scratch root' );

done_testing();
