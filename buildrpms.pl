#!/usr/bin/perl

use strict;
use warnings;

use feature 'say';

sub install_deps {
    system(<<"EOF");
    set -x
    source /etc/os-release
    case "\$ID" in
        rhel)
            subscription-manager repos --enable codeready-builder-for-rhel-10-\$(arch)-rpms
            ;;
        *)
            dnf config-manager --set-enabled crb
            ;;
    esac
    dnf install -y perl-generators https://dl.fedoraproject.org/pub/epel/epel-release-latest-10.noarch.rpm
    dnf install -y \$(/usr/lib/rpm/perl.req $0)
    dnf install -y tar mock nginx createrepo podman rpmdevtools rpm-sign

    systemctl enable --now nginx

    rpmdev-setuptree
EOF
    $? >> 8;
}

BEGIN {

    exit(install_deps())
        if grep { "--install_deps" eq $_ } @ARGV;
}

use Carp;
use Cwd qw();
use Data::Dumper;
use File::Copy qw(cp);
use File::Path qw(make_path remove_tree);
use File::Slurper qw(read_text write_text);
use FindBin qw($Bin);
use Getopt::Long qw(GetOptions);
use POSIX qw(strftime);
use Parallel::ForkManager;
use Pod::Usage qw(pod2usage);

use autodie;
use autodie qw(cp);

my $SOURCES = "$ENV{HOME}/rpmbuild/SOURCES";
my $VERSION = read_text("Version");
my $PWD = Cwd::cwd();

chomp($VERSION);

# Gitinfo is regenerated at each run with the current git revision.
my $GITINFO = `git rev-parse HEAD 2>/dev/null`;
chomp($GITINFO);
$GITINFO = "unknown" unless $GITINFO;
write_text("Gitinfo", "$GITINFO\n");

my $SOURCE_DATE_EPOCH;
if (-f "Gitepoch") {
    $SOURCE_DATE_EPOCH = read_text("Gitepoch");
    chomp($SOURCE_DATE_EPOCH);
}
unless ($SOURCE_DATE_EPOCH && $SOURCE_DATE_EPOCH =~ /^\d+$/) {
    $SOURCE_DATE_EPOCH = `git log -1 --format=%ct HEAD 2>/dev/null`;
    chomp($SOURCE_DATE_EPOCH);
}
$SOURCE_DATE_EPOCH = time() unless $SOURCE_DATE_EPOCH =~ /^\d+$/;
$ENV{SOURCE_DATE_EPOCH} = $SOURCE_DATE_EPOCH;

sub os_release {
    my %os;
    open my $fh, '<', '/etc/os-release' or die "Cannot open /etc/os-release: $!";

    while (<$fh>) {
        chomp;
        next if /^\s*#/ || !/=/;
        my ($k, $v) = split /=/, $_, 2;
        $v =~ s/^["'](.*)["']$/$1/;  # strip surrounding quotes
        $os{$k} = $v;
    }

    return %os;   # usage: my %os = os_release();
}

sub arch {
    my $arch = `uname -m`;
    chomp $arch;
    return $arch;
}

my $ARCH = arch();
my %OS = os_release();
my $DISTRO = $OS{ID};
# mock's EPEL-enabled AlmaLinux templates are named alma+epel-*, there is no
# almalinux+epel-* config, so translate the os-release ID accordingly.
$DISTRO = "alma" if $DISTRO eq "almalinux";

my @PACKAGES = qw(
    perl-xCAT
    xCAT
    xCATsn
    xCAT-buildkit
    xCAT-client
    xCAT-confluent
    xCAT-genesis-base
    xCAT-genesis-scripts
    xCAT-openbmc-py
    xCAT-probe
    xCAT-rmc
    xCAT-server
    xCAT-test
    xCAT-vlan
);

my @TARGETS = (
    "$DISTRO+epel-8-$ARCH",
    "$DISTRO+epel-9-$ARCH",
    "$DISTRO+epel-10-$ARCH",
);


my %opts = (
    configure_nginx => 0,
    force => 0,
    gpg_home => "",
    gpg_key_name => "xCAT Automatic Signing Key",
    gpg_sign => 0,
    help => 0,
    mock_uniqueext => "",
    nginx_port => 8080,
    nproc => int(`nproc --all`),
    packages => \@PACKAGES,
    release => "",
    repo_mode => "file",
    targets => \@TARGETS,
    verbose => 0,
    xcat_dep_path => "$PWD/../xcat-dep/",
);

GetOptions(
    "configure_nginx" => \$opts{configure_nginx},
    "force" => \$opts{force},
    "gpg-home=s" => \$opts{gpg_home},
    "gpg-key-name=s" => \$opts{gpg_key_name},
    "gpg-sign" => \$opts{gpg_sign},
    "help" => \$opts{help},
    "mock-uniqueext=s" => \$opts{mock_uniqueext},
    "nginx_port" => \$opts{nginx_port},
    "nproc=i" => \$opts{nproc},
    "package=s@" => \$opts{packages},
    "release=s" => \$opts{release},
    "repo-mode=s" => \$opts{repo_mode},
    "target=s@" => \$opts{targets},
    "verbose" => \$opts{verbose},
    "xcat_dep_path=s" => \$opts{xcat_dep_path},
    "setup_local_repos" => \$opts{setup_local_repos},
) or usage();

# Release is regenerated at each run so every build gets a fresh snapshot
# release, unless pinned with --release (e.g. to rebuild a single package
# matching the release the rest of the repo was built with).
my $RELEASE = $opts{release} || strftime("snap%Y%m%d%H%M", localtime);
write_text("Release", "$RELEASE\n");

sub usage {
    my (%args) = @_;
    my $verbose = $args{verbose} // 1;
    my $exitval = $args{exitval} // 2;
    my $message = $args{message};
    pod2usage(
        -verbose => $verbose,
        -exitval => $exitval,
        (defined($message) && length($message) ? (-message => "$message\n") : ()),
    );
}

sub sh {
    my ($cmd) = @_;
    say "Running: $cmd"
        if $opts{verbose};
    system($cmd);
    $? >> 8;
}

# sed { s/foo/bar/ } $filepath applies s/foo/bar/ to the file at $filepath
sub sed (&$) {
    my ($block, $path) = @_;
    my $content = read_text($path);
    local $_ = $content;
    $block->();
    $content = $_;
    write_text($path, $content);
}

sub is_in {
    my $needle = shift;
    for (@_) {
        return 1 if $_ eq $needle;
    }
    0;
}

sub genesis_tarch_from_targetarch {
    my ($targetarch) = @_;
    return 'ppc64' if $targetarch eq 'ppc64le';
    return 'x86' if $targetarch =~ /^i[3-6]86$/;
    return $targetarch;
}

sub targetarch_from_target {
    my ($target) = @_;
    return $ARCH unless defined $target && length $target;
    my @parts = split /-/, $target;
    my $arch = $parts[-1];
    $arch =~ s/^\s+|\s+$//g;
    return lc $arch;
}

# product(\@A, \@B) returns the catersian product of \@A and \@B
sub product {
    my ($a, $b) = @_;
    return map {
        my $x = $_;
        map [ $x, $_ ], @$b;
    } @$a
}

sub setup_repo {
    my (%opts) = @_;
    my $id = $opts{-id} or confess "-id is required";
    my $name = $opts{-name} // $id;
    my $url = $opts{-baseurl} or confess "-url is required";
    my $gpgkey = $opts{-gpgkey};
    my $gpgcheck = $gpgkey ? 1 : 0 ;
    my $gpgkey_line =
            $gpgkey
            ? "gpgkey=$gpgkey"
            : "# gpgkey=";
    write_text("/etc/yum.repos.d/$id.repo", <<"EOF");
[$id]
name=$name
baseurl=$url
$gpgkey_line
gpgcheck=$gpgcheck
EOF
    $? >> 0;
}

sub createmockconfig {
    my ($pkg, $target) = @_;
    my $ext = $opts{mock_uniqueext} ? "-$opts{mock_uniqueext}" : "";
    my $chroot = "$pkg-$target$ext";
    my $cfgfile = "/etc/mock/$chroot.cfg";
    return if -f $cfgfile && ! $opts{force};
    cp "/etc/mock/$target.cfg", $cfgfile;
    my $contents = read_text($cfgfile);
    $contents =~ s/config_opts\['root'\]\s+=.*/config_opts['root'] = \"$chroot\"/;
    if ($pkg eq "perl-xCAT") {
        # perl-generators is required for having perl(xCAT::...) symbols
        # exported by the RPM
        $contents .= "config_opts['chroot_additional_packages'] = 'perl-generators'\n";
    }
    $contents .= "config_opts['environment']['SOURCE_DATE_EPOCH'] = '$SOURCE_DATE_EPOCH'\n";
    write_text($cfgfile, $contents);
}

sub buildsources_genesis_base($) {
    my ($target) = @_;

    die "Assertion failed! No directory xCAT-genesis-builder in the current directory"
        unless -d "./xCAT-genesis-builder";
    my $staging_parent = "/tmp/xcat-genesis-base-build-support.$$";
    my $staging_root = "$staging_parent/xCAT-genesis-base-build-support";
    my $support_tarball = "$SOURCES/xCAT-genesis-base-build-support.tar.bz2";

    remove_tree($staging_parent) if -e $staging_parent;
    make_path("$staging_root/dracut_105");

    sh(qq(cp -a "xCAT-genesis-builder/dracut_105" "$staging_root/"))
        and die "Error copying dracut_105 sources";
    cp "xCAT-genesis-builder/80-net-name-slot.rules",
       "$staging_root/80-net-name-slot.rules";

    unlink $support_tarball if -f $support_tarball;
    sh(qq(tar --sort=name --owner=0 --group=0 --mtime="\@$SOURCE_DATE_EPOCH" -cjf "$support_tarball" -C "$staging_parent" xCAT-genesis-base-build-support))
        and die "Error creating $support_tarball";

    remove_tree($staging_parent);
}

sub buildsources {
    my ($pkg, $target) = @_;

    if ($pkg eq "xCAT") {
        my @files = ("bmcsetup", "getipmi");
        for my $f (@files) {
            cp "xCAT-genesis-scripts/usr/bin/$f", "$pkg/postscripts/$f";
            sed { s/xcat.genesis.$f/$f/ } "${pkg}/postscripts/$f";
        }
        sh(<<"EOF");
          cd xCAT
          tar --sort=name --owner=0 --group=0 --mtime="\@$SOURCE_DATE_EPOCH" --exclude upflag -czf $SOURCES/postscripts.tar.gz  postscripts LICENSE.html
          tar --sort=name --owner=0 --group=0 --mtime="\@$SOURCE_DATE_EPOCH" -czf $SOURCES/prescripts.tar.gz  prescripts
          tar --sort=name --owner=0 --group=0 --mtime="\@$SOURCE_DATE_EPOCH" -czf $SOURCES/templates.tar.gz templates
          tar --sort=name --owner=0 --group=0 --mtime="\@$SOURCE_DATE_EPOCH" -czf $SOURCES/winpostscripts.tar.gz winpostscripts
          tar --sort=name --owner=0 --group=0 --mtime="\@$SOURCE_DATE_EPOCH" -czf $SOURCES/etc.tar.gz etc
          cp xcat.conf $SOURCES
          cp xcat.conf.apach24 $SOURCES
          cp xCATMN $SOURCES
EOF
    } elsif ($pkg eq "xCAT-genesis-scripts") {
      sh qq(tar --sort=name --owner=0 --group=0 --mtime="\@$SOURCE_DATE_EPOCH" -cjf "$SOURCES/$pkg.tar.bz2" $pkg);
    } elsif ($pkg eq "xCAT-genesis-base") {
        buildsources_genesis_base($target);
    } elsif ($pkg eq "xCATsn") {
      sh(<<"EOF");
          tar --sort=name --owner=0 --group=0 --mtime="\@$SOURCE_DATE_EPOCH" -czf "$SOURCES/$pkg-$VERSION.tar.gz" $pkg
          tar --sort=name --owner=0 --group=0 --mtime="\@$SOURCE_DATE_EPOCH" -czf "$SOURCES/license.tar.gz" -C $pkg LICENSE.html
          tar --sort=name --owner=0 --group=0 --mtime="\@$SOURCE_DATE_EPOCH" -czf "$SOURCES/etc.tar.gz" -C xCAT etc
          cp $pkg/xcat.conf $SOURCES
          cp $pkg/xcat.conf.apach24 $SOURCES
          cp $pkg/xCATSN $SOURCES
EOF
      # xCATsn.spec consumes templates from xCAT shared templates payload.
      sh qq(tar --sort=name --owner=0 --group=0 --mtime="\@$SOURCE_DATE_EPOCH" -czf "$SOURCES/templates.tar.gz" xCAT/templates) unless -f "$SOURCES/templates.tar.gz";
    } else {
      sh qq(tar --sort=name --owner=0 --group=0 --mtime="\@$SOURCE_DATE_EPOCH" -czf "$SOURCES/$pkg-$VERSION.tar.gz" $pkg);
    }
}

sub buildspkgs {
    my ($pkg, $target) = @_;

    my $ext = $opts{mock_uniqueext} ? "-$opts{mock_uniqueext}" : "";
    my $chroot = "$pkg-$target$ext";
    my $targetarch = targetarch_from_target($target);
    my $genesis_tarch = genesis_tarch_from_targetarch($targetarch);

    my $diskcache = (
        $pkg eq 'xCAT-genesis-scripts' || $pkg eq 'xCAT-genesis-base'
    ) ? "dist/$target/srpms/$pkg-$genesis_tarch-$VERSION-$RELEASE.src.rpm"
      : "dist/$target/srpms/$pkg-$VERSION-$RELEASE.src.rpm";
    return if -f $diskcache and not $opts{force};

    my $dir = sub {
        return "xCAT-genesis-builder"
            if $pkg eq "xCAT-genesis-base";
        $pkg;
    }->();

    my @opts;
    push @opts, "--quiet" unless $opts{verbose};


    say "Building $diskcache";

    sh(<<"EOF");
mock -r $chroot \\
    -N \\
    @{[ join "  ", @opts ]} \\
    --define "version $VERSION" \\
    --define "release $RELEASE" \\
    --define "gitinfo $GITINFO" \\
    --define "use_source_date_epoch_as_buildtime 1" \\
    --define "clamp_mtime_to_source_date_epoch 1" \\
    --define "_buildhost xcat-build" \\
    --buildsrpm \\
    --spec $dir/$pkg.spec \\
    --sources $SOURCES \\
    --resultdir "dist/$target/srpms/"
EOF
}

sub buildpkgs {
    my ($pkg, $target) = @_;
    my $optsref = \%opts;
    my $ext = $opts{mock_uniqueext} ? "-$opts{mock_uniqueext}" : "";
    my $chroot = "$pkg-$target$ext";

    my @native_pkgs = qw(
        xCAT
        xCAT-genesis-scripts
    );

    # get x86_64 from alma+epel-9-x86_64
    my $targetarch = targetarch_from_target($target);

    # xCAT genesis packages include the translated target arch in their file names.
    my $arch = is_in($pkg, @native_pkgs) ? $targetarch : "noarch";

    my $genesis_tarch = genesis_tarch_from_targetarch($targetarch);
    my $diskcache = (
        $pkg eq 'xCAT-genesis-scripts' || $pkg eq 'xCAT-genesis-base'
    ) ? "dist/$target/rpms/$pkg-$genesis_tarch-$VERSION-$RELEASE.noarch.rpm"
      : "dist/$target/rpms/$pkg-$VERSION-$RELEASE.$arch.rpm";
    return if -f $diskcache and not $opts{force};

    my @opts;
    push @opts, "--quiet" unless $opts{verbose};


    my $spkgname = sub {
        return "${pkg}-${genesis_tarch}-${VERSION}-${RELEASE}.src.rpm"
            if $pkg eq 'xCAT-genesis-scripts';
        return "xCAT-genesis-base-${genesis_tarch}-${VERSION}-${RELEASE}.src.rpm"
            if $pkg eq 'xCAT-genesis-base';

        return "$pkg-${VERSION}-${RELEASE}.src.rpm";
    }->();

    say "Building $pkg $diskcache";

    sh(<<"EOF");
mock -r $chroot \\
    -N \\
    @{[ join "  ", @opts ]} \\
    --define "version $VERSION" \\
    --define "release $RELEASE" \\
    --define "gitinfo $GITINFO" \\
    --define "use_source_date_epoch_as_buildtime 1" \\
    --define "clamp_mtime_to_source_date_epoch 1" \\
    --define "_buildhost xcat-build" \\
    --resultdir "dist/$target/rpms/" \\
    --rebuild dist/$target/srpms/$spkgname
EOF
}

sub buildall {
    my ($pkg, $target) = @_;
    createmockconfig($pkg, $target);
    buildsources($pkg, $target);
    buildspkgs($pkg, $target);
    buildpkgs($pkg, $target);
}

sub configure_nginx {
    my %os = os_release();
    my $version = $os{VERSION_ID};
    my $xcat_dep_path;

    if ($version > 10) {
        setup_repo
            -id => "VersatusHPC",
            -baseurl => "https://mirror.versatushpc.com.br/versatushpc/rpm/el10/";
        $xcat_dep_path = $opts{xcat_dep_path};
        confess "Missing xcat-dep folder in $xcat_dep_path: No such file or directory"
            unless -d $xcat_dep_path;
    } elsif ($version =~ /^9/) {
        $xcat_dep_path = "https://mirror.versatushpc.com.br/xcat/yum/xcat-dep/rh9/";
    } elsif ($version =~ /^8/) {
        $xcat_dep_path = "https://mirror.versatushpc.com.br/xcat/yum/xcat-dep/rh8/";
    } else {
        confess "Unexpected OS version $version";
    }
    confess "xcat-dep path still undef, this is likely to be a bug"
        unless defined $xcat_dep_path;

    my $port = $opts{nginx_port};
    my $conf = <<"EOF";
server {
    listen $port;
    listen [::]:$port;
EOF

    # We always generate the nginx config for all
    # the targets, not $opts{targets}
    for my $target (@TARGETS) {
        my $fullpath = "$PWD/dist/$target/rpms";
        $conf .= <<"EOF";
    location /$target/ {
        alias $fullpath/;
        autoindex on;
        index off;
        allow all;
    }
EOF
    }
    # TODO:I need one xcat-dep for each target
    $conf .= <<"EOF";
    location /xcat-dep/ {
        alias $xcat_dep_path;
        autoindex on;
        index off;
        allow all;
    }
}
EOF
    write_text("/etc/nginx/conf.d/xcat-repos.conf", $conf);
    `systemctl restart nginx`;
    $? >> 8;
}

sub repo_mode {
    my $mode = lc($opts{repo_mode} // "file");
    return $mode;
}

sub xcat_dep_file_repo_baseurl {
    my ($version, $arch) = @_;
    my $xcat_dep_path = $opts{xcat_dep_path};
    confess "Missing xcat-dep path: --xcat_dep_path is empty"
        unless defined $xcat_dep_path && length $xcat_dep_path;
    $xcat_dep_path =~ s{/+$}{};
    my $repo_path = "$xcat_dep_path/el$version/$arch";
    confess "Missing xcat-dep repository path in $repo_path: No such directory"
        unless -d $repo_path;
    return "file://$repo_path";
}

sub setup_local_repos {
    my ($target) = @_;
    $target //= $opts{targets}->[0]
        or die "A target must be provided for setup_local_repos";
    my $mode = repo_mode();
    my $core_baseurl = (
        $mode eq "file"
        ? "file://$PWD/dist/$target/rpms"
        : "http://127.0.0.1:$opts{nginx_port}/$target"
    );
    my $gpgkey = $opts{gpg_sign}
        ? "file://$PWD/dist/$target/rpms/repodata/repomd.xml.key"
        : undef;
    my $exit = setup_repo
        -id => "xcat-core-local",
        -baseurl => $core_baseurl,
        -gpgkey => $gpgkey;
    return $exit if $exit;
    my %os = os_release();
    my $version = int $os{VERSION_ID};
    my $arch = $ARCH;
    my $xcat_dep_baseurl = (
        $mode eq "file"
        ? xcat_dep_file_repo_baseurl($version, $arch)
        : "http://127.0.0.1:$opts{nginx_port}/xcat-dep/el$version/$arch"
    );

    $exit = setup_repo
            -id => "xcat-dep",
            -baseurl => $xcat_dep_baseurl;
}


sub update_repo {
    my ($target) = @_;
    say "Creating repository dist/$target/rpms";
    `find dist/$target/rpms -name ".src.rpm" -delete`;
    `createrepo --update dist/$target/rpms`;
}

sub sign_rpms {
    my ($target) = @_;
    my $key_name = $opts{gpg_key_name};
    my $repodir = "dist/$target/rpms";

    say "Signing RPMs in $repodir";
    my @rpms = glob("$repodir/*.rpm");
    if (@rpms) {
        my $rpm_list = join " ", map { qq("$_") } @rpms;
        sh(qq(rpmsign --define "%_gpg_name $key_name" --addsign $rpm_list))
            and die "Failed to sign RPMs in $repodir";
    }

    # rpmsign --addsign rewrites the rpm files, so the checksums recorded by the
    # earlier createrepo no longer match and dnf rejects them. Regenerate the repo
    # metadata now (after signing, before signing repomd.xml) so it stays consistent.
    say "Regenerating repo metadata after signing $repodir";
    sh(qq(createrepo --update "$repodir"))
        and die "Failed to regenerate repo metadata after signing";

    say "Signing repomd.xml for $target";
    my $repomd = "$repodir/repodata/repomd.xml";
    unlink "$repomd.asc" if -f "$repomd.asc";
    sh(qq(gpg -a --detach-sign --default-key "$key_name" "$repomd"))
        and die "Failed to sign $repomd";
    sh(qq(gpg -a --export "$key_name" > "$repomd.key"))
        and die "Failed to export public key";
}

sub main {
    usage(verbose => 2, exitval => 0) if $opts{help};
    my $mode = repo_mode();
    return usage(message => "Invalid --repo-mode '$opts{repo_mode}'. Allowed values: file, http")
        unless $mode eq "file" || $mode eq "http";

    return exit(configure_nginx()) if $opts{configure_nginx};
    return exit(setup_local_repos()) if $opts{setup_local_repos};

    my @rpms = product($opts{packages}, $opts{targets});
    my $pm = Parallel::ForkManager->new($opts{nproc});

    for my $pair (@rpms) {
        my ($pkg, $target) = $pair->@*;
        $pm->start and next;

        buildall($pkg, $target);

        $pm->finish;
    }

    $pm->wait_all_children;

    for my $target ($opts{targets}->@*) {
        $pm->start and next;

        update_repo($target);

        $pm->finish;
    }
    $pm->wait_all_children;

    if ($opts{gpg_sign}) {
        $ENV{GNUPGHOME} = $opts{gpg_home} if $opts{gpg_home};
        for my $target ($opts{targets}->@*) {
            sign_rpms($target);
        }
    }

    exit(0);
}

main();

__END__;

=head1 NAME

buildrpms.pl - Build xCAT RPM packages with mock

=head1 SYNOPSIS

  perl buildrpms.pl [options]

=head1 DESCRIPTION

Build xCAT packages (SRPM and RPM) for one or more targets using mock.
By default, this script only performs package builds and repository metadata
updates under C<dist/>. It does not configure nginx or yum repositories unless
explicitly requested.

=head1 OPTIONS

=over 4

=item B<--help>

Show usage text and exit.

=item B<--install_deps>

Install host build dependencies, mock, nginx, and supporting tools.
This option is handled before normal option parsing.

=item B<--target>=I<TARGET>

Build for the specified target. Repeatable. Example:
C<rocky+epel-10-ppc64le>.

=item B<--package>=I<PACKAGE>

Build only selected package(s). Repeatable.

=item B<--nproc>=I<N>

Number of parallel workers used by C<Parallel::ForkManager>.
Default: all host CPUs.

=item B<--force>

Rebuild artifacts even if output files already exist.

=item B<--release>=I<STRING>

Override the auto-generated C<snapYYYYMMDDHHMM> release string. xCAT packages
inter-depend on the exact C<Version-Release>, so use this to rebuild a single
package that installs alongside an already-built repo:

  ./buildrpms.pl --package xCAT-client --release snap202606060850 --force

C<--force> is usually required: with a pinned release the existing RPM under
C<dist/> matches the disk-cache check and the build would be skipped.

=item B<--verbose>

Print executed shell commands.

=item B<--xcat_dep_path>=I<PATH>

Path to the local C<xcat-dep> tree. Default: C<../xcat-dep/>.
Used by nginx configuration and file-based repo setup.

=item B<--repo-mode>=I<file|http>

Repository mode used by C<--setup_local_repos>. Default: C<file>.

C<file>:
configure C<xcat-core-local> and C<xcat-dep> using C<file://> URLs.
No nginx configuration is required.

C<http>:
configure local repos as C<http://127.0.0.1:E<lt>nginx_portE<gt>/...>.
Use C<--configure_nginx> to generate and apply nginx configuration first.

=item B<--configure_nginx>

Generate C</etc/nginx/conf.d/xcat-repos.conf> and restart nginx.
This is an explicit action and does not run during the default build flow.

=item B<--nginx_port>=I<PORT>

nginx listen port used by C<--configure_nginx> and C<--repo-mode=http>.
Default: C<8080>.

=item B<--setup_local_repos>

Write C</etc/yum.repos.d/xcat-core-local.repo> and
C</etc/yum.repos.d/xcat-dep.repo> for the selected mode.
This is an explicit action and does not run during the default build flow.

=item B<--gpg-sign>

Sign RPMs and repository metadata after build. Requires a GPG key
in the active keyring (default C<~/.gnupg> or the directory set by
C<--gpg-home>).

=item B<--gpg-home>=I<PATH>

Path to GNUPGHOME directory containing the signing key.
If not specified, uses the default GPG keyring.

=item B<--gpg-key-name>=I<NAME>

Name of the GPG key to use for signing.
Default: C<xCAT Automatic Signing Key>.

=back

=head1 DEFAULT FLOW

When no explicit repo/nginx options are passed, the script:

=over 4

=item 1.

Builds all selected package/target combinations.

=item 2.

Runs C<createrepo --update> for each selected target under C<dist/>.

=item 3.

If C<--gpg-sign> is set, signs RPMs and C<repomd.xml> for each target.

=item 4.

Exits without modifying nginx or yum repo files.

=back

=head1 KNOWN ERRORS

=over 4

=item 1.

Error: GPG error during mock cache creation/update.

Cause: out-dated C<distribution-gpg-keys> on the host machine.

Solution: run C<dnf update -y distribution-gpg-keys> on the host.

=back
