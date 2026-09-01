#!/usr/bin/perl
# Build the xcat-core Debian packages and assemble a signed apt repository.
#
# Replaces build-ubunturepo. The shape mirrors buildrpms.pl -- Getopt::Long options,
# one package list, build then index then sign -- so the two builders read the same way
# and share BuildUtils.pm.
#
# The central fact this design rests on: xcat-core debs are Perl. They are byte-identical
# for every Ubuntu release, so they are built ONCE and the same files are published into
# every codename. Only xCAT, xCATsn and xCAT-genesis-scripts carry an architecture, and
# even there the difference is packaging metadata, not compiled output. That is why this
# needs no sbuild and no per-codename chroot -- unlike xcat-dep, whose compiled packages
# genuinely differ per release.
use strict;
use warnings;
use feature 'say';

use Cwd qw(abs_path);
use File::Basename qw(basename);
use File::Copy qw(copy move);
use File::Path qw(make_path remove_tree);
use File::Spec;
use File::Temp qw(tempdir);
use Getopt::Long qw(GetOptions);
use POSIX qw(strftime);
use Pod::Usage qw(pod2usage);

use FindBin;
use lib $FindBin::Bin;
use BuildUtils qw(
    source_date_epoch snap_release deb_version
    stage_probe_helpers XCAT_PROBE_HELPERS
    deb_package_arches dist_arches default_dists
    orig_tarball_name upstream_version resolve_dest clean_debian_residue
    backup_file restore_file git_revision
    pin_control_version rewrite_changelog_header
    reprepro_distributions reprepro_options
    lock_id_for take_build_lock sh_quote
    sh usage read_file write_file rewrite_file write_script buildinfo_text
);

# The xcat-core packages that ship as debs. xCAT-openbmc-py, xCAT-rmc and xCAT-release
# are rpm-only and are deliberately absent.
my @PACKAGES = qw(
    perl-xCAT
    xCAT
    xCATsn
    xCAT-buildkit
    xCAT-client
    xCAT-confluent
    xCAT-genesis-scripts
    xCAT-probe
    xCAT-server
    xCAT-test
    xCAT-vlan
);

# Releases the repo serves. The same debs are published into each; the list itself
# lives in BuildUtils so the builder and the tests cannot disagree about it.
my @DISTS = default_dists();

my %opts;
my (@cli_packages, @cli_dists);
GetOptions(
    "dist=s@"          => \@cli_dists,
    "package=s@"       => \@cli_packages,
    "dest=s"           => \$opts{dest},
    "builddir=s"       => \$opts{builddir},
    "release=s"        => \$opts{release},
    "gpg-sign"         => \$opts{gpg_sign},
    "gpg-home=s"       => \$opts{gpg_home},
    "gpg-key-name=s"   => \$opts{gpg_key_name},
    "force"            => \$opts{force},
    "verbose"          => \$opts{verbose},
    "help"             => \$opts{help},
) or usage();
usage(exitval => 0, verbose => 2) if $opts{help};

$BuildUtils::VERBOSE = $opts{verbose};

$opts{packages} = @cli_packages ? \@cli_packages : \@PACKAGES;
$opts{dists}    = @cli_dists    ? \@cli_dists    : \@DISTS;
$opts{gpg_key_name} //= 'xCAT Signing Key';

for my $pkg ($opts{packages}->@*) {
    die "FATAL: unknown package '$pkg'. Known: @PACKAGES\n"
        unless grep { $_ eq $pkg } @PACKAGES;
}

my $ROOT    = abs_path($FindBin::Bin);
my $VERSION = do { open my $fh, '<', "$ROOT/Version" or die "Cannot read Version: $!\n";
                   my $v = <$fh>; chomp $v; $v };
my $EPOCH   = source_date_epoch();
# A Release file, when present, is authoritative: buildrpms.pl writes one, and a
# pipeline that builds both must stamp the rpms and the debs with the same release.
my $FILE_RELEASE = do {
    my $r;
    if (-f "$ROOT/Release") {
        open my $fh, '<', "$ROOT/Release" or die "Cannot read Release: $!\n";
        $r = <$fh>;
        chomp $r if defined $r;
    }
    ($r && $r =~ /\S/) ? $r : undef;
};
my $RELEASE = $opts{release} || $FILE_RELEASE || snap_release($EPOCH);
my $PKGVER  = deb_version($VERSION, $RELEASE);
$ENV{SOURCE_DATE_EPOCH} = $EPOCH;

# Gitinfo is what perl-xCAT/debian/rules hands modifyUtils as the commit. Without it
# modifyUtils does nothing at all and the built xCAT reports no version -- `lsxcatd -v`
# prints a bare "Version" -- so it is written here rather than left to debian/rules'
# `git log` fallback, which produces nothing when the tree has no .git (a source
# export, or a checkout that was copied rather than cloned).
my $GITINFO = git_revision();
if ($GITINFO eq 'unknown') {
    # Say so. The usual cause is not a missing .git but git refusing to read one it
    # considers dubiously owned -- the tree belongs to another user, and the
    # safe.directory exception lives in a config that the build's own HOME hides.
    # Silence here is how packages end up stamped with a provenance nobody notices.
    warn "WARNING: no git revision for $ROOT; packages will be stamped "
       . "'(git commit unknown)'.\n"
       . "         If $ROOT is a git checkout, check `git -C $ROOT rev-parse HEAD` "
       . "as the build user (HOME=$ENV{HOME}).\n";
}
{
    open my $g, '>', "$ROOT/Gitinfo" or die "Cannot write Gitinfo: $!\n";
    print {$g} "$GITINFO\n";
    close $g;
}

# dpkg reads these for the changelog trailer. Fixed, so the packages do not carry
# whoever happened to run the build.
$ENV{DEBFULLNAME} = 'xCAT Build';
$ENV{DEBEMAIL}    = 'xcat-build@xcat.org';
my $MAINTAINER = "$ENV{DEBFULLNAME} <$ENV{DEBEMAIL}>";
my $DEB_DATE   = strftime('%a, %d %b %Y %H:%M:%S +0000', gmtime($EPOCH));

# The build lock is scoped to this checkout, not the host -- see BuildUtils::lock_id_for.

# ------------------------------------------------------------------ staging --
#
# Each package is prepared, built, and put back exactly as it was. dpkg-buildpackage
# has no --define equivalent, so the version has to be written into the tree; leaving it
# there would dirty the checkout the CD pipeline builds from.
sub with_prepared_tree {
    my ($pkg, $arch, $body) = @_;
    my $dir = "$ROOT/$pkg";
    my @restore;

    my @remove;

    # Back up a file the build is about to edit, or -- when it does not exist yet --
    # note that the build is CREATING it so it can be taken away again.
    # xCAT-genesis-scripts has no debian/control of its own; it is generated from
    # control-<arch>. Restoring only pre-existing files left that generated file in
    # the checkout, so the tree ended dirty and a later single-arch build would start
    # from the other architecture's control.
    my $claim = sub {
        my ($rel) = @_;
        my $path = "$dir/$rel";
        if (-f $path) {
            push @restore, backup_file($path);
        }
        else {
            push @remove, $path;
        }
    };

    $claim->('debian/control');
    $claim->('debian/changelog');
    # dpkg rewrites debian/<pkg>.substvars in place, and several of them are tracked.
    $claim->("debian/" . basename($_)) for glob("$dir/debian/*.substvars");

    # Pin the intra-xCAT dependencies to this exact build, so a partial upgrade cannot
    # mix versions.
    my $control = "$dir/debian/control";
    rewrite_file($control, sub { pin_control_version($_[0], $PKGVER) });

    my $changelog = "$dir/debian/changelog";
    rewrite_file($changelog,
        sub { rewrite_changelog_header($_[0], $PKGVER, $DEB_DATE, $MAINTAINER) });
    unlink glob("$dir/debian/*.dch");

    my @added;
    # xcat-probe reuses functions shipped by xCAT. Copied, not linked: a symlink does
    # not survive packaging, and maintaining two copies lets them drift.
    if ($pkg eq 'xCAT-probe') {
        push @added, stage_probe_helpers("$ROOT/perl-xCAT/xCAT", "$dir/lib/perl/xCAT");
    }
    # xCAT ships the genesis bmcsetup/getipmi helpers as postscripts, renamed.
    if ($pkg eq 'xCAT') {
        for my $f (qw(bmcsetup getipmi)) {
            my $src = "$ROOT/xCAT-genesis-scripts/usr/bin/$f";
            next unless -f $src;
            my $dst = "$dir/postscripts/$f";
            # Both are TRACKED files. Claiming them backs the originals up and puts
            # them back; treating them as created would delete them from the
            # checkout, which is what happened before.
            $claim->("postscripts/$f");
            my $text = read_file($src);
            $text =~ s/xcat\.genesis\.\Q$f\E/$f/g;
            write_script($dst, $text, 0755);
        }
    }
    # xCAT-genesis-scripts keeps a control file per architecture.
    if ($pkg eq 'xCAT-genesis-scripts' && $arch ne 'all') {
        my $per_arch = "$dir/debian/control-$arch";
        die "FATAL: $per_arch is missing\n" unless -f $per_arch;
        write_file($control, pin_control_version(read_file($per_arch), $PKGVER));
    }

    my $rc = eval { $body->($dir); 1 } ? 0 : 1;
    my $err = $@;

    unlink @added, @remove;
    restore_file($_) for reverse @restore;
    die $err if $rc;
    return;
}

sub build_package {
    my ($pkg, $arch, $pkgdir) = @_;
    say "Building $pkg ($arch) $PKGVER";

    with_prepared_tree($pkg, $arch, sub {
        my ($dir) = @_;

        # A 3.0 (quilt) source package needs its .orig tarball beside the tree.
        my $format = "$dir/debian/source/format";
        if (-f $format) {
            my $text = read_file($format);
            if ($text =~ /3\.0 \(quilt\)/) {
                my $tar = "$ROOT/" . orig_tarball_name($pkg, $PKGVER);
                unless (-f $tar) {
                    sh(sprintf('tar czf %s --exclude debian -C %s .',
                               sh_quote($tar), sh_quote($dir))) == 0
                        or die "FATAL: could not create $tar\n";
                }
            }
        }

        my $arch_flag = $arch eq 'all' ? '' : " -a$arch";
        my $quiet = $opts{verbose} ? '' : ' >/dev/null';
        sh("cd " . sh_quote($dir) . " && dpkg-buildpackage -rfakeroot -uc -us$arch_flag$quiet") == 0
            or die "FATAL: dpkg-buildpackage failed for $pkg ($arch)\n";
    });

    return;
}

# collect_debs: move a finished package's .deb files out of the checkout root.
#
# This happens once the package's LAST architecture is built, never between them:
# dpkg-genbuildinfo reads the sibling .deb files that the same source package
# produced, so moving amd64 away before ppc64el runs makes the second build die with
#   dpkg-genbuildinfo: error: cannot fstat file ../xcat_..._amd64.deb
sub collect_debs {
    my ($pkg, $pkgdir) = @_;
    my $moved = 0;
    for my $deb (glob("$ROOT/*.deb")) {
        move($deb, "$pkgdir/" . basename($deb))
            or die "Cannot move $deb into $pkgdir: $!\n";
        $moved++;
    }
    die "FATAL: $pkg produced no .deb\n" unless $moved;
    # The rest of the dpkg output is build residue, not an artifact.
    unlink glob("$ROOT/*.buildinfo"), glob("$ROOT/*.changes"), glob("$ROOT/*.dsc"),
           glob("$ROOT/*.tar.xz"), glob("$ROOT/*.tar.gz");
    # And the residue dpkg leaves inside the package -- debian/files survives
    # `dh_clean -d` and would make the next build with a different release fstat
    # artifacts this run already moved away. Safe here: this runs after the last
    # architecture, so no dpkg-genchanges still needs it.
    clean_debian_residue("$ROOT/$pkg");
    return $moved;
}

# ------------------------------------------------------------- apt assembly --
sub gpg_key_id {
    my ($name) = @_;
    my $out = `gpg --list-keys --keyid-format long @{[ sh_quote($name) ]} 2>/dev/null`;
    my ($id) = $out =~ m{^pub\s+\S+/(\S+)}m;
    die "FATAL: no gpg key matching '$name'\n" unless $id;
    return $id;
}

sub assemble_repo {
    my ($pkgdir, $repodir) = @_;
    make_path("$repodir/conf");

    my $keyid;
    if ($opts{gpg_sign}) {
        local $ENV{GNUPGHOME} = $opts{gpg_home} if $opts{gpg_home};
        $keyid = gpg_key_id($opts{gpg_key_name});
    }

    open my $d, '>', "$repodir/conf/distributions" or die "Cannot write conf/distributions: $!\n";
    print {$d} reprepro_distributions($opts{dists}, $keyid);
    close $d;

    open my $o, '>', "$repodir/conf/options" or die "Cannot write conf/options: $!\n";
    print {$o} reprepro_options($opts{gpg_home});
    close $o;

    local $ENV{GNUPGHOME} = $opts{gpg_home} if $opts{gpg_home};
    my @debs = sort glob("$pkgdir/*.deb");
    die "FATAL: no .deb files to publish in $pkgdir\n" unless @debs;

    for my $dist ($opts{dists}->@*) {
        my %ok = map { $_ => 1 } dist_arches($dist);
        for my $deb (@debs) {
            # A release that predates an architecture must not be handed its packages.
            next if basename($deb) =~ /_(\w+)\.deb\z/ && $1 ne 'all' && !$ok{$1};
            sh("cd " . sh_quote($repodir) . " && reprepro -b ./ includedeb "
               . sh_quote($dist) . ' ' . sh_quote($deb)) == 0
                or die "FATAL: reprepro could not add $deb to $dist\n";
        }
    }
    return scalar @debs;
}

sub write_repo_metadata {
    my ($repodir) = @_;

    # Point apt at this directory, for a locally built repo.
    write_script("$repodir/mklocalrepo.sh", <<'SCRIPT');
. /etc/lsb-release
cd `dirname $0`
host_arch=`uname -m`
if [ "$host_arch" != "ppc64le" ];then
    host_arch="amd64"
else
    host_arch="ppc64el"
fi
echo deb [arch=$host_arch] file://"`pwd`" $DISTRIB_CODENAME main > /etc/apt/sources.list.d/xcat-core.list
SCRIPT

    write_file("$repodir/buildinfo", buildinfo_text(
        version => $VERSION, release => $RELEASE, epoch => $EPOCH,
        commit => $GITINFO, time_format => '%a %b %d %H:%M:%S %Y'));
    return;
}

# ----------------------------------------------------------------- main ------
my $lock = take_build_lock($ROOT);

my $dest   = resolve_dest($opts{dest}, "$ROOT/dist/debs");
my $pkgdir = "$dest/debs";
my $repo   = "$dest/xcat-core";
make_path($pkgdir);
remove_tree($repo) if -d $repo && $opts{force};
make_path($repo);

# Clear dpkg output left in the checkout by an earlier run. dpkg-genbuildinfo reads
# the sibling artifacts of the source package it is building, so a stale .changes or
# .buildinfo from an aborted run makes the next build die with
#   dpkg-genbuildinfo: error: cannot fstat file ../<pkg>_<arch>.deb
# naming an architecture this run has not reached yet.
unlink glob("$ROOT/*.deb"), glob("$ROOT/*.buildinfo"), glob("$ROOT/*.changes"),
       glob("$ROOT/*.dsc"), glob("$ROOT/*.tar.xz"), glob("$ROOT/*.orig.tar.gz");

say "xcat-core $PKGVER -> $dest";
say "releases: @{[ join ' ', $opts{dists}->@* ]}";

for my $pkg ($opts{packages}->@*) {
    for my $arch (deb_package_arches($pkg)) {
        build_package($pkg, $arch, $pkgdir);
    }
    collect_debs($pkg, $pkgdir);
}

my $count = assemble_repo($pkgdir, $repo);
write_repo_metadata($repo);
say "published $count package(s) into @{[ scalar $opts{dists}->@* ]} release(s) at $repo";

__END__

=head1 NAME

builddebs.pl - build the xcat-core Debian packages and an apt repository

=head1 SYNOPSIS

  perl builddebs.pl [options]

=head1 DESCRIPTION

Builds every xcat-core Debian package and assembles a C<reprepro> apt repository
containing them.

xcat-core packages are Perl. The same binary serves every Ubuntu release, so each
package is built B<once> and the resulting C<.deb> files are published into every
codename the repository declares. Only C<xCAT>, C<xCATsn> and C<xCAT-genesis-scripts>
carry an architecture, and there the difference is packaging metadata rather than
compiled output. Consequently this builder needs no C<sbuild> and no per-codename
chroot. (xcat-dep is different: its packages are compiled, so it builds per codename.)

Replaces C<build-ubunturepo>. The GSA upload paths, the C<PROMOTE>/C<PREGA> release
flows and the C<-d> xcat-dep repository mode were not carried over: publishing is done
by the CD pipeline's own deploy step, and xcat-dep is built from its own repository.

=head1 OPTIONS

=over

=item B<--dist>=I<CODENAME>

Publish into this release. Repeatable. Defaults to focal, jammy, noble and resolute.

=item B<--package>=I<NAME>

Build only this package. Repeatable. Defaults to every xcat-core deb package.

=item B<--dest>=I<DIR>

Write the build under this directory: packages in C<debs/>, the apt repository in
C<xcat-core/>. Defaults to C<dist/debs> in the checkout.

=item B<--release>=I<STRING>

Override the C<snapYYYYMMDDHHMM> release derived from the commit time.

=item B<--gpg-sign>

Sign the repository. Without it the repository is left unsigned.

=item B<--gpg-home>=I<DIR>

Use this directory as C<GNUPGHOME>. Implies the key has no passphrase, so the build
never stops to prompt.

=item B<--gpg-key-name>=I<NAME>

The key to sign with. Defaults to C<xCAT Signing Key>.

=item B<--force>

Rebuild the repository from scratch rather than adding to what is there.

=item B<--verbose>

Echo each command.

=item B<--help>

This message.

=back

=head1 EXAMPLES

  ./builddebs.pl
  ./builddebs.pl --dist noble --package perl-xCAT
  ./builddebs.pl --dest /srv/out --gpg-sign --gpg-home /keys/xcat-gpg-home

=cut
