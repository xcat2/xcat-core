#!/usr/bin/env perl
use strict;
use warnings;

use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

# Regression: systemd-timesyncd is only stopped on the chrony path.
#
# setupntp disciplines the clock with whichever daemon it configures, and timesyncd is an SNTP
# client that disciplines the same clock. Leaving it running means two things stepping the clock.
# The stop/disable sits ~24 lines BELOW the `exec setupntp.traditional` that the ntpd path takes,
# and setupntp.traditional never touches timesyncd -- so on the ntpd path it is never reached.
#
# setupntp resets PATH at the top, so PATH stubs cannot shadow anything in it. The region that
# decides this is extracted instead and driven with systemctl and friends shadowed by shell
# functions, which bash resolves ahead of PATH. `exec` is a builtin and cannot be shadowed, so
# the harness puts a recording stand-in where the script execs, and the exec ends the run --
# which is exactly the behaviour under test.

my $repo_root = File::Spec->rel2abs(
    File::Spec->catdir( $FindBin::Bin, '..', '..' )
);
my $setupntp = File::Spec->catfile( $repo_root, 'xCAT', 'postscripts', 'setupntp' );
plan skip_all => "setupntp not found" unless -f $setupntp;

my $src = do { local $/; open my $fh, '<', $setupntp or die $!; <$fh> };

# Take the span that contains BOTH the ntpd dispatch and the timesyncd handling, whichever
# order they appear in -- the ordering is asserted at runtime below, from what the run actually
# recorded, not from where the text sits. Anchored on the dispatch and on the `unset` block that
# follows it, so a reordering does not silently shrink the region to cover only one of them.
# BAIL_OUT rather than skip, so a rename fails loudly instead of silently covering nothing.
my $dispatch_at = index( $src, 'if [ -n "${USE_NTPD}" ]' . "\nthen" );
my $timesyncd_at = index( $src, 'systemctl stop systemd-timesyncd.service' );
my $end_at = index( $src, '# Unset xCAT passed environment variables' );
BAIL_OUT('could not locate the ntpd dispatch in setupntp')      if $dispatch_at < 0;
BAIL_OUT('could not locate the timesyncd handling in setupntp') if $timesyncd_at < 0;
BAIL_OUT('could not locate the end of the dispatch region')     if $end_at < 0;

BAIL_OUT('the timesyncd handling is outside the extracted region')
  if $timesyncd_at > $end_at;

# Start at the top of the paragraph the earlier landmark sits in, so an enclosing `if ... then`
# comes with its `fi`. Slicing at the landmark itself orphaned the guard and the region would
# not parse.
my $start_at = $dispatch_at < $timesyncd_at ? $dispatch_at : $timesyncd_at;
my $para = rindex( $src, "\n\n", $start_at );
$start_at = $para + 2 if $para >= 0;

my $region = substr( $src, $start_at, $end_at - $start_at );
BAIL_OUT('the extracted region does not parse as shell')
  if system( '/bin/bash', '-n', '-c', "f(){ :; }\n$region" ) != 0;

my $dir = tempdir( CLEANUP => 1 );
my $run = 0;

sub drive {
    my ($use_ntpd) = @_;
    $run++;
    my $root = File::Spec->catdir( $dir, "run$run" );
    mkdir $root;
    my $calls = File::Spec->catfile( $root, 'calls' );

    # The script execs "${0%/*}/setupntp.traditional"; $0 is the harness, so this is where it
    # lands. Recording rather than executing anything real.
    my $trad = File::Spec->catfile( $root, 'setupntp.traditional' );
    open my $t, '>', $trad or die $!;
    print $t "#!/bin/bash\necho 'EXEC setupntp.traditional' >> '$calls'\nexit 0\n";
    close $t;
    chmod 0755, $trad;

    my $harness = File::Spec->catfile( $root, 'harness.sh' );
    open my $fh, '>', $harness or die $!;
    print $fh <<"PRE";
#!/bin/bash
USE_NTPD='$use_ntpd'
NTP_SERVERS=(pool.ntp.org)
log_label=xcat
logger(){ :; }
systemctl(){ echo "systemctl \$*" >> '$calls'; return 0; }
timedatectl(){ echo "timedatectl \$*" >> '$calls'; return 0; }
check_exec_or_exit(){ :; }
check_executes(){ return 0; }
PRE
    print $fh $region, "\n";
    close $fh;

    system( '/bin/bash', $harness );
    return '' unless -f $calls;
    return do { local $/; open my $c, '<', $calls or die $!; <$c> };
}

# The chrony path: this already worked, and pins the behaviour we are extending.
my $chrony = drive('');
like( $chrony, qr/^systemctl stop systemd-timesyncd\.service$/m,
    'chrony path: timesyncd is stopped' );
like( $chrony, qr/^systemctl disable systemd-timesyncd\.service$/m,
    'chrony path: timesyncd is disabled' );
unlike( $chrony, qr/^EXEC setupntp\.traditional$/m,
    'chrony path: does not hand off to setupntp.traditional' );

# The ntpd path: it hands off, so anything that must happen has to happen first.
my $ntpd = drive('yes');
like( $ntpd, qr/^EXEC setupntp\.traditional$/m,
    'ntpd path: hands off to setupntp.traditional' );
like( $ntpd, qr/^systemctl stop systemd-timesyncd\.service$/m,
    'ntpd path: timesyncd is stopped too' );
like( $ntpd, qr/^systemctl disable systemd-timesyncd\.service$/m,
    'ntpd path: timesyncd is disabled too' );

my ($before_exec) = $ntpd =~ /\A(.*?)^EXEC setupntp\.traditional/ms;
ok( defined $before_exec && $before_exec =~ /systemctl disable systemd-timesyncd/,
    'ntpd path: the disable happens before the hand-off, not after it' );

# setupntp.traditional does not do it either, which is why the ordering above matters.
my $trad_src = File::Spec->catfile(
    $repo_root, 'xCAT', 'postscripts', 'setupntp.traditional' );
SKIP: {
    skip 'setupntp.traditional not found', 1 unless -f $trad_src;
    my $t = do { local $/; open my $h, '<', $trad_src or die $!; <$h> };
    unlike( $t, qr/timesyncd/,
        'setupntp.traditional does not handle timesyncd itself' );
}

done_testing();
