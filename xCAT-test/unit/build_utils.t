#!/usr/bin/env perl
# BuildUtils.pm: the helpers buildrpms.pl and builddebs.pl share.
#
# Every function here is pure, so every assertion below RUNS it. Nothing in this file
# reads the builders' source to check that they call it -- that would pass with the
# call removed.
use strict;
use warnings;

use File::Path qw(make_path);
use File::Slurper qw(read_text write_text);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../..";
use Test::More;

BEGIN { use_ok('BuildUtils') or BAIL_OUT('BuildUtils.pm does not load'); }

use BuildUtils qw(
    source_date_epoch snap_release deb_version
    stage_probe_helpers XCAT_PROBE_HELPERS
    deb_package_arches dist_arches
    orig_tarball_name upstream_version resolve_dest
    pin_control_version rewrite_changelog_header
    reprepro_distributions reprepro_options sh_quote
);

# ------------------------------------------------------------------- versions --

is( snap_release(1756000000), 'snap202508240146',
    'the release is the commit time, to the minute, in UTC' );
is( snap_release(1756000000), snap_release(1756000000),
    'the same commit time always gives the same release' );
isnt( snap_release(1756000000), snap_release(1756000060),
    'a different commit time gives a different release' );

is( deb_version('2.19.0', 'snap202608240826'), '2.19.0-snap202608240826',
    'the deb version is the same Version-Release the rpms carry' );

# Gitepoch wins so every arch of one release stamps an identical epoch.
is( source_date_epoch(read_file => sub { '1756000000' },
                      git_epoch => sub { '1700000000' }), 1756000000,
    'Gitepoch is preferred over the git log' );
is( source_date_epoch(read_file => sub { undef },
                      git_epoch => sub { "1700000000\n" }), 1700000000,
    'the git commit time is used when Gitepoch is absent' );
is( source_date_epoch(read_file => sub { "not-a-number\n" },
                      git_epoch => sub { '1700000000' }), 1700000000,
    'a corrupt Gitepoch falls through to the git log rather than being trusted' );
is( source_date_epoch(read_file => sub { undef },
                      git_epoch => sub { '' }, now => 42), 42,
    'with no git and no Gitepoch the caller-supplied clock is the last resort' );

# ---------------------------------------------------------------- deb layout --

is_deeply( [deb_package_arches('perl-xCAT')], ['all'],
    'a Perl package is built once, arch-independent' );
is_deeply( [deb_package_arches('xCAT-probe')], ['all'],
    'xCAT-probe is arch-independent too' );
for my $pkg (qw(xCAT xCATsn xCAT-genesis-scripts)) {
    is_deeply( [deb_package_arches($pkg)], ['amd64', 'ppc64el'],
        "$pkg is built per architecture" );
}
is_deeply( [deb_package_arches(undef)], ['all'],
    'an undefined package name does not blow up the arch lookup' );

is_deeply( [dist_arches('noble')], ['amd64', 'ppc64el'],
    'a current release serves both architectures' );
is_deeply( [dist_arches('saucy')], ['amd64'],
    'saucy predates ppc64el and serves only amd64' );

# dpkg looks for <source>_<upstream>.orig.tar.gz -- no Debian revision, because one
# upstream tarball is shared by every revision built from it.
is( orig_tarball_name('xCAT-server', '2.19.0-snap202608240826'),
    'xcat-server_2.19.0.orig.tar.gz',
    'the orig tarball carries the upstream version, not the Debian revision' );
is( orig_tarball_name('xCAT-server', '2.19.0'),
    'xcat-server_2.19.0.orig.tar.gz',
    'and is the same name when handed the upstream version directly' );
is( upstream_version('2.19.0-snap1'), '2.19.0', 'the Debian revision is stripped' );
is( upstream_version('2.19.0'), '2.19.0', 'a bare upstream version is unchanged' );
is( upstream_version('1.2.3-4-5'), '1.2.3-4', 'only the LAST hyphen separates the revision' );
is( upstream_version(undef), '', 'an undefined version does not blow up' );

# resolve_dest must not use Cwd::abs_path: that returns undef when a PARENT component
# is missing, and the caller then builds "/debs" and "/xcat-core" at the root.
is( resolve_dest(undef, '/default/out'), '/default/out',
    'no --dest falls back to the default' );
is( resolve_dest('', '/default/out'), '/default/out',
    'an empty --dest falls back too' );
is( resolve_dest('/no-such-parent-xyz/out', '/default'), '/no-such-parent-xyz/out',
    'a --dest whose parent does not exist resolves to itself, never undef' );
like( resolve_dest('relative/out', '/default'), qr{^/.*relative/out$},
    'a relative --dest becomes absolute' );

# ------------------------------------------------------------------- control --

my $control = <<'CTRL';
Package: xCAT
Depends: perl-xCAT (>= 2.13-snap000000000000), xCAT-server (>= 2.13-snap000000000000)
CTRL
my $pinned = pin_control_version($control, '2.19.0-snap202608240826');
like( $pinned, qr/perl-xCAT \(= 2\.19\.0-snap202608240826\)/,
    'the sentinel dependency is pinned to this exact build' );
unlike( $pinned, qr/2\.13-snap000000000000/,
    'no sentinel survives, so apt cannot satisfy it with an older xCAT' );
is( scalar(() = $pinned =~ /= 2\.19\.0-snap202608240826/g), 2,
    'every occurrence is pinned, not just the first' );
is( pin_control_version(undef, '2.19.0'), undef,
    'an absent control file is passed through rather than dying' );

# ----------------------------------------------------------------- changelog --

my $changelog = <<'CHANGELOG';
xcat (2.18.0-snap000000000000) unstable; urgency=low

  * upstream

 -- Somebody Else <nobody@example.invalid>  Mon, 01 Jan 2024 00:00:00 +0000

xcat (2.17.0) unstable; urgency=low

  * older

 -- Somebody Else <nobody@example.invalid>  Mon, 01 Jan 2023 00:00:00 +0000
CHANGELOG

my $rewritten = rewrite_changelog_header(
    $changelog, '2.19.0-snap202608240826',
    'Sat, 24 Aug 2026 08:26:40 +0000', 'xCAT Build <build@xcat.invalid>');

like( $rewritten, qr/\Axcat \(2\.19\.0-snap202608240826\) unstable/,
    'the top stanza carries the version being built' );
like( $rewritten, qr/^ -- xCAT Build <build\@xcat\.invalid>  Sat, 24 Aug 2026 08:26:40 \+0000$/m,
    'and the deterministic date, so two builds of one commit match' );
like( $rewritten, qr/^xcat \(2\.17\.0\) unstable/m,
    'the older stanza is left alone -- the history is not ours to rewrite' );

# ------------------------------------------------------------------ reprepro --

my $dists = reprepro_distributions([qw(focal noble)], 'DEADBEEF');
is( scalar(() = $dists =~ /^Codename:/mg), 2, 'one stanza per release' );
like( $dists, qr/^Codename: focal\nArchitectures: amd64 ppc64el$/m,
    'a release declares both architectures, on the line after its codename' );
is( scalar(() = $dists =~ /^SignWith: DEADBEEF$/mg), 2,
    'every stanza is signed when a key is given' );

my $unsigned = reprepro_distributions([qw(noble)], undef);
unlike( $unsigned, qr/SignWith/, 'no SignWith line without a key' );
like( $unsigned, qr/\n\n\z/, 'stanzas stay blank-line separated so reprepro can parse them' );

like( reprepro_distributions([qw(saucy)], undef), qr/^Architectures: amd64$/m,
    'saucy declares only the architecture it had' );

like( reprepro_options(undef), qr/^ask-passphrase$/m,
    'an interactive build may be asked for a passphrase' );
unlike( reprepro_options('/some/gnupghome'), qr/ask-passphrase/,
    'a build given a GNUPGHOME must never stop to prompt' );
like( reprepro_options('/some/gnupghome'), qr/^basedir \.$/m,
    'and still sets its basedir' );

# --------------------------------------------------------------------- files --

{
    my $root = tempdir(CLEANUP => 1);
    my $from = File::Spec->catdir($root, 'perl-xCAT', 'xCAT');
    my $to   = File::Spec->catdir($root, 'xCAT-probe', 'lib', 'perl', 'xCAT');
    make_path($from);
    write_text(File::Spec->catfile($from, $_), "package $_;\n1;\n")
        for XCAT_PROBE_HELPERS;

    my @staged = stage_probe_helpers($from, $to);
    is( scalar @staged, scalar(my @h = XCAT_PROBE_HELPERS),
        'every probe helper is staged' );
    for my $helper (XCAT_PROBE_HELPERS) {
        my $path = File::Spec->catfile($to, $helper);
        ok( -f $path, "$helper reaches the probe tree" );
        is( read_text($path), "package $helper;\n1;\n",
            "$helper arrives with its content intact" );
    }
    # Copied, not linked: a symlink does not survive packaging.
    ok( !-l File::Spec->catfile($to, 'GlobalDef.pm'),
        'the helpers are real files, not symlinks' );
}

{
    my $root = tempdir(CLEANUP => 1);
    my $ok = eval {
        stage_probe_helpers(File::Spec->catdir($root, 'absent'),
                            File::Spec->catdir($root, 'dest'));
        1;
    };
    ok( !$ok, 'a missing helper is fatal rather than a silently incomplete package' );
}

# -------------------------------------------------------------------- quoting --

is( sh_quote(q{it's}), q{'it'"'"'s'}, 'a single quote survives shell quoting' );
is( sh_quote(undef), q{''}, 'undef quotes to the empty string' );

done_testing();
