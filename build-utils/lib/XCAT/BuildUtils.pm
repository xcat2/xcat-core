package XCAT::BuildUtils;
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
    sh sh_or_die usage
    rewrite_file write_script read_line
    buildinfo_text
    targetarch_from_target
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
# The pid of the command sh() is running, so a cancellation handler can stop it before the
# build lock is released. system() gives no pid, which is why this forks explicitly.
our $CURRENT_CHILD;

# Locks this process holds, weakly. Released by a signal handler or at exit, because
# _BuildLock::DESTROY does not run when a signal ends the process.
our @LIVE_LOCKS;
END { release_build_locks() }

sub sh {
    my ($cmd) = @_;
    require POSIX;
    say "Running: $cmd" if $VERBOSE;

    # Do not let cancellation run between fork and publishing the process group.
    my $blocked = POSIX::SigSet->new(POSIX::SIGINT(), POSIX::SIGTERM());
    my $oldmask = POSIX::SigSet->new();
    POSIX::sigprocmask(POSIX::SIG_BLOCK(), $blocked, $oldmask)
        or die "Cannot block build cancellation signals: $!\n";

    my $pid = fork();
    unless (defined $pid) {
        my $error = "$!";
        POSIX::sigprocmask(POSIX::SIG_SETMASK(), $oldmask)
            or POSIX::_exit(127);
        warn "FATAL: cannot fork to run $cmd: $error\n";
        return 127;
    }
    unless ($pid) {
        $SIG{INT} = $SIG{TERM} = 'DEFAULT';
        POSIX::setpgid(0, 0) or POSIX::_exit(127);
        POSIX::sigprocmask(POSIX::SIG_SETMASK(), $oldmask)
            or POSIX::_exit(127);
        exec('/bin/sh', '-c', $cmd) or POSIX::_exit(127);
    }

    local $CURRENT_CHILD = $pid;  # also the command's process-group ID
    # Both sides set the group, so neither depends on which side runs first.
    # EACCES means the child already exec'd, after setting its group; ESRCH
    # means it has already gone away.
    unless (POSIX::setpgid($pid, $pid) || $!{EACCES} || $!{ESRCH}) {
        warn "FATAL: cannot create build process group $pid: $!; retaining locks\n";
        kill 'KILL', $pid;
        POSIX::_exit(127);
    }
    POSIX::sigprocmask(POSIX::SIG_SETMASK(), $oldmask) or do {
        warn "FATAL: cannot restore signal mask: $!\n";
        cancel_build('TERM');
        POSIX::_exit(127);
    };

    my $got;
    do { $got = waitpid($pid, 0) } while ($got == -1 && $!{EINTR});
    my $status = $?;
    return 127 if $got == -1;
    return ($status & 127) ? 128 + ($status & 127) : $status >> 8;
}

# pod2usage reads the POD of the running program, so each builder keeps its own
# help text while sharing the way it is printed and the status it exits with.
# Run a command and stop the build when it fails.  The same operation was
# spelled in opposite polarities -- `sh(...) == 0 or die` in builddebs.pl,
# `sh(...) and die` in buildrpms.pl, which also used both -- and the `and die`
# form reads as though the die is what happens next rather than what happens on
# failure.  One name, one direction, and the exit code lands in the message.
sub sh_or_die {
    my ($cmd, $message) = @_;
    my $rc = sh($cmd);
    return 0 if $rc == 0;
    $message = "FATAL: command failed: $cmd" unless defined $message;
    $message =~ s/\n\z//;
    die "$message (exit $rc)\n";
}

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
    CommandUtils.pm
    GlobalDef.pm
    NetworkUtils.pm
    ServiceNodeUtils.pm
);

# Packages whose .deb carries a real architecture, and the architectures each is built
# for. Everything else in xcat-core is Perl and ships as Architecture: all -- one binary
# serving every Ubuntu release and every arch, which is why this build never needs a
# per-codename chroot. xCAT-genesis-scripts has no riscv64 control file: riscv64 Genesis
# ships as an OpenEmbedded package.
my %ARCH_PACKAGES = (
    'xCAT'                 => [qw(amd64 ppc64el riscv64)],
    'xCATsn'               => [qw(amd64 ppc64el riscv64)],
    'xCAT-genesis-scripts' => [qw(amd64 ppc64el)],
);

# Ubuntu releases predating ppc64el. Kept as data rather than an `if` in the caller so
# the repo-assembly and the package-selection paths cannot disagree about it.
my %NO_PPC64EL = map { $_ => 1 } qw(saucy);

my @DEB_ARCHES = qw(amd64 ppc64el riscv64);

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
    my $arches = $ARCH_PACKAGES{ $package // '' };
    return $arches ? @{$arches} : ('all');
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
    require POSIX;
    # A directory, not an flock. A build tree can live on an NFS re-export, where the kernel
    # refuses locks outright: every attempt answers errno 524. mkdir(2) is arbitrated by the
    # server and needs no lock daemon.
    my $lockdir = lock_path_for($path, $dir) . '.d';
    unless (mkdir $lockdir) {
        die "FATAL: cannot take $lockdir: $!\n" unless $! == POSIX::EEXIST();
        my $who = ''; if (open(my $h, '<', "$lockdir/owner")) { local $/; $who = <$h> // ''; close $h }
        chomp $who;
        die "FATAL: another build of $path already holds $lockdir"
          . ($who ? " (held by [$who])" : "") . "\n";
    }
    if (open(my $ow, '>', "$lockdir/owner")) { print {$ow} "pid=$$\n"; close $ow }
    # The caller keeps the returned value; release is by pid so a fork cannot free the parent's.
    my $owner = $$;
    my $lock = XCAT::BuildUtils::_BuildLock->new($lockdir, $owner);
    # Registered weakly, so holding it here does not keep the lock alive past its caller's
    # scope. The registry exists only so a signal can release what DESTROY will not.
    require Scalar::Util;
    push @LIVE_LOCKS, $lock;
    Scalar::Util::weaken($LIVE_LOCKS[-1]);
    return $lock;
}

#-------------------------------------------------------------------------------

=head3 release_build_locks

Descriptions:
    Release every build lock this process still holds.

    DESTROY does not run when a signal terminates the process, so a cancelled build left its
    lock directory behind and the next build of that checkout died on "another build already
    holds" naming a pid that had long exited. One such directory blocked an openSUSE target
    across three consecutive runs before anyone looked.

Arguments:
    None.
Returns:
    Nothing.

=cut

#-------------------------------------------------------------------------------
sub release_build_locks {
    for my $l (@LIVE_LOCKS) { $l->release if defined $l }
    return;
}

#-------------------------------------------------------------------------------

=head3 install_build_cancellation

Descriptions:
    Install the INT and TERM handlers that stop the build and release its locks.

    It lives here rather than in the builder so the behaviour can be tested. A builder that
    wired its own handler inline could only be covered by reading its source, and a test that
    installs an equivalent handler of its own proves the helper works while saying nothing
    about whether anything calls it.

    The signal is re-raised with the default disposition afterwards, so the exit status still
    tells a caller the build was cancelled rather than that it failed.

Arguments:
    $announce - optional coderef called with the signal name before the build is stopped
Returns:
    Nothing.

=cut

#-------------------------------------------------------------------------------
sub install_build_cancellation {
    my ($announce) = @_;
    for my $sig (qw(INT TERM)) {
        $SIG{$sig} = sub {
            my ($caught) = @_;
            $announce->($caught) if $announce;
            cancel_build($caught);
            $SIG{$caught} = 'DEFAULT';
            kill $caught => $$;
        };
    }
    return;
}

#-------------------------------------------------------------------------------

=head3 cancel_build

Descriptions:
    Stop the command in flight, then release the build locks.

    The order matters. Releasing first would hand the checkout to a second build while
    dpkg-buildpackage is still rewriting debian/changelog and debian/control in it.

    The wait is bounded: a child that ignores the signal must not keep the lock for ever, so
    it is given a few seconds and then killed outright.

Arguments:
    $sig - the signal name that started the cancellation
Returns:
    Nothing.

=cut

#-------------------------------------------------------------------------------
sub cancel_build {
    my ($sig) = @_;
    require POSIX;
    # A second Ctrl-C must not interrupt cleanup and release the lock early.
    local $SIG{INT}  = 'IGNORE';
    local $SIG{TERM} = 'IGNORE';

    if (my $pgid = $CURRENT_CHILD) {
        my $reaped = 0;
        for my $stop_signal ($sig, 'KILL') {
            kill $stop_signal, -$pgid;
            for (1 .. 50) {
                unless ($reaped) {
                    my $got = waitpid($pgid, POSIX::WNOHANG());
                    $reaped = 1 if $got == $pgid || ($got == -1 && $!{ECHILD});
                }
                # The shell exiting is not enough: its workers may still exist.
                if (!kill(0, -$pgid) && $!{ESRCH}) {
                    $CURRENT_CHILD = undef;
                    release_build_locks();
                    return;
                }
                select undef, undef, undef, 0.1;
            }
        }
        # Never let END/DESTROY unlock a checkout whose workers may still run.
        warn "FATAL: build process group $pgid has not disappeared; retaining locks\n";
        POSIX::_exit(1);
    }
    release_build_locks();
    return;
}

{   package XCAT::BuildUtils::_BuildLock;
    sub new { my ($c,$d,$p)=@_; return bless { dir=>$d, pid=>$p, released=>0 }, $c }
    # Idempotent: a signal handler and then DESTROY both reach here, and the second must not
    # remove a directory a LATER build has since taken.
    sub release {
        my $s = shift;
        return if $s->{released};
        $s->{released} = 1;
        return unless $$ == $s->{pid};
        unlink "$s->{dir}/owner";
        rmdir $s->{dir};
        return;
    }
    sub DESTROY { shift->release }
}

# The rpm architecture a mock target builds for. A target carries the arch as its
# last meaningful token (alma+epel-10-ppc64le), and a suffixed target keeps it in
# the middle (rocky-10-riscv64-xcat), so the token is found from the right.
sub targetarch_from_target {
    my ( $target, $default_arch ) = @_;
    return $default_arch unless defined($target) && length($target);

    my @parts = map {
        my $part = lc($_);
        $part =~ s/^\s+|\s+$//g;
        $part;
    } split /-/, $target;

    for my $part (reverse @parts) {
        return $part
          if $part =~ /^(?:x86_64|i[3-6]86|ppc64le|ppc64|aarch64|riscv64|s390x|armv7hl)$/;
    }
    return $parts[-1];
}

1;
