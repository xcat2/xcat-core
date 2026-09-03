#!/usr/bin/env perl
use strict;
use warnings;

use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Slurper qw(read_text write_text);
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;

use XCAT::Test::File qw(repo_path);

my $postscripts = repo_path('xCAT/postscripts');
my $remoteshell = "$postscripts/remoteshell";
my $sshd_helper = "$postscripts/remoteshell-sshd-config";
plan skip_all => 'remoteshell postscript not found' unless -r $remoteshell;
plan skip_all => 'remoteshell sshd helper not found' unless -x $sshd_helper;
# The postscript is written against GNU sed; sed -i means something else on BSD.
plan skip_all => 'postscript targets Linux nodes' unless $^O eq 'linux';
is( system( 'sh', '-n', $sshd_helper ), 0,
    'the sshd configuration helper has POSIX shell syntax' );

sub run_sshd_helper {
    my (%opt) = @_;

    my ($root, $sshdir, $config);
    if ($opt{reuse}) {
        # A second deployment against the tree the first one left behind.
        ($root, $sshdir, $config) = @{$opt{reuse}}{qw(root sshdir untouched)};
    }
    else {
        $root   = tempdir(CLEANUP => 1);
        $sshdir = "$root/etc/ssh";
        make_path($sshdir);
        make_path("$root/bin");

        # The fixtures name /etc/ssh so they read like a real config; point them
        # at the scratch tree along with the script itself.
        $config = $opt{sshd_config};
        $config =~ s{/etc/ssh}{$sshdir}g;
        write_text("$sshdir/sshd_config", $config);
        write_text("$sshdir/ssh_config",  "Host *\n");
        make_path("$root$opt{dropin_dir}") if $opt{dropin_dir} && !$opt{skip_dropin_dir};

        # Record logging in the scratch tree rather than the real syslog.
        write_text("$root/bin/logger",
            "#!/bin/sh\nprintf '%s\\n' \"\$*\" >> '$root/logger.log'\nexit 0\n");
        chmod 0755, "$root/bin/logger";
    }

    my @args = (
        $opt{pcm} ? 1 : 0,
        defined $opt{osver} ? $opt{osver} : '',
        'xcat',
    );
    my $rc;
    my $output;
    {
        local $ENV{XCAT_SSH_ETC} = $sshdir;
        local $ENV{XCAT_LOGGER}  = "$root/bin/logger";
        open(
            my $pipe,
            '-|', 'sh', '-c', 'exec "$@" 2>&1', 'sh',
            $sshd_helper, @args,
        ) or die "Unable to run $sshd_helper: $!";
        $output = do { local $/; <$pipe> };
        close($pipe);
        $rc = $?;
    }

    return {
        root        => $root,
        sshdir      => $sshdir,
        sshd_config => read_file("$sshdir/sshd_config"),
        ssh_config  => read_file("$sshdir/ssh_config"),
        untouched   => $config,
        orig        => (-e "$sshdir/sshd_config.ORIG" ? 1 : 0),
        output      => $output,
        rc          => $rc,
        logged      => read_file("$root/logger.log"),
    };
}

sub read_file {
    my ($path) = @_;
    return '' unless -f $path;
    return read_text($path);
}

sub run_remoteshell_wrapper {
    my (%opt) = @_;
    my $helper_contents = $opt{helper};
    my $root = tempdir(CLEANUP => 1);
    my $bin = "$root/bin";
    make_path($bin);

    for my $name (qw(remoteshell xcatlib.sh)) {
        my $source = "$postscripts/$name";
        my $destination = "$bin/$name";
        copy($source, $destination)
          or die "Unable to stage $name: $!";
        chmod 0755, $destination or die "Unable to make $destination executable: $!";
    }
    if (defined $helper_contents) {
        write_text("$bin/remoteshell-sshd-config", $helper_contents);
        chmod 0755, "$bin/remoteshell-sshd-config"
          or die "Unable to make staged helper executable: $!";
    }
    write_text("$bin/logger", "#!/bin/sh\nprintf '%s\\n' \"\$*\" >>'$root/logger.log'\n");
    chmod 0755, "$bin/logger" or die "Unable to make logger executable: $!";

    my $status;
    {
        local %ENV = (
            %ENV,
            PATH     => "$bin:/usr/bin:/bin",
            OSVER    => defined($opt{osver}) ? $opt{osver} : '',
            LOGLABEL => defined($opt{log_label}) ? $opt{log_label} : 'xcat',
        );
        $status = system( "$bin/remoteshell", @{ $opt{args} || [] } );
    }
    return ($status >> 8, read_file("$root/logger.log"));
}

my $ADMIN_POLICY = <<'EOF';
Port 22
MaxStartups 3:30:3
X11Forwarding no
EOF

my $WITH_INCLUDE = "Include /etc/ssh/sshd_config.d/*.conf\n" . $ADMIN_POLICY;

SKIP: {
    skip 'the management-node marker bypasses remoteshell setup', 6
      if -e '/etc/xCATMN';

    my ($missing_status, $missing_log) = run_remoteshell_wrapper();
    isnt($missing_status, 0, 'the wrapper fails when its sshd helper is missing');
    like($missing_log, qr/required sshd configuration helper not found/,
        'the wrapper reports the missing helper');

    my ($failed_status, $failed_log) = run_remoteshell_wrapper(
        helper => "#!/bin/sh\nexit 42\n",
    );
    isnt($failed_status, 0, 'the wrapper fails when its sshd helper fails');
    like($failed_log, qr/failed to configure sshd/,
        'the wrapper reports the failed helper');

    my $recording_helper = <<'SH';
#!/bin/sh
logger -t helper-args -p local4.info "$*"
exit 42
SH
    my ( undef, $plain_log ) = run_remoteshell_wrapper(
        helper    => $recording_helper,
        osver     => 'ubuntu24.04',
        log_label => 'wrapper-test',
    );
    like( $plain_log, qr/-t helper-args -p local4\.info 0 ubuntu24\.04 wrapper-test/m,
        'the wrapper passes the normal helper contract' );

    my ( undef, $pcm_log ) = run_remoteshell_wrapper(
        helper    => $recording_helper,
        osver     => 'ubuntu24.04',
        log_label => 'wrapper-test',
        args      => ['-p'],
    );
    like( $pcm_log, qr/-t helper-args -p local4\.info 1 ubuntu24\.04 wrapper-test/m,
        'the wrapper maps -p to the PCM helper contract' );
}

# --- sshd that reads a drop-in directory -----------------------------------
{
    my $r = run_sshd_helper(sshd_config => $WITH_INCLUDE, dropin_dir => '/etc/ssh/sshd_config.d');
    my $dropin = read_file("$r->{sshdir}/sshd_config.d/01-xcat.conf");

    is($r->{rc}, 0, 'the postscript exits cleanly');
    is($r->{sshd_config}, $r->{untouched}, 'sshd_config is left exactly as the administrator wrote it');
    is($r->{orig}, 0, 'no sshd_config.ORIG copy is made when a drop-in is used');
    like($dropin, qr/^X11Forwarding yes$/m, 'X11Forwarding is set in the drop-in');
    unlike($dropin, qr/MaxStartups/, 'the drop-in does not set MaxStartups');
    ok(!glob("$r->{sshdir}/sshd_config.d/*xcatnew*"), 'no scratch file is left behind');
    like($r->{ssh_config}, qr/^StrictHostKeyChecking no$/m,
        'the client SSH setting is configured by the same helper');
}

# The directory has to come from the file, since an administrator is free to
# point Include somewhere other than /etc/ssh/sshd_config.d.
{
    my $config = "Include /etc/ssh/local.d/*.conf\n" . $ADMIN_POLICY;
    my $r = run_sshd_helper(sshd_config => $config, dropin_dir => '/etc/ssh/local.d');

    ok(-e "$r->{sshdir}/local.d/01-xcat.conf", 'the drop-in follows the Include path in the file');
    ok(!-e "$r->{sshdir}/sshd_config.d/01-xcat.conf", 'no file is written to the assumed default path');
    is($r->{sshd_config}, $r->{untouched}, 'sshd_config is untouched for a custom Include path');
}

# The directory may not exist yet on a freshly installed node.
{
    my $r = run_sshd_helper(sshd_config => $WITH_INCLUDE, dropin_dir => '/etc/ssh/sshd_config.d', skip_dropin_dir => 1);

    ok(-e "$r->{sshdir}/sshd_config.d/01-xcat.conf", 'the drop-in directory is created when missing');
}

# sshd resolves a relative Include under /etc/ssh, so writing it relative to
# wherever the postscript happens to be running would land nowhere useful.
{
    my $config = "Include sshd_config.d/*.conf\n" . $ADMIN_POLICY;
    my $r = run_sshd_helper(sshd_config => $config, dropin_dir => '/etc/ssh/sshd_config.d');

    ok(-e "$r->{sshdir}/sshd_config.d/01-xcat.conf", 'a relative Include is resolved under /etc/ssh');
    is($r->{sshd_config}, $r->{untouched}, 'sshd_config is untouched for a relative Include');
}

# Configuration keywords are not case sensitive.
for my $case (
    ['lower case include', "include /etc/ssh/sshd_config.d/*.conf\n"],
    ['upper case INCLUDE', "INCLUDE /etc/ssh/sshd_config.d/*.conf\n"],
) {
    my ($name, $prefix) = @{$case};
    my $r = run_sshd_helper(sshd_config => $prefix . $ADMIN_POLICY, dropin_dir => '/etc/ssh/sshd_config.d');

    ok(-e "$r->{sshdir}/sshd_config.d/01-xcat.conf", "$name: the keyword is recognised");
}

# Forms that cannot be reduced to one directory have to fall back rather than
# guess, and an Include inside a Match block does not apply to every connection.
for my $case (
    ['several patterns on one line', "Include /etc/ssh/sshd_config.d/*.conf /etc/ssh/other.d/*.conf\n"],
    ['a quoted path',                qq{Include "/etc/ssh/sshd_config.d/*.conf"\n}],
    ['a single file, not a glob',    "Include /etc/ssh/local.conf\n"],
    ['an Include inside Match',      "Match User admin\nInclude /etc/ssh/sshd_config.d/*.conf\n"],
    ['an Include inside MATCH',      "MATCH User admin\nInclude /etc/ssh/sshd_config.d/*.conf\n"],
) {
    my ($name, $prefix) = @{$case};
    my $r = run_sshd_helper(sshd_config => $prefix . $ADMIN_POLICY, dropin_dir => '/etc/ssh/sshd_config.d');

    ok(!-e "$r->{sshdir}/sshd_config.d/01-xcat.conf", "$name: no drop-in is guessed at");
    is($r->{orig}, 1, "$name: falls back to editing sshd_config in place");
}

# A kernel-owned directory cannot accept the scratch file, even as root.  The
# failure must stay quiet and fall back to the main configuration.
SKIP: {
    skip 'procfs is not mounted at /proc', 3 unless -d '/proc/self';

    my $r = run_sshd_helper(
        sshd_config => "Include /proc/*.conf\n" . $ADMIN_POLICY,
    );

    like($r->{sshd_config}, qr/^X11Forwarding yes$/m, 'an unwritable drop-in directory falls back to the in-place edit');
    is($r->{orig}, 1, 'the fallback still keeps a backup copy');
    is($r->{output}, '', 'the expected drop-in fallback does not leak a shell error');
}

# SSH configuration is best effort.  An unwritable client configuration must not
# prevent the wrapper from continuing to install the root keys.
{
    my $r = run_sshd_helper(sshd_config => $WITH_INCLUDE, dropin_dir => '/etc/ssh/sshd_config.d');
    unlink "$r->{sshdir}/ssh_config"
      or die "Unable to remove the client configuration: $!";
    mkdir "$r->{sshdir}/ssh_config"
      or die "Unable to create the unwritable client configuration: $!";
    my $again = run_sshd_helper(reuse => $r);

    is($again->{rc}, 0, 'an unwritable client configuration remains best effort');
}

# An administrator's own file at 01-xcat.conf must not be clobbered; xCAT
# leaves it and edits sshd_config in place instead.
{
    my $r = run_sshd_helper(sshd_config => $WITH_INCLUDE, dropin_dir => '/etc/ssh/sshd_config.d', skip_dropin_dir => 1);
    make_path("$r->{sshdir}/sshd_config.d");
    my $foreign = "$r->{sshdir}/sshd_config.d/01-xcat.conf";
    write_text($foreign, "# admin's own file\nX11Forwarding no\n");
    my $again = run_sshd_helper(reuse => $r);

    is(read_file($foreign), "# admin's own file\nX11Forwarding no\n", 'a foreign 01-xcat.conf is left untouched');
    like($again->{sshd_config}, qr/^X11Forwarding yes$/m, 'the setting falls back to sshd_config when the name is taken');
    is($again->{orig}, 1, 'the fallback keeps a backup copy');
    like($again->{logged}, qr/01-xcat\.conf sets X11Forwarding before the fallback value/,
        'the fallback warns that the earlier fragment still controls X11Forwarding');
}

# The same protection covers the PCM fragment: a foreign 02-xcat-pcm.conf is
# not overwritten, and the PCM setting still lands via the in-place edit rather
# than being silently dropped.
{
    my $config = "Include /etc/ssh/sshd_config.d/*.conf\nPermitRootLogin prohibit-password\n";
    my $r = run_sshd_helper(sshd_config => $config, dropin_dir => '/etc/ssh/sshd_config.d', skip_dropin_dir => 1);
    make_path("$r->{sshdir}/sshd_config.d");
    my $foreign = "$r->{sshdir}/sshd_config.d/02-xcat-pcm.conf";
    write_text($foreign, "# admin's own file\nPermitRootLogin no\n");
    my $again = run_sshd_helper(reuse => $r, pcm => 1, osver => 'ubuntu24.04');

    is(read_file($foreign), "# admin's own file\nPermitRootLogin no\n", 'a foreign 02-xcat-pcm.conf is left untouched');
    like($again->{sshd_config}, qr/^PermitRootLogin yes$/m, 'PCM falls back to the in-place edit when its fragment cannot be written');
    like($again->{logged}, qr/02-xcat-pcm\.conf sets PermitRootLogin before the fallback value/,
        'the PCM fallback warns that the earlier fragment still controls root login');
}

{
    my $config = "Include /etc/ssh/sshd_config.d/*.conf\n#PermitRootLogin prohibit-password\n";
    my $r = run_sshd_helper(
        sshd_config => $config,
        dropin_dir  => '/etc/ssh/sshd_config.d',
        pcm         => 1,
        osver       => 'ubuntu24.04',
    );

    ok(!-e "$r->{sshdir}/sshd_config.d/02-xcat-pcm.conf",
        'Ubuntu PCM does not create a root-login setting when none was active');
    is($r->{sshd_config}, $r->{untouched},
        'Ubuntu PCM preserves a commented root-login default');
}

# sshd allows glob metacharacters anywhere in an Include path.  A parent that is
# itself a pattern (sshd_config.[12].d) must not be written to literally.
{
    my $config = "Include /etc/ssh/sshd_config.[12].d/*.conf\n" . $ADMIN_POLICY;
    my $r = run_sshd_helper(sshd_config => $config);

    ok(!-e "$r->{sshdir}/sshd_config.[12].d", 'no literal directory is created for a glob parent');
    like($r->{sshd_config}, qr/^X11Forwarding yes$/m, 'a glob parent falls back to the in-place edit');
    is($r->{orig}, 1, 'the glob-parent fallback keeps a backup copy');
}

# --- sshd without Include support ------------------------------------------
for my $case (
    ['no Include line at all', $ADMIN_POLICY],
    ['Include commented out',  "#Include /etc/ssh/sshd_config.d/*.conf\n" . $ADMIN_POLICY],
) {
    my ($name, $config) = @{$case};
    my $r = run_sshd_helper(sshd_config => $config);

    like($r->{sshd_config}, qr/^X11Forwarding yes$/m, "$name: X11Forwarding is set in sshd_config");
    unlike($r->{sshd_config}, qr/^X11Forwarding no$/m, "$name: the old X11Forwarding line is removed");
    is($r->{orig}, 1, "$name: sshd_config.ORIG is kept as a backup");
    ok(!-e "$r->{sshdir}/sshd_config.d/01-xcat.conf", "$name: no drop-in is written");
}

# --- MaxStartups belongs to the administrator ------------------------------
for my $case (
    ['with a drop-in directory', $WITH_INCLUDE,  '/etc/ssh/sshd_config.d'],
    ['editing in place',         $ADMIN_POLICY,  undef],
) {
    my ($name, $config, $dir) = @{$case};
    my $r = run_sshd_helper(sshd_config => $config, dropin_dir => $dir);

    like($r->{sshd_config}, qr/^MaxStartups 3:30:3$/m, "$name: the administrator's MaxStartups survives");
}

# --- the PCM settings keep their own fragment ------------------------------
# updatenode reruns remoteshell without -p, so anything the PCM setup wrote has
# to survive a plain run.
{
    my $config = "Include /etc/ssh/sshd_config.d/*.conf\nPermitRootLogin prohibit-password\n";
    my $r = run_sshd_helper(
        sshd_config => $config,
        dropin_dir  => '/etc/ssh/sshd_config.d',
        pcm         => 1,
        osver       => 'ubuntu24.04',
    );

    like(read_file("$r->{sshdir}/sshd_config.d/02-xcat-pcm.conf"), qr/^PermitRootLogin yes$/m,
        'PermitRootLogin goes to its own fragment on Ubuntu');
    unlike(read_file("$r->{sshdir}/sshd_config.d/01-xcat.conf"), qr/PermitRootLogin/,
        'the PCM setting is kept out of 01-xcat.conf');
    is($r->{sshd_config}, $r->{untouched}, 'sshd_config is untouched by the PCM setup');

    my $again = run_sshd_helper(reuse => $r, osver => 'ubuntu24.04');
    like(read_file("$again->{sshdir}/sshd_config.d/02-xcat-pcm.conf"), qr/^PermitRootLogin yes$/m,
        'a later run without -p leaves the PCM setting alone');
    like(read_file("$again->{sshdir}/sshd_config.d/01-xcat.conf"), qr/^X11Forwarding yes$/m,
        'the later run still refreshes its own fragment');
}

{
    my $config = "Include /etc/ssh/sshd_config.d/*.conf\nPasswordAuthentication no\n";
    my $r = run_sshd_helper(
        sshd_config => $config,
        dropin_dir  => '/etc/ssh/sshd_config.d',
        pcm         => 1,
        osver       => 'sles15',
    );

    like(read_file("$r->{sshdir}/sshd_config.d/02-xcat-pcm.conf"), qr/^PasswordAuthentication yes$/m,
        'PasswordAuthentication goes to its own fragment on SLES');

    my $again = run_sshd_helper(reuse => $r, osver => 'sles15');
    like(read_file("$again->{sshdir}/sshd_config.d/02-xcat-pcm.conf"), qr/^PasswordAuthentication yes$/m,
        'a later run without -p leaves the SLES setting alone');
}

# Without a drop-in directory the PCM settings are still edited in place.
{
    my $r = run_sshd_helper(sshd_config => "PasswordAuthentication no\n", pcm => 1, osver => 'sles15');

    like($r->{sshd_config}, qr/^PasswordAuthentication yes$/m, 'PasswordAuthentication is edited in place on SLES');
    unlike($r->{sshd_config}, qr/^PasswordAuthentication no$/m, 'the old PasswordAuthentication line is removed');
}

# sshd keeps the first value it finds, so a keyword set ahead of the Include
# line still wins over the drop-in. The postscript detects that and warns.
{
    my $r = run_sshd_helper(
        sshd_config => "X11Forwarding no\nInclude /etc/ssh/sshd_config.d/*.conf\nPort 22\n" );

    like( $r->{logged}, qr/X11Forwarding is set before the Include line/,
        'a keyword set before the Include line is reported' );
    like( $r->{logged}, qr{01-xcat\.conf},
        'the report names the fragment that is overridden' );
}

# The same keyword after the Include line does not override the drop-in.
{
    my $r = run_sshd_helper(
        sshd_config => "Include /etc/ssh/sshd_config.d/*.conf\nX11Forwarding no\nPort 22\n" );

    unlike( $r->{logged}, qr/X11Forwarding is set before the Include line/,
        'a keyword set after the Include line is not reported' );
}

# The Include keyword is matched whatever its case and leading spacing.
{
    my $r = run_sshd_helper(
        sshd_config => "X11Forwarding no\n   inClUdE /etc/ssh/sshd_config.d/*.conf\nPort 22\n" );

    like( $r->{logged}, qr/X11Forwarding is set before the Include line/,
        'the Include line is recognised whatever its case and spacing' );
}

# A keyword that merely starts with the Include name is not an Include line.
{
    my $r = run_sshd_helper(
        sshd_config => "IncludeFoo bar\nX11Forwarding no\nInclude /etc/ssh/sshd_config.d/*.conf\n" );

    like( $r->{logged}, qr/X11Forwarding is set before the Include line/,
        'a keyword that only begins with Include does not end the search' );
}

# An earlier Include that is not the selected drop-in glob does not end the
# precedence scan either.
{
    my $r = run_sshd_helper(
        sshd_config => "Include /etc/ssh/local.conf\nX11Forwarding no\nInclude /etc/ssh/sshd_config.d/*.conf\n" );

    like( $r->{logged}, qr/X11Forwarding is set before the Include line/,
        'an unrelated earlier Include does not hide an overriding keyword' );
}

done_testing();
