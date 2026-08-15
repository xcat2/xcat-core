#!/usr/bin/env perl
use strict;
use warnings;

use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

my $postscripts = "$FindBin::Bin/../../xCAT/postscripts";
my $remoteshell = "$postscripts/remoteshell";
plan skip_all => 'remoteshell postscript not found' unless -r $remoteshell;
# The postscript is written against GNU sed; sed -i means something else on BSD.
plan skip_all => 'postscript targets Linux nodes' unless $^O eq 'linux';
# The CI runner installs xCAT (creating /etc/xCATMN) before running unit tests,
# and the postscript exits early when that marker exists.  Its check is
# redirected into the scratch root below so this test runs instead of skipping.

# The sshd_config handling lives at the top of remoteshell, before the script
# starts fetching credentials from the xcatmaster.  Run that part for real
# against a scratch /etc/ssh so the branching, the Include detection and the
# sed edits are all exercised as written.
my $source = do {
    open my $fh, '<', $remoteshell or die "open $remoteshell: $!";
    local $/;
    <$fh>;
};

my $anchor = 'xcatpost="xcatpost"';
ok(index($source, $anchor) > 0, 'credential-fetching section still starts at the expected anchor');

sub run_remoteshell {
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
        write_file("$sshdir/sshd_config", $config);
        write_file("$sshdir/ssh_config",  "Host *\n");
        make_path("$root$opt{dropin_dir}") if $opt{dropin_dir} && !$opt{skip_dropin_dir};

        # logger is not present everywhere and would write to the real syslog.
        write_file("$root/bin/logger", "#!/bin/sh\nexit 0\n");
        chmod 0755, "$root/bin/logger";

        my ($body) = $source =~ /\A(.*?)^\Q$anchor\E/ms;
        $body =~ s{/etc/ssh}{$sshdir}g;
        # Point the management-node guard at the scratch tree so it never sees
        # the real /etc/xCATMN the CI runner installs.
        $body =~ s{/etc/xCATMN}{$root/etc/xCATMN}g;
        write_file("$root/remoteshell", $body);
        chmod 0755, "$root/remoteshell";
        copy("$postscripts/xcatlib.sh", "$root/xcatlib.sh") if -r "$postscripts/xcatlib.sh";
    }

    my @args = $opt{pcm} ? ('-p') : ();
    my $rc;
    {
        local $ENV{OSVER} = defined $opt{osver} ? $opt{osver} : '';
        local $ENV{PATH}  = "$root/bin:$ENV{PATH}";
        $rc = system("cd '$root' && ./remoteshell @args >/dev/null 2>&1");
    }

    return {
        root        => $root,
        sshdir      => $sshdir,
        sshd_config => read_file("$sshdir/sshd_config"),
        untouched   => $config,
        orig        => (-e "$sshdir/sshd_config.ORIG" ? 1 : 0),
        rc          => $rc,
    };
}

sub write_file {
    my ($path, $content) = @_;
    open my $fh, '>', $path or die "open $path: $!";
    print {$fh} $content;
    close $fh;
    return;
}

sub read_file {
    my ($path) = @_;
    return '' unless -e $path;
    open my $fh, '<', $path or die "open $path: $!";
    local $/;
    return <$fh>;
}

my $ADMIN_POLICY = <<'EOF';
Port 22
MaxStartups 3:30:3
X11Forwarding no
EOF

my $WITH_INCLUDE = "Include /etc/ssh/sshd_config.d/*.conf\n" . $ADMIN_POLICY;

# --- sshd that reads a drop-in directory -----------------------------------
{
    my $r = run_remoteshell(sshd_config => $WITH_INCLUDE, dropin_dir => '/etc/ssh/sshd_config.d');
    my $dropin = read_file("$r->{sshdir}/sshd_config.d/01-xcat.conf");

    is($r->{rc}, 0, 'the postscript exits cleanly');
    is($r->{sshd_config}, $r->{untouched}, 'sshd_config is left exactly as the administrator wrote it');
    is($r->{orig}, 0, 'no sshd_config.ORIG copy is made when a drop-in is used');
    like($dropin, qr/^X11Forwarding yes$/m, 'X11Forwarding is set in the drop-in');
    unlike($dropin, qr/MaxStartups/, 'the drop-in does not set MaxStartups');
    ok(!glob("$r->{sshdir}/sshd_config.d/*xcatnew*"), 'no scratch file is left behind');
}

# The directory has to come from the file, since an administrator is free to
# point Include somewhere other than /etc/ssh/sshd_config.d.
{
    my $config = "Include /etc/ssh/local.d/*.conf\n" . $ADMIN_POLICY;
    my $r = run_remoteshell(sshd_config => $config, dropin_dir => '/etc/ssh/local.d');

    ok(-e "$r->{sshdir}/local.d/01-xcat.conf", 'the drop-in follows the Include path in the file');
    ok(!-e "$r->{sshdir}/sshd_config.d/01-xcat.conf", 'no file is written to the assumed default path');
    is($r->{sshd_config}, $r->{untouched}, 'sshd_config is untouched for a custom Include path');
}

# The directory may not exist yet on a freshly installed node.
{
    my $r = run_remoteshell(sshd_config => $WITH_INCLUDE, dropin_dir => '/etc/ssh/sshd_config.d', skip_dropin_dir => 1);

    ok(-e "$r->{sshdir}/sshd_config.d/01-xcat.conf", 'the drop-in directory is created when missing');
}

# sshd resolves a relative Include under /etc/ssh, so writing it relative to
# wherever the postscript happens to be running would land nowhere useful.
{
    my $config = "Include sshd_config.d/*.conf\n" . $ADMIN_POLICY;
    my $r = run_remoteshell(sshd_config => $config, dropin_dir => '/etc/ssh/sshd_config.d');

    ok(-e "$r->{sshdir}/sshd_config.d/01-xcat.conf", 'a relative Include is resolved under /etc/ssh');
    is($r->{sshd_config}, $r->{untouched}, 'sshd_config is untouched for a relative Include');
}

# Configuration keywords are not case sensitive.
for my $case (
    ['lower case include', "include /etc/ssh/sshd_config.d/*.conf\n"],
    ['upper case INCLUDE', "INCLUDE /etc/ssh/sshd_config.d/*.conf\n"],
) {
    my ($name, $prefix) = @{$case};
    my $r = run_remoteshell(sshd_config => $prefix . $ADMIN_POLICY, dropin_dir => '/etc/ssh/sshd_config.d');

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
    my $r = run_remoteshell(sshd_config => $prefix . $ADMIN_POLICY, dropin_dir => '/etc/ssh/sshd_config.d');

    ok(!-e "$r->{sshdir}/sshd_config.d/01-xcat.conf", "$name: no drop-in is guessed at");
    is($r->{orig}, 1, "$name: falls back to editing sshd_config in place");
}

# A drop-in directory that cannot be written to must not swallow the settings.
SKIP: {
    skip 'root ignores directory permissions', 2 if $> == 0;

    my $r = run_remoteshell(sshd_config => $WITH_INCLUDE, dropin_dir => '/etc/ssh/sshd_config.d', skip_dropin_dir => 1);
    # Put a read-only directory in the way and deploy again.
    chmod 0500, "$r->{sshdir}/sshd_config.d";
    unlink "$r->{sshdir}/sshd_config.d/01-xcat.conf";
    my $again = run_remoteshell(reuse => $r);
    chmod 0700, "$r->{sshdir}/sshd_config.d";

    like($again->{sshd_config}, qr/^X11Forwarding yes$/m, 'an unwritable drop-in directory falls back to the in-place edit');
    is($again->{orig}, 1, 'the fallback still keeps a backup copy');
}

# An administrator's own file at 01-xcat.conf must not be clobbered; xCAT
# leaves it and edits sshd_config in place instead.
{
    my $r = run_remoteshell(sshd_config => $WITH_INCLUDE, dropin_dir => '/etc/ssh/sshd_config.d', skip_dropin_dir => 1);
    make_path("$r->{sshdir}/sshd_config.d");
    my $foreign = "$r->{sshdir}/sshd_config.d/01-xcat.conf";
    write_file($foreign, "# admin's own file\nX11Forwarding no\n");
    my $again = run_remoteshell(reuse => $r);

    is(read_file($foreign), "# admin's own file\nX11Forwarding no\n", 'a foreign 01-xcat.conf is left untouched');
    like($again->{sshd_config}, qr/^X11Forwarding yes$/m, 'the setting falls back to sshd_config when the name is taken');
    is($again->{orig}, 1, 'the fallback keeps a backup copy');
}

# The same protection covers the PCM fragment: a foreign 02-xcat-pcm.conf is
# not overwritten, and the PCM setting still lands via the in-place edit rather
# than being silently dropped.
{
    my $config = "Include /etc/ssh/sshd_config.d/*.conf\nPermitRootLogin prohibit-password\n";
    my $r = run_remoteshell(sshd_config => $config, dropin_dir => '/etc/ssh/sshd_config.d', skip_dropin_dir => 1);
    make_path("$r->{sshdir}/sshd_config.d");
    my $foreign = "$r->{sshdir}/sshd_config.d/02-xcat-pcm.conf";
    write_file($foreign, "# admin's own file\nPermitRootLogin no\n");
    my $again = run_remoteshell(reuse => $r, pcm => 1, osver => 'ubuntu24.04');

    is(read_file($foreign), "# admin's own file\nPermitRootLogin no\n", 'a foreign 02-xcat-pcm.conf is left untouched');
    like($again->{sshd_config}, qr/^PermitRootLogin yes$/m, 'PCM falls back to the in-place edit when its fragment cannot be written');
}

# sshd allows glob metacharacters anywhere in an Include path.  A parent that is
# itself a pattern (sshd_config.[12].d) must not be written to literally.
{
    my $config = "Include /etc/ssh/sshd_config.[12].d/*.conf\n" . $ADMIN_POLICY;
    my $r = run_remoteshell(sshd_config => $config);

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
    my $r = run_remoteshell(sshd_config => $config);

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
    my $r = run_remoteshell(sshd_config => $config, dropin_dir => $dir);

    like($r->{sshd_config}, qr/^MaxStartups 3:30:3$/m, "$name: the administrator's MaxStartups survives");
}

# --- the PCM settings keep their own fragment ------------------------------
# updatenode reruns remoteshell without -p, so anything the PCM setup wrote has
# to survive a plain run.
{
    my $config = "Include /etc/ssh/sshd_config.d/*.conf\nPermitRootLogin prohibit-password\n";
    my $r = run_remoteshell(
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

    my $again = run_remoteshell(reuse => $r, osver => 'ubuntu24.04');
    like(read_file("$again->{sshdir}/sshd_config.d/02-xcat-pcm.conf"), qr/^PermitRootLogin yes$/m,
        'a later run without -p leaves the PCM setting alone');
    like(read_file("$again->{sshdir}/sshd_config.d/01-xcat.conf"), qr/^X11Forwarding yes$/m,
        'the later run still refreshes its own fragment');
}

{
    my $config = "Include /etc/ssh/sshd_config.d/*.conf\nPasswordAuthentication no\n";
    my $r = run_remoteshell(
        sshd_config => $config,
        dropin_dir  => '/etc/ssh/sshd_config.d',
        pcm         => 1,
        osver       => 'sles15',
    );

    like(read_file("$r->{sshdir}/sshd_config.d/02-xcat-pcm.conf"), qr/^PasswordAuthentication yes$/m,
        'PasswordAuthentication goes to its own fragment on SLES');

    my $again = run_remoteshell(reuse => $r, osver => 'sles15');
    like(read_file("$again->{sshdir}/sshd_config.d/02-xcat-pcm.conf"), qr/^PasswordAuthentication yes$/m,
        'a later run without -p leaves the SLES setting alone');
}

# Without a drop-in directory the PCM settings are still edited in place.
{
    my $r = run_remoteshell(sshd_config => "PasswordAuthentication no\n", pcm => 1, osver => 'sles15');

    like($r->{sshd_config}, qr/^PasswordAuthentication yes$/m, 'PasswordAuthentication is edited in place on SLES');
    unlike($r->{sshd_config}, qr/^PasswordAuthentication no$/m, 'the old PasswordAuthentication line is removed');
}

done_testing();
