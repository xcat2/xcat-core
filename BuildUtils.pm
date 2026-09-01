package BuildUtils;
# Reusable, unit-testable helpers shared by the xcat-core build tooling: buildrpms.pl
# (rpm/mock) and builddebs.pl (deb/reprepro). Both derive the same Version-Release from
# the same git state, stage the same xCAT-probe helpers, and shell out the same way, so
# that logic lives here once instead of twice.
#
# Everything here is a pure function of its arguments, or a thin wrapper whose side
# effect is the argument. Nothing reaches for an orchestrator global, so
# xCAT-test/unit/build_utils.t drives every function directly rather than grepping the
# builders for evidence that they call it.
#
# It mirrors xcat-dep's BuildUtils.pm in shape and intent; the two repos ship separate
# copies because neither installs the other's tooling.
use strict;
use warnings;
use Exporter 'import';
use File::Copy qw(copy move);
use File::Basename qw(basename);
use File::Path qw(make_path remove_tree);
use File::Slurper qw(read_text write_text);
use POSIX qw(strftime);
use Pod::Usage qw(pod2usage);
use feature 'say';

our @EXPORT_OK = qw(
    source_date_epoch snap_release deb_version
    stage_probe_helpers XCAT_PROBE_HELPERS
    deb_package_arches dist_arches default_dists
    orig_tarball_name upstream_version resolve_dest
    pin_control_version rewrite_changelog_header
    reprepro_distributions reprepro_options
    lock_id_for take_build_lock
    sh_quote clean_debian_residue git_revision
    backup_file restore_file
    sh usage
    rewrite_file write_script read_line
    buildinfo_text
);

# Both builders echo the commands they run under --verbose.  Set once, after
# option parsing, rather than threaded through every sh() call site.
our $VERBOSE = 0;

# The xCAT-probe helpers. xcat-probe reuses functions shipped by xCAT; they are COPIED
# rather than symlinked because a symlink does not survive packaging, and rather than
# maintained twice because they would drift. Both builders stage them the same way.
# The stamp both builders write beside a published repository. deploy.sh copies
# the file verbatim and cluster-test.pl parses it, so the field names and their
# order are a contract; each builder passes its own time format and writes to
# its own filename, which are part of that contract too.
sub buildinfo_text {
    my (%args) = @_;
    my $commit = $args{commit} // 'unknown';
    my $host   = $args{host};
    unless (defined $host) {
        $host = `hostname 2>/dev/null` || 'unknown';
        chomp $host;
    }
    return join('', map { "$_\n" }
        "VERSION=$args{version}",
        "RELEASE=$args{release}",
        "BUILD_TIME=" . strftime($args{time_format}, gmtime($args{epoch})),
        "BUILD_MACHINE=$host",
        "COMMIT_ID=" . substr($commit, 0, 7),
        "COMMIT_ID_LONG=$commit");
}

# Write a helper script and make it executable.  Both builders ship a
# mklocalrepo.sh beside the packages they publish, and builddebs.pl installs the
# genesis postscripts the same way; a script written without the executable bit
# is shipped broken, so the mode is not left to the caller to remember.  It
# still varies -- the published repo helper is group-writable, the postscripts
# are not -- so the caller may say, and 0775 is only the default.
sub write_script {
    my ($path, $content, $mode) = @_;
    $mode = 0775 unless defined $mode;
    write_text($path, $content);
    chmod $mode, $path or die "Cannot chmod $path: $!\n";
    return;
}

# The first line of a file, without its newline.  Version and Release are
# one-line stamps that both builders read, and each spelled the open, the read
# and the chomp differently -- buildrpms.pl chomped ten lines away from its
# read, which is how a stamp keeps a trailing newline nobody notices until it
# lands in a package name.  Returns undef when the file is absent, which is
# what a caller with a fallback wants.
sub read_line {
    my ($path) = @_;
    return undef unless -f $path;
    my ($line) = split /\n/, read_text($path), 2;
    return undef unless defined $line && length $line;
    return $line;
}

# Read a file, pass its contents through $transform, write the result back.
# A file that is not there is left alone, which is what every caller wanted.
sub rewrite_file {
    my ($path, $transform) = @_;
    return 0 unless -f $path;
    write_text($path, $transform->(read_text($path)));
    return 1;
}

# Run a shell command, returning its EXIT STATUS.  system() yields the raw wait
# status, which is the exit code times 256, so it is shifted here: a caller
# comparing the result against a specific code gets the code it expects, not a
# multiple of it.
sub sh {
    my ($cmd) = @_;
    say "Running: $cmd" if $VERBOSE;
    system($cmd);
    return $? >> 8;
}

# pod2usage reads the POD of the running program, so each builder keeps its own
# help text while sharing the way it is printed and the status it exits with.
sub usage {
    my (%args) = @_;
    pod2usage(
        -verbose => $args{verbose} // 1,
        -exitval => $args{exitval} // 2,
        (defined($args{message}) && length($args{message})
            ? (-message => "$args{message}\n") : ()),
    );
}

use constant XCAT_PROBE_HELPERS => qw(
    GlobalDef.pm
    NetworkUtils.pm
    ServiceNodeUtils.pm
);

# Packages whose .deb carries a real architecture. Everything else in xcat-core is
# Perl and ships as Architecture: all -- one binary serving every Ubuntu release and
# every arch, which is why this build never needs a per-codename chroot.
my %ARCH_PACKAGES = map { $_ => 1 } qw(xCAT xCATsn xCAT-genesis-scripts);

# Ubuntu releases predating ppc64el. Kept as data rather than an `if` in the caller so
# the repo-assembly and the package-selection paths cannot disagree about it.
my %NO_PPC64EL = map { $_ => 1 } qw(saucy);

my @DEB_ARCHES = qw(amd64 ppc64el);

# The Ubuntu releases the apt repository serves by default. Single source of truth:
# the builder, the repo assembly and the tests all read it here, so they cannot drift.
my @DEFAULT_DISTS = qw(focal jammy noble resolute);

sub default_dists { return @DEFAULT_DISTS; }

# sh_quote: single-quote a string for safe use in a shell command.
# clean_debian_residue: remove what dpkg-buildpackage leaves inside a package's
# debian/ directory.
#
# debian/files accumulates one line per artifact and is never truncated by
# `dh_clean -d`, which only removes directories. dpkg-genchanges then reads the
# stale entries on the next build and fstats artifacts that are no longer there:
#   dpkg-genchanges: error: cannot fstat file ../perl-xcat_<old release>_amd64.buildinfo
# so a second build in the same checkout dies as soon as the release string moves.
# The staging directories go for the same reason the old shell builder removed
# them -- they are the previous build's payload, not source.
#
# Call this only after a package's LAST architecture: debian/files carries the
# amd64 artifacts that the ppc64el run's dpkg-genchanges still needs.
# backup_file / restore_file: put a file back exactly as it was.
#
# File::Copy::copy does NOT carry permissions, so a naive backup-and-restore returns
# an executable with its exec bit stripped -- the content compares equal and only
# `git diff` notices the mode change. xCAT/postscripts/{bmcsetup,getipmi} are shipped
# executable and are rewritten during the xCAT build, so this is not hypothetical.
# git_revision: the commit the packages are built from.
#
# This is not cosmetic. perl-xCAT/debian/rules and perl-xCAT.spec both pass it to
# modifyUtils, which substitutes it and the version into xCAT::Version. Hand
# modifyUtils an empty string and it does nothing, and the built package reports no
# version at all -- `lsxcatd -v` prints a bare "Version". So a revision is always
# produced: the git checkout when there is one, an existing Gitinfo when there is
# not (a source export carries the real revision that way, and clobbering it with
# a placeholder would throw away the only provenance the tree has), and only then
# the "unknown" placeholder.
sub git_revision {
    my (%args) = @_;
    my $run       = $args{git}       || sub { `git rev-parse HEAD 2>/dev/null` };
    my $read_file = $args{read_file} || sub {
        return unless -f 'Gitinfo';
        return scalar read_text('Gitinfo');
    };

    for my $source ($run, $read_file) {
        my $rev = $source->();
        next unless defined $rev;
        $rev =~ s/\s+\z//;
        return $rev if length $rev;
    }
    return 'unknown';
}

sub backup_file {
    my ($path) = @_;
    return unless defined $path && -f $path;
    my $backup = "$path.build.save";
    my $mode   = ( stat $path )[2] & 07777;
    copy( $path, $backup ) or die "Cannot back up $path: $!\n";
    return [ $backup, $path, $mode ];
}

sub restore_file {
    my ($entry) = @_;
    return 0 unless $entry;
    my ( $backup, $path, $mode ) = @{$entry};
    move( $backup, $path ) or do { warn "Could not restore $path: $!\n"; return 0; };
    chmod $mode, $path if defined $mode;
    return 1;
}

sub clean_debian_residue {
    my ($package_root) = @_;
    return () unless defined $package_root && -d "$package_root/debian";

    my @removed;
    my $files = "$package_root/debian/files";
    if (-e $files) {
        unlink $files or die "Cannot remove $files: $!\n";
        push @removed, $files;
    }

    my $stem = lc(basename($package_root));
    foreach my $dir (glob("$package_root/debian/$stem*")) {
        next unless -d $dir;
        remove_tree($dir);
        push @removed, $dir;
    }

    # debhelper's own bookkeeping. Never tracked, and it accumulates per build.
    # glob returns a wildcard-free pattern verbatim whether or not it exists, so
    # the -e guard is what makes a second call a no-op rather than a fatal unlink.
    foreach my $residue (glob("$package_root/debian/*.debhelper.log"),
                         "$package_root/debian/.debhelper") {
        next unless -e $residue;
        if (-d $residue) { remove_tree($residue); }
        else { unlink $residue or die "Cannot remove $residue: $!\n"; }
        push @removed, $residue;
    }

    return @removed;
}

sub sh_quote {
    my ($s) = @_;
    $s = '' if !defined $s;
    $s =~ s/'/'"'"'/g;
    return "'$s'";
}

# source_date_epoch: the commit time the build is reproducible against.
#
# Gitepoch wins when present -- CI writes it so every arch of one release stamps an
# identical epoch even when the arches build minutes apart. Falling back to the local
# clock is last-resort: it makes the build non-reproducible, so the caller is told.
sub source_date_epoch {
    my (%args) = @_;
    my $read = $args{read_file} || sub {
        my ($p) = @_;
        return unless -f $p;
        return scalar read_text($p);
    };
    my $git = $args{git_epoch} || sub { return scalar `git log -1 --format=%ct HEAD 2>/dev/null`; };

    for my $candidate ($read->('Gitepoch'), $git->()) {
        next unless defined $candidate;
        chomp $candidate;
        return $candidate if $candidate =~ /\A\d+\z/;
    }
    return $args{now} || time();
}

# snap_release: the Release string, derived from the commit time so identical sources
# give identical NVRs. UTC, because a build host's timezone must not change the name.
sub snap_release {
    my ($epoch) = @_;
    return strftime("snap%Y%m%d%H%M", gmtime($epoch));
}

# deb_version: the Debian version. Same Version-Release pair the rpms carry, so an
# apt repo and a yum repo built from one commit report the same thing.
sub deb_version {
    my ($version, $release) = @_;
    return "$version-$release";
}

# stage_probe_helpers: copy the shared helpers into xCAT-probe's tree.
# Returns the list of destination paths, so a caller can remove exactly what it added.
sub stage_probe_helpers {
    my ($source_dir, $dest_dir) = @_;
    make_path($dest_dir) unless -d $dest_dir;
    my @staged;
    for my $helper (XCAT_PROBE_HELPERS) {
        my $from = "$source_dir/$helper";
        my $to   = "$dest_dir/$helper";
        copy($from, $to) or die "Unable to stage $from into $dest_dir: $!\n";
        push @staged, $to;
    }
    return @staged;
}

# deb_package_arches: the architectures to build a package for.
# 'all' is a single arch-independent build; the three arch packages get one per arch.
sub deb_package_arches {
    my ($package) = @_;
    return @DEB_ARCHES if $ARCH_PACKAGES{$package // ''};
    return ('all');
}

# dist_arches: the architectures a release's apt repo declares.
sub dist_arches {
    my ($dist) = @_;
    return ('amd64') if $NO_PPC64EL{$dist // ''};
    return @DEB_ARCHES;
}

# orig_tarball_name: the .orig.tar.gz dpkg-source expects for a 3.0 (quilt) package.
#
# The name carries the UPSTREAM version only -- dpkg looks for
# <source>_<upstream>.orig.tar.gz, with no Debian revision, because one upstream
# tarball is shared by every revision built from it. The revision is stripped here
# rather than at the call site so passing the full Version-Release cannot produce a
# tarball dpkg will not find. Lower-cased because dpkg requires a lower-case source
# package name.
sub upstream_version {
    my ($version) = @_;
    return '' unless defined $version;
    $version =~ s/-[^-]*\z//;    # drop the Debian revision, if any
    return $version;
}

sub orig_tarball_name {
    my ($package, $version) = @_;
    return lc($package) . '_' . upstream_version($version) . '.orig.tar.gz';
}

# resolve_dest: turn a --dest argument into an absolute path.
#
# NOT Cwd::abs_path: that returns undef when a PARENT component is missing, and the
# caller then interpolates undef, so `--dest /no/such/parent/out` silently becomes
# `/debs` and `/xcat-core` at the filesystem root. rel2abs is purely lexical and
# works for a path that does not exist yet, which is the normal case for an output
# directory.
sub resolve_dest {
    my ($dest, $default) = @_;
    return $default unless defined $dest && length $dest;
    require File::Spec;
    return File::Spec->rel2abs($dest);
}

# pin_control_version: pin xCAT's inter-package dependencies to this exact build.
#
# debian/control carries the sentinel ">= 2.13-snap000000000000" on every intra-xCAT
# dependency. Left alone, apt would satisfy them with any older xCAT already installed,
# so a partial upgrade could mix versions. Replacing it with "= <version>" makes the set
# install or fail as a unit.
sub pin_control_version {
    my ($control, $version) = @_;
    return $control unless defined $control;
    $control =~ s/>= \Q2.13-snap000000000000\E/= $version/g;
    return $control;
}

# rewrite_changelog_header: set the version and the trailer date of the top stanza.
#
# The date comes from SOURCE_DATE_EPOCH rather than "now" so two builds of one commit
# produce byte-identical packages. Only the first stanza is touched -- the history below
# it is not ours to rewrite.
sub rewrite_changelog_header {
    my ($changelog, $version, $date, $maintainer) = @_;
    return $changelog unless defined $changelog;
    $changelog =~ s/\A(\S+) \([^)]*\)/$1 ($version)/;
    $changelog =~ s/^ -- .*$/ -- $maintainer  $date/m;
    return $changelog;
}

# reprepro_distributions: the conf/distributions body for the whole repo.
#
# One stanza per release, all listing the same packages: xcat-core debs are Perl and are
# byte-identical across releases, so the build produces them once and every codename
# serves the same files. keyid is undef for an unsigned repo.
sub reprepro_distributions {
    my ($dists, $keyid) = @_;
    my $out = '';
    for my $dist (@$dists) {
        my $arches = join ' ', dist_arches($dist);
        $out .= <<"STANZA";
Origin: xCAT internal repository
Label: xcat-core bazaar repository
Codename: $dist
Architectures: $arches
Components: main
Description: Repository automatically genereted conf
STANZA
        $out .= "SignWith: $keyid\n" if defined $keyid && length $keyid;
        $out .= "\n";
    }
    return $out;
}

# reprepro_options: the conf/options body.
#
# ask-passphrase is omitted when a GNUPGHOME is supplied, because that key is
# passphrase-less and an unattended build must never stop to prompt.
sub reprepro_options {
    my ($gpg_home) = @_;
    my $out = "verbose\n";
    $out .= "ask-passphrase\n" unless defined $gpg_home && length $gpg_home;
    $out .= "basedir .\n";
    return $out;
}


# lock_id_for: a short, stable id for a checkout path.
#
# The build rewrites debian/changelog and debian/control and runs dpkg-buildpackage
# inside the package directories, so what two builds contend for is the CHECKOUT, not
# the host. A host-global lock made the devel and stable CD lanes collide even though
# they share nothing. Keying on the path lets distinct checkouts build in parallel while
# two builds of one checkout still fail fast.
sub lock_id_for {
    my ($path) = @_;
    require Digest::MD5;
    return substr(Digest::MD5::md5_hex(defined $path ? $path : ''), 0, 12);
}

# lock_path_for: where that checkout's lock lives.
# Local /var/lock deliberately: the checkout itself may be on NFS, where flock is not
# reliable.
sub lock_path_for {
    my ($path, $dir) = @_;
    $dir = '/var/lock' unless defined $dir;
    return "$dir/xcatbld-" . lock_id_for($path) . ".lock";
}

# take_build_lock: take the checkout's lock, or die.
# Returns the open handle -- the lock is held for as long as the caller keeps it.
sub take_build_lock {
    my ($path, $dir) = @_;
    require Fcntl;
    my $lockfile = lock_path_for($path, $dir);
    open my $fh, '>', $lockfile or die "FATAL: cannot open $lockfile: $!\n";
    flock($fh, Fcntl::LOCK_EX() | Fcntl::LOCK_NB())
        or die "FATAL: another build of $path already holds $lockfile\n";
    return $fh;
}

1;
