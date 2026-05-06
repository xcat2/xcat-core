#!/usr/bin/env perl
use strict;
use warnings;

use File::Path qw(make_path);
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

my $bmcsetup = "$FindBin::Bin/../../xCAT-genesis-scripts/usr/bin/bmcsetup";
plan skip_all => 'bmcsetup script not found' unless -x $bmcsetup;

my $ipmicfg = '/tmp/ipmicfg.xml';
my $cleanup_ipmicfg = !-e $ipmicfg;
plan skip_all => "$ipmicfg already exists" unless $cleanup_ipmicfg;
END {
    unlink $ipmicfg if $cleanup_ipmicfg && -e $ipmicfg;
}

my $tmpdir = tempdir(CLEANUP => 1);
my $bindir = "$tmpdir/bin";
make_path($bindir);

write_executable(
    "$bindir/ipmitool",
    <<'EOF'
#!/bin/sh
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
);

write_executable("$bindir/logger",       "#!/bin/sh\nexit 0\n");
write_executable("$bindir/modprobe",     "#!/bin/sh\nexit 0\n");
write_executable("$bindir/sleep",        "#!/bin/sh\nexit 0\n");
write_executable("$bindir/updateflag.awk", "#!/bin/sh\nexit 0\n");
write_executable("$bindir/remoteimmsetup", "#!/bin/sh\nexit 0\n");
write_executable("$bindir/allowcred.awk", "#!/bin/sh\nexit 0\n");
write_executable(
    "$bindir/getipmi",
    <<'EOF'
#!/bin/sh
cat > /tmp/ipmicfg.xml <<IPMICFG
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
);

my $user_list = "$tmpdir/user-list.txt";
write_file(
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

local $ENV{PATH}                 = "$bindir:$ENV{PATH}";
local $ENV{IPMITOOL_USER_LIST}   = $user_list;
local $ENV{IPMITOOL_CALL_LOG}    = $call_log;
local $ENV{IPMITOOL_DISABLE_LOG} = $disable_log;

my $output = `bash "$bmcsetup" 2>&1`;
my $rc = $? >> 8;
is($rc, 0, 'bmcsetup exits successfully with stubbed IPMI commands')
  or diag($output);

my @disabled = read_lines($disable_log);
is_deeply(\@disabled, ['4'], 'bmcsetup disables only enabled non-target user slots');

my @calls = read_lines($call_log);
ok(
    !grep({ /user disable (1|3|5)\b/ } @calls),
    'bmcsetup does not retry user disable for slots that are already disabled'
);

done_testing();

sub write_executable {
    my ($path, $content) = @_;
    write_file($path, $content);
    chmod 0755, $path or die "chmod $path: $!";
}

sub write_file {
    my ($path, $content) = @_;
    open(my $fh, '>', $path) or die "open $path: $!";
    print {$fh} $content;
    close($fh) or die "close $path: $!";
}

sub read_lines {
    my ($path) = @_;
    return () unless -e $path;
    open(my $fh, '<', $path) or die "open $path: $!";
    my @lines = <$fh>;
    close($fh) or die "close $path: $!";
    chomp @lines;
    return @lines;
}
