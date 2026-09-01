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
    orig_tarball_name pin_control_version rewrite_changelog_header
    reprepro_distributions reprepro_options
    lock_id_for take_build_lock sh_quote
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

$opts{packages} = @cli_packages ? \@cli_packages : \@PACKAGES;
$opts{dists}    = @cli_dists    ? \@cli_dists    : \@DISTS;
$opts{gpg_key_name} //= 'xCAT Signing Key';

for my $pkg ($opts{packages}->@*) {
    die "FATAL: unknown package '$pkg'. Known: @PACKAGES\n"
        unless grep { $_ eq $pkg } @PACKAGES;
}

sub usage {
    my (%args) = @_;
    pod2usage(
        -verbose => $args{verbose} // 1,
        -exitval => $args{exitval} // 2,
        (defined $args{message} ? (-message => "$args{message}\n") : ()),
    );
}

sub sh {
    my ($cmd) = @_;
    say "+ $cmd" if $opts{verbose};
    return system($cmd);
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

    my $save = sub {
        my ($rel) = @_;
        my $path = "$dir/$rel";
        return unless -f $path;
        my $backup = "$path.build.save";
        copy($path, $backup) or die "Cannot back up $path: $!\n";
        push @restore, [$backup, $path];
    };

    $save->('debian/control');
    $save->('debian/changelog');

    # Pin the intra-xCAT dependencies to this exact build, so a partial upgrade cannot
    # mix versions.
    my $control = "$dir/debian/control";
    if (-f $control) {
        my $text = do { open my $fh, '<', $control or die; local $/; <$fh> };
        open my $out, '>', $control or die "Cannot write $control: $!\n";
        print {$out} pin_control_version($text, $PKGVER);
        close $out;
    }

    my $changelog = "$dir/debian/changelog";
    if (-f $changelog) {
        my $text = do { open my $fh, '<', $changelog or die; local $/; <$fh> };
        open my $out, '>', $changelog or die "Cannot write $changelog: $!\n";
        print {$out} rewrite_changelog_header($text, $PKGVER, $DEB_DATE, $MAINTAINER);
        close $out;
    }
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
            my $text = do { open my $fh, '<', $src or die; local $/; <$fh> };
            $text =~ s/xcat\.genesis\.\Q$f\E/$f/g;
            open my $out, '>', $dst or die "Cannot write $dst: $!\n";
            print {$out} $text;
            close $out;
            chmod 0755, $dst;
            push @added, $dst;
        }
    }
    # xCAT-genesis-scripts keeps a control file per architecture.
    if ($pkg eq 'xCAT-genesis-scripts' && $arch ne 'all') {
        my $per_arch = "$dir/debian/control-$arch";
        die "FATAL: $per_arch is missing\n" unless -f $per_arch;
        my $text = do { open my $fh, '<', $per_arch or die; local $/; <$fh> };
        open my $out, '>', $control or die "Cannot write $control: $!\n";
        print {$out} pin_control_version($text, $PKGVER);
        close $out;
    }

    my $rc = eval { $body->($dir); 1 } ? 0 : 1;
    my $err = $@;

    unlink @added;
    for my $pair (reverse @restore) {
        my ($backup, $path) = @$pair;
        move($backup, $path) or warn "Could not restore $path: $!\n";
    }
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
            my $text = do { open my $fh, '<', $format or die; local $/; <$fh> };
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
    open my $m, '>', "$repodir/mklocalrepo.sh" or die "Cannot write mklocalrepo.sh: $!\n";
    print {$m} <<'SCRIPT';
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
    close $m;
    chmod 0775, "$repodir/mklocalrepo.sh";

    my $commit = `git -C @{[ sh_quote($ROOT) ]} rev-parse HEAD 2>/dev/null` || 'unknown';
    chomp $commit;
    my $host = `hostname 2>/dev/null` || 'unknown'; chomp $host;
    open my $b, '>', "$repodir/buildinfo" or die "Cannot write buildinfo: $!\n";
    print {$b} "VERSION=$VERSION\n",
               "RELEASE=$RELEASE\n",
               "BUILD_TIME=@{[ strftime('%a %b %d %H:%M:%S %Y', gmtime($EPOCH)) ]}\n",
               "BUILD_MACHINE=$host\n",
               "COMMIT_ID=@{[ substr($commit, 0, 7) ]}\n",
               "COMMIT_ID_LONG=$commit\n";
    close $b;
    return;
}

# ----------------------------------------------------------------- main ------
my $lock = take_build_lock($ROOT);

my $dest   = $opts{dest} ? abs_path($opts{dest}) : "$ROOT/dist/debs";
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
