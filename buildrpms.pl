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
    dnf install -y tar mock nginx createrepo_c podman rpmdevtools rpm-sign

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
use File::Temp qw(tempdir tempfile);
use FindBin qw($Bin);
use lib $Bin;
use BuildUtils qw(git_revision source_date_epoch sh usage);
use Fcntl qw(:flock);           # per-target build lock (concurrency guard; see main())
use Getopt::Long qw(GetOptions);
use POSIX qw(strftime);
use Parallel::ForkManager;
use Pod::Usage qw(pod2usage);

use autodie;
use autodie qw(cp);

require "$Bin/build-utils/lib/XCAT/BuildUtils.pm";

my $SOURCES = "$ENV{HOME}/rpmbuild/SOURCES";
# Ensure the rpmbuild tree exists. buildrpms stages source tarballs into $SOURCES, but it only
# runs rpmdev-setuptree in the one-time env-setup path -- so on a host where that never ran (or
# $HOME/rpmbuild was cleaned) source staging fails with "SOURCES/...: No such file or directory",
# no srpms/rpms are produced, and the run still exits 0. Create the tree up front so a build never
# depends on prior manual setup.
system('mkdir', '-p', map { "$ENV{HOME}/rpmbuild/$_" } qw(SOURCES SPECS BUILD BUILDROOT RPMS SRPMS));
my $VERSION = read_text("Version");
my $PWD = Cwd::cwd();
my @XCAT_PROBE_HELPERS = qw(
    GlobalDef.pm
    NetworkUtils.pm
    ServiceNodeUtils.pm
);

chomp($VERSION);

# Gitinfo is regenerated at each run with the current git revision.
my $GITINFO = git_revision();
write_text("Gitinfo", "$GITINFO\n");

my $SOURCE_DATE_EPOCH = source_date_epoch();
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

# xCAT-genesis-base is intentionally NOT in the default build set below. Its
# payload is a dracut-built initramfs that bundles the build chroot's kernel +
# glibc/busybox/perl, so it is OS-dependent (an el10 build cannot boot el8/el9
# nodes). It is built per target by the xcat-dep pipeline
# (xcat-dep/mockbuild-all.pl, via `buildrpms.pl --package xCAT-genesis-base`)
# and shipped in the per-EL repo xcat-dep/rh<N>, NOT in the flat xcat-core. The
# build logic further down still supports `--package xCAT-genesis-base`.
my @PACKAGES = qw(
    perl-xCAT
    xCAT
    xCATsn
    xCAT-buildkit
    xCAT-client
    xCAT-confluent
    xCAT-genesis-scripts
    xCAT-openbmc-py
    xCAT-probe
    xCAT-rmc
    xCAT-server
    xCAT-test
    xCAT-vlan
    xCAT-release
);

# The arch-native packages: their rpms carry the target arch. Everything else in @PACKAGES
# is noarch and byte-identical on every arch, so `--native-only` builds just these -- a
# secondary-arch build (e.g. ppc64le) then produces only what the x86_64 build cannot already
# provide, and the multi-arch merge has no duplicate noarch to reconcile.
my @NATIVE_PACKAGES = qw(xCAT xCATsn xCAT-genesis-scripts);

my @TARGETS = (
    "$DISTRO+epel-8-$ARCH",
    "$DISTRO+epel-9-$ARCH",
    "$DISTRO+epel-10-$ARCH",
);


my %opts = (
    configure_nginx => 0,
    force => 0,
    gpg_home => "",
    gpg_key_name => "xCAT Signing Key",
    gpg_sign => 0,
    help => 0,
    mock_uniqueext => "",
    nginx_port => 8080,
    nproc => int(`nproc --all`),
    packages => \@PACKAGES,
    release => "",
    repo_mode => "file",
    repo_baseurl => "https://xcat.org/files/xcat/repos/yum/devel/xcat-core",
    targets => \@TARGETS,
    verbose => 0,
    xcat_dep_path => "$PWD/../xcat-dep/",
);

my (@cli_packages, @cli_targets, @cli_input_core_repos);
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
    "package=s@" => \@cli_packages,
    "native-only" => \$opts{native_only},
    "release=s" => \$opts{release},
    "repo-mode=s" => \$opts{repo_mode},
    "target=s@" => \@cli_targets,
    "verbose" => \$opts{verbose},
    "xcat_dep_path=s" => \$opts{xcat_dep_path},
    "setup_local_repos" => \$opts{setup_local_repos},
    "merge-core-repos" => \$opts{merge_core_repos},
    "output-dir=s" => \$opts{output_dir},
    "input-core-repos=s{1,}" => \@cli_input_core_repos,
    "repo-baseurl=s" => \$opts{repo_baseurl},
    "source-only" => \$opts{source_only},
) or usage();

$BuildUtils::VERBOSE = $opts{verbose};

# --package REPLACES the default set (build exactly what was asked), so
# `--package xCAT-genesis-base` builds only genesis-base for the dep pipeline.
# The full default set is built on every arch (x86_64 and ppc64le alike), so each
# arch produces a complete, self-contained xcat-core repo.
# --source-only produces source rpms and nothing else. It is a build mode, so it has
# nothing to assemble and must not be confused with the deploy-time merge.
usage(message => "--source-only and --merge-core-repos are different modes; pass one")
    if $opts{source_only} && $opts{merge_core_repos};

$opts{packages} = \@cli_packages if @cli_packages;

# --native-only: build just the arch-native packages (@NATIVE_PACKAGES). Used on a
# secondary-arch builder (ppc64le) so the noarch packages get built only once, on x86_64.
$opts{packages} = [@NATIVE_PACKAGES] if $opts{native_only} && !@cli_packages;

# --input-core-repos accepts one or more dirs (repeatable, or several after one flag); each is
# a per-arch build's dist/<target>/rpms tree that --merge-core-repos assembles into --output-dir.
$opts{input_core_repos} = [@cli_input_core_repos] if @cli_input_core_repos;

# --target REPLACES the default (like --package), and exactly ONE target is built per
# invocation. The flat xcat-core is EL-agnostic, so a single <distro>+epel-10-<arch>
# build per arch is canonical; the multi-arch flat core is assembled separately via
# --merge-core-repos. Building several targets in one run is unsupported: Getopt used to
# bind --target directly to the pre-seeded 3-EL default and thus SILENTLY APPEND (so
# `--target X` built 4 targets). Collect into @cli_targets and reject >1 explicitly.
if (@cli_targets) {
    usage(verbose => 0,
          message => "only one --target may be given (got: @cli_targets); "
                   . "run buildrpms.pl once per target")
        if @cli_targets > 1;
    $opts{targets} = [@cli_targets];
} else {
    $opts{targets} = ["$DISTRO+epel-10-$ARCH"];
}

# Release is derived from SOURCE_DATE_EPOCH (the git commit time), NOT wall-clock,
# so identical sources -> identical Version-Release -> bit-reproducible packages
# (a hard requirement for the content-addressed/Merkle-DAG CI). Override with
# --release to rebuild a single package matching an existing repo's release.
my $RELEASE = $opts{release} || strftime("snap%Y%m%d%H%M", gmtime($SOURCE_DATE_EPOCH));
write_text("Release", "$RELEASE\n");

# sh_retry: run $cmd, retrying up to $tries times on non-zero exit. Absorbs transient mock/nspawn
# flakes (e.g. the systemd-nspawn ENOMEDIUM cgroup race, dnf mirror hiccups) so one bad attempt does
# not silently drop a package from the core. Returns the last exit code (0 on eventual success).
sub sh_retry {
    my ($cmd, $tries) = @_;
    $tries ||= 3;
    my $rc = 1;
    for my $t (1 .. $tries) {
        $rc = sh($cmd);
        return 0 if $rc == 0;
        warn "[buildrpms] build command failed (rc=$rc), attempt $t/$tries"
           . ($t < $tries ? " -- retrying after backoff...\n" : " -- giving up.\n");
        sleep(5 * $t) if $t < $tries;   # linear backoff
    }
    return $rc;
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
    if ($pkg eq "perl-xCAT" && $target !~ /suse|sles|leap/i) {
        # perl-generators exports perl(xCAT::...) provides on RHEL/Fedora; it does not
        # exist on openSUSE/SLES (rpm there generates perl provides itself), so injecting
        # it into a SUSE chroot aborts chroot setup. Suppress it for SUSE targets.
        $contents .= "config_opts['chroot_additional_packages'] = 'perl-generators'\n";
    }
    $contents .= "config_opts['environment']['SOURCE_DATE_EPOCH'] = '$SOURCE_DATE_EPOCH'\n";
    # Avoid systemd-nspawn: it INTERMITTENTLY fails chroot setup with
    #   "Failed to determine whether the unified cgroups hierarchy is used: No medium found"
    # (ENOMEDIUM), which drops that package from the (still-signed) core -> an incomplete build that
    # only surfaces later as a confusing MN install failure. 'simple' isolation is a plain chroot --
    # reliable for these RPM builds -- and sidesteps the nspawn cgroup race entirely.
    $contents .= "config_opts['isolation'] = 'simple'\n";
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

sub prepare_xcat_probe_source_tar {
    my $staging_parent = tempdir("xcat-probe-source.XXXXXX", TMPDIR => 1, CLEANUP => 1);
    my $staging_root = "$staging_parent/xCAT-probe";
    my $helper_dir = "$staging_root/lib/perl/xCAT";
    my $source_tarball = "$SOURCES/xCAT-probe-$VERSION.tar.gz";

    sh(qq(cp -a "xCAT-probe" "$staging_root"))
        and die "Error staging xCAT-probe sources";

    remove_tree($helper_dir) if -e $helper_dir;
    make_path($helper_dir);
    chmod 0755, $helper_dir;
    for my $helper (@XCAT_PROBE_HELPERS) {
        my $destination = "$helper_dir/$helper";
        cp "perl-xCAT/xCAT/$helper", $destination;
        chmod 0644, $destination;
    }

    my ($archive_fh, $archive_path) = tempfile(
        ".xCAT-probe-$VERSION.XXXXXX",
        DIR => $SOURCES,
        UNLINK => 1,
    );
    close $archive_fh;

    sh(qq(tar --sort=name --owner=0 --group=0 --numeric-owner --mtime="\@$SOURCE_DATE_EPOCH" --use-compress-program="gzip -n" -cf "$archive_path" -C "$staging_parent" xCAT-probe))
        and die "Error creating $source_tarball";

    chmod 0644, $archive_path;
    rename $archive_path, $source_tarball;
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
EOF
      system('build-utils/sync-xcat-apache-configs', '--stage', $SOURCES) == 0
          or die "FATAL: unable to stage canonical Apache configurations\n";
      cp "$pkg/xCATSN", $SOURCES;
      # xCATsn.spec consumes templates from xCAT shared templates payload.
      sh qq(tar --sort=name --owner=0 --group=0 --mtime="\@$SOURCE_DATE_EPOCH" -czf "$SOURCES/templates.tar.gz" xCAT/templates) unless -f "$SOURCES/templates.tar.gz";
    } elsif ($pkg eq "xCAT-probe") {
      # Prepared once before target builds fork so workers only read a complete archive.
      return;
    } else {
      sh qq(tar --sort=name --owner=0 --group=0 --mtime="\@$SOURCE_DATE_EPOCH" -czf "$SOURCES/$pkg-$VERSION.tar.gz" $pkg);
    }
}

sub buildspkgs {
    my ($pkg, $target) = @_;

    my $ext = $opts{mock_uniqueext} ? "-$opts{mock_uniqueext}" : "";
    my $chroot = "$pkg-$target$ext";
    my $targetarch =
      XCAT::BuildUtils::targetarch_from_target( $target, $ARCH );
    my $genesis_tarch = genesis_tarch_from_targetarch($targetarch);

    my $diskcache = (
        $pkg eq 'xCAT-genesis-scripts' || $pkg eq 'xCAT-genesis-base'
    ) ? "dist/$target/rpms/SRPMS/$pkg-$genesis_tarch-$VERSION-$RELEASE.src.rpm"
      : "dist/$target/rpms/SRPMS/$pkg-$VERSION-$RELEASE.src.rpm";
    return if -f $diskcache and not $opts{force};

    my $dir = sub {
        return "xCAT-genesis-builder"
            if $pkg eq "xCAT-genesis-base";
        $pkg;
    }->();

    my @opts;
    push @opts, "--quiet" unless $opts{verbose};


    say "Building $diskcache";

    # Clean-before-start: re-init the buildroot from mock's root cache so a corrupt or
    # half-built chroot left behind by a PREVIOUS aborted/failed run cannot poison this
    # build (this is what caused "cannot open Packages database ... /usr/lib/sysimage/rpm"
    # -> missing rpm -> incomplete core). Cheap: --init restores from the cached root
    # tarball rather than a full dnf bootstrap, and the -N below then reuses THIS freshly
    # initialised root for both the srpm and the binary rebuild within this run. We reach
    # here only when actually building (past the diskcache skip), so flat-disk reuse across
    # runs is preserved -- we just guarantee a known-good starting point each time.
    sh_retry(qq(mock -r $chroot @{[ join "  ", @opts ]} --init)) == 0
        or die "FATAL: mock --init failed for $chroot ($pkg/$target)\n";

    sh_retry(<<"EOF") == 0 or die "FATAL: srpm build failed for $pkg ($target)\n";
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
    --resultdir "dist/$target/rpms/SRPMS/"
EOF
}

sub buildpkgs {
    my ($pkg, $target) = @_;
    my $optsref = \%opts;
    my $ext = $opts{mock_uniqueext} ? "-$opts{mock_uniqueext}" : "";
    my $chroot = "$pkg-$target$ext";

    # get x86_64 from alma+epel-9-x86_64
    my $targetarch =
      XCAT::BuildUtils::targetarch_from_target( $target, $ARCH );

    # xCAT genesis packages include the translated target arch in their file names.
    my $arch = is_in($pkg, @NATIVE_PACKAGES) ? $targetarch : "noarch";

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

    sh_retry(<<"EOF") == 0 or die "FATAL: rpm rebuild failed for $pkg ($target)\n";
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
    --rebuild dist/$target/rpms/SRPMS/$spkgname
EOF
}

sub buildall {
    my ($pkg, $target) = @_;
    createmockconfig($pkg, $target);
    buildsources($pkg, $target);
    buildspkgs($pkg, $target);
    # --source-only stops here: buildspkgs has produced the src.rpm, and the binary
    # rebuild is the only thing buildpkgs does. Everything upstream of this point --
    # the spec, the staged sources, the mock root -- is identical either way, which
    # is why source-only belongs here rather than in a parallel script.
    return if $opts{source_only};
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


# Index one repo dir with deterministic, upstream-matching metadata. createrepo_c's
# defaults already emit primary/filelists/other as *.xml.zst plus *.sqlite.bz2
# (--database), exactly the upstream shape; --set-timestamp-to-revision pins the
# repomd timestamp to SOURCE_DATE_EPOCH.
sub createrepo_dir {
    my ($dir, $extra) = @_;
    $extra //= '';
    sh(qq(createrepo_c --update --database )
       . qq(--revision "$SOURCE_DATE_EPOCH" --set-timestamp-to-revision $extra "$dir"))
        and die "Failed to createrepo_c $dir\n";
}

# A core repo dir holds binaries flat plus a SRPMS/ subdir carrying its own
# repodata (the upstream xcat.org layout). mock --rebuild re-emits the .src.rpm
# into the binary resultdir, but the canonical copy lives in SRPMS/, so drop the
# top-level strays; then index the binaries EXCLUDING the SRPMS/ subdir so no
# src.rpm enters the binary repomd, and index the SRPMS repo separately.
sub index_repo {
    my ($repodir) = @_;
    my $alias = "$repodir/xCAT-release-latest.noarch.rpm";

    # The stable bootstrap filename is a direct-download convenience, not a
    # second package. Keep it out of repository metadata.
    unlink $alias if -f $alias;
    say "Creating repository $repodir";
    # Drop the top-level stray src.rpm and the mock logs (build.log/root.log/...)
    # that mock leaves in the resultdir, so the dir is directly deployable (upstream
    # ships neither). The canonical src.rpm lives in SRPMS/.
    unlink($_) for glob("$repodir/*.src.rpm"), glob("$repodir/*.log"),
                   glob("$repodir/SRPMS/*.log");
    # In source-only mode no binaries were built, so re-indexing the binary dir would
    # replace good metadata with metadata for an empty repo -- publishing a repo that
    # resolves nothing. Leave it exactly as the last binary build left it and index
    # only the srpms.
    createrepo_dir($repodir, "--excludes 'SRPMS/*' --excludes '*.src.rpm'")
        unless $opts{source_only};
    createrepo_dir("$repodir/SRPMS") if -d "$repodir/SRPMS";
}

sub update_repo {
    my ($target) = @_;
    index_repo("dist/$target/rpms");
}

sub write_release_alias {
    my ($repodir) = @_;
    my $alias = "$repodir/xCAT-release-latest.noarch.rpm";

    # glob() returns a wildcard-free pattern verbatim even when the file does not exist, so
    # guard on the rpm actually being present. Without this, a partial build that does not
    # produce xCAT-release (e.g. buildrpms.pl --package xCAT-genesis-base) would try to cp a
    # nonexistent rpm here and die.
    my @release_rpms = grep { -f } glob("$repodir/xCAT-release-$VERSION-$RELEASE.noarch.rpm");
    if (@release_rpms == 1) {
        cp $release_rpms[0], $alias or die "cp $release_rpms[0] -> $alias: $!";
        chmod 0644, $alias;
    }
}

sub sign_rpms {
    my ($target) = @_;
    sign_repo_dir("dist/$target/rpms", $opts{gpg_key_name});
}

# Sign every rpm in a core repo dir -- the top-level binaries AND SRPMS/*.src.rpm --
# then re-index (signing rewrites the rpms, invalidating checksums) and detach-sign
# + export the key into BOTH the binary and the SRPMS repodata dirs.
sub sign_repo_dir {
    my ($repodir, $key_name) = @_;

    say "Signing RPMs in $repodir";
    my @bin = glob("$repodir/*.rpm");
    if (@bin) {
        sh(qq(rpmsign --define "%_gpg_name $key_name" --addsign )
           . join(" ", map { qq("$_") } @bin))
            and die "Failed to sign RPMs in $repodir";
    }
    my @src = glob("$repodir/SRPMS/*.src.rpm");
    if (@src) {
        sh(qq(rpmsign --define "%_gpg_name $key_name" --addsign )
           . join(" ", map { qq("$_") } @src))
            and die "Failed to sign SRPMs in $repodir/SRPMS";
    }

    # Regenerate both indexes (binary + SRPMS) after signing, before signing repomd.
    index_repo($repodir);

    for my $rd ("$repodir/repodata",
                (-d "$repodir/SRPMS/repodata" ? ("$repodir/SRPMS/repodata") : ())) {
        my $repomd = "$rd/repomd.xml";
        next unless -f $repomd;
        say "Signing $repomd";
        unlink "$repomd.asc" if -f "$repomd.asc";
        sh(qq(gpg -a --detach-sign --default-key "$key_name" "$repomd"))
            and die "Failed to sign $repomd";
        sh(qq(gpg -a --export "$key_name" > "$rd/repomd.xml.key"))
            and die "Failed to export public key to $rd";
    }
}

# Emit the deployable repo metadata into dist/$target/rpms: xcat-core.repo,
# mklocalrepo.sh and buildinfo.txt (templates ported from buildcore.sh). This makes
# the built tree directly deployable to xcat.org and removes the need for
# cluster-test.pl to re-collect / re-createrepo the dist output.
sub write_repo_metadata {
    my ($target) = @_;
    write_repo_metadata_dir("dist/$target/rpms");
}

sub write_repo_metadata_dir {
    my ($repodir) = @_;
    return unless -d $repodir;
    # The .repo file and buildinfo describe an installable binary repository. A
    # source-only run produced none, so emitting them would advertise packages that
    # are not there.
    return if $opts{source_only};

    # Shipped baseurl points at xcat.org (--repo-baseurl overrides it per family, e.g. the
    # sles/apt layout); mklocalrepo.sh rewrites baseurl/gpgkey to file:// at deploy time.
    my $baseurl = $opts{repo_baseurl};
    my $gpgcheck = $opts{gpg_sign} ? 1 : 0;
    my $gpgkey_line = $opts{gpg_sign}
        ? "gpgkey=$baseurl/repodata/repomd.xml.key"
        : "# gpgkey=";
    write_text("$repodir/xcat-core.repo", <<"EOF");
[xcat-core]
name=xCAT 2 Core packages
baseurl=$baseurl
enabled=1
gpgcheck=$gpgcheck
$gpgkey_line
EOF

    write_text("$repodir/mklocalrepo.sh", <<'EOF2');
#!/bin/sh
cd `dirname $0`
REPOFILE=`basename xcat-*.repo`
if [[ $REPOFILE == "xcat-*.repo" ]]; then
    echo "ERROR: For xcat-dep, please execute $0 in the correct <os>/<arch> subdirectory"
    exit 1
fi
#
# default to RHEL yum, if doesn't exist try Zypper
#
DIRECTORY="/etc/yum.repos.d"
if [ ! -d "$DIRECTORY" ]; then
    DIRECTORY="/etc/zypp/repos.d"
fi
sed -e 's|baseurl=.*|baseurl=file://'"`pwd`"'|' $REPOFILE | sed -e 's|gpgkey=.*|gpgkey=file://'"`pwd`"'/repodata/repomd.xml.key|' > "$DIRECTORY/$REPOFILE"
if [ -f "$DIRECTORY/xCAT-core.repo" ]; then
    mv "$DIRECTORY/xCAT-core.repo" "$DIRECTORY/xCAT-core.repo.nouse"
fi
cd -
EOF2
    chmod 0775, "$repodir/mklocalrepo.sh";

    # BUILD_TIME from SOURCE_DATE_EPOCH keeps buildinfo reproducible across rebuilds.
    my $build_time = strftime("%a %b %e %H:%M:%S %Z %Y", gmtime($SOURCE_DATE_EPOCH));
    my $build_machine = `hostname`; chomp $build_machine;
    my $commit_short = substr($GITINFO, 0, 7);
    write_text("$repodir/buildinfo.txt", <<"EOF");
VERSION=$VERSION
RELEASE=$RELEASE
BUILD_TIME=$build_time
BUILD_MACHINE=$build_machine
COMMIT_ID=$commit_short
COMMIT_ID_LONG=$GITINFO
EOF
}

# Assemble the flat MULTI-ARCH core from per-arch build outputs and sign it, in the upstream
# xcat.org layout, reusing the same index/sign/metadata code as a per-target build. Given
# --output-dir OUT and one or more --input-core-repos IN (each a per-arch dist/<target>/rpms
# tree), this wipes OUT, rsyncs every IN into it (excluding each arch's own repodata/; noarch
# packages dedup), then does the single final createrepo_c + repomd signing -- no packages are
# moved by hand. This absorbs the wipe+rsync assembly that used to live in the CI caller.
#
# Start CLEAN (wipe OUT first): snap-versioned rpms carry a per-build timestamp in their NVR, so
# merging into a dirty OUT would PILE UP stale versions from prior builds and make the flat core
# unresolvable (e.g. an old noarch against a fresh ppc build).
sub merge_core_repos {
    my $out = $opts{output_dir}
        or die "FATAL: --merge-core-repos requires --output-dir\n";
    my @ins = @{ $opts{input_core_repos} || [] };
    die "FATAL: --merge-core-repos requires at least one --input-core-repos dir\n" unless @ins;
    -d $_ or die "FATAL: --input-core-repos dir '$_' does not exist\n" for @ins;

    sh(qq(rm -rf "$out")) and die "Failed to clean output dir '$out'\n";
    make_path($out);
    for my $in (@ins) {
        sh(qq(rsync -a --exclude 'repodata/' "$in/" "$out/"))
            and die "Failed to rsync '$in' into '$out'\n";
    }

    # Index, sign (when --gpg-sign), write the final repository metadata, then create the
    # xCAT-release-latest stable bootstrap alias. The alias MUST be created AFTER the final
    # metadata pass so write_release_alias can unlink it before createrepo and keep it out of
    # the repository index.
    index_repo($out);
    if ($opts{gpg_sign}) {
        $ENV{GNUPGHOME} = $opts{gpg_home} if $opts{gpg_home};
        sign_repo_dir($out, $opts{gpg_key_name});
    }
    write_repo_metadata_dir($out);
    write_release_alias($out);
    return 0;
}

# --- graceful mock cancellation --------------------------------------------------
# A mock build killed mid-flight would leave its chroot bind-mounts (proc/sys/dev and the
# -bootstrap chroot's dnf/yum cache mounts) and orphaned rpmbuild/dnf processes behind,
# breaking the next run. Verified out-of-band: when the *mock* process itself receives
# SIGTERM it runs orphansKill, unmounts every chroot it created, releases its buildroot
# flock, and exits within a couple of seconds -- mock cleans up after itself. Builds run
# as Parallel::ForkManager children (main -> child -> mock -> rpmbuild), and the trap here
# sees SIGINT/SIGTERM before those mock grandchildren, so it just forwards the signal to
# the in-flight mock processes and WAITS for mock to finish that cleanup. Only if a mock
# is wedged do we escalate to SIGKILL and lazy-unmount by hand. (The 0-byte buildroot.lock
# file and the cached chroot dirs left behind are normal mock state, not leaks.)
my %MOCK_INFLIGHT;      # ForkManager child pid => mock chroot (-r) name it is building
my $ABORTING = 0;
my $BUILD_LOCK_FH;      # per-target build flock; MUST stay file-scoped so the fd (and thus the
                        # lock) lives for the whole process. A lexical inside main()'s block would
                        # be DESTROYED at block exit -> lock released before any worker forks.
my @CHILD_FAILURES;     # idents (chroot names) of ForkManager children that exited non-zero

# PIDs of running mock processes whose `-r <chroot>` matches one of @chroots.
sub mock_pids {
    my %want = map { (" -r $_ " => 1) } @_;
    my @pids;
    for my $proc (glob '/proc/[0-9]*') {
        my ($pid) = $proc =~ m{/(\d+)\z} or next;
        open my $fh, '<', "$proc/cmdline" or next;
        local $/; my $cmd = <$fh>; close $fh;
        next unless defined $cmd;
        $cmd =~ tr/\0/ /;                            # NUL-separated argv -> spaces
        next unless $cmd =~ m{(?:^|/)mock } && index($cmd, ' -r ') >= 0;
        push @pids, $pid if grep { index($cmd, $_) >= 0 } keys %want;
    }
    return @pids;
}

sub sweep_mock_mounts {
    # Fallback only (after SIGKILL): lazy-unmount binds left under THIS build's own chroots --
    # each chroot's dir plus its "-bootstrap" sibling. Scoped to @chroots so an unrelated,
    # concurrent build's mounts under other /var/lib/mock chroots are never torn out.
    my (@chroots) = @_;
    return unless @chroots;
    my %want = map { $_ => 1 } @chroots;
    open my $f, '<', '/proc/mounts' or return;
    my @mp = grep {
        my ($comp) = m{^/var/lib/mock/([^/]+)/};
        if (defined $comp) { (my $base = $comp) =~ s/-bootstrap$//; $want{$comp} || $want{$base} }
        else { 0 }
    } map { (split ' ')[1] } <$f>;
    close $f;
    system('umount', '-l', $_) for sort { length($b) <=> length($a) } @mp;
}

sub abort_builds {
    my ($sig) = @_;
    return if $ABORTING;
    $ABORTING = 1;
    warn "\n[buildrpms] caught SIG$sig: aborting -- signalling mock to self-clean...\n";
    my @chroots = values %MOCK_INFLIGHT;
    kill 'TERM', mock_pids(@chroots);               # mock unmounts + orphanKills itself
    kill 'TERM', keys %MOCK_INFLIGHT;               # unwind the ForkManager builders too
    my @mock;
    for (1 .. 30) {                                 # wait for mock to finish its own cleanup
        @mock = mock_pids(@chroots);
        last unless @mock;
        select undef, undef, undef, 1;
    }
    if (@mock) {                                    # wedged mock -> force it, then clean by hand
        warn "[buildrpms] mock still running after 30s; SIGKILL + unmount sweep\n";
        kill 'KILL', @mock, keys %MOCK_INFLIGHT;
        select undef, undef, undef, 2;
        sweep_mock_mounts(@chroots);
    }
    warn "[buildrpms] abort cleanup done\n";
    $SIG{$sig} = 'DEFAULT';
    kill $sig, $$;                                  # re-raise for the correct exit status
}

sub main {
    usage(verbose => 2, exitval => 0) if $opts{help};
    my $mode = repo_mode();
    return usage(message => "Invalid --repo-mode '$opts{repo_mode}'. Allowed values: file, http")
        unless $mode eq "file" || $mode eq "http";

    return exit(configure_nginx()) if $opts{configure_nginx};
    return exit(setup_local_repos()) if $opts{setup_local_repos};
    return exit(merge_core_repos()) if $opts{merge_core_repos};

    prepare_xcat_probe_source_tar()
        if grep { $_ eq "xCAT-probe" } $opts{packages}->@*;

    # ---- concurrency guard (mirrors cluster-test.pl's per-cluster lock) --------------------------
    # Every per-package mock chroot/config for this run shares the "<pkg>-<target><ext>" namespace:
    # /etc/mock/<cfg>.cfg, /var/lib/mock/<cfg>/ and its buildroot.lock. Two builds of the SAME
    # target(+uniqueext) therefore CLOBBER each other's mock config (SOURCE_DATE_EPOCH -> wrong NVR)
    # and race the shared chroot -- and abort_builds' fallback lazy-unmounts this build's own chroot
    # binds, which for the SAME target(+ext) are the very dirs a peer uses. So refuse to run a second
    # build of the same target(+ext) concurrently. Distinct targets / --mock-uniqueext are independent
    # and never conflict. (Held for the process lifetime via $BUILD_LOCK_FH, a file-scoped handle.)
    {
        my $key = join('-', $opts{targets}->@*)
                . ($opts{mock_uniqueext} ? "-$opts{mock_uniqueext}" : "");
        $key =~ s/[^A-Za-z0-9._-]/-/g;
        my $lock = "/var/lock/buildrpms.$key.lock";
        if (open($BUILD_LOCK_FH, '>', $lock)) {
            unless (flock($BUILD_LOCK_FH, LOCK_EX | LOCK_NB)) {
                die "FATAL: another buildrpms.pl is already building target '@{$opts{targets}}'"
                  . ($opts{mock_uniqueext} ? " (uniqueext=$opts{mock_uniqueext})" : "") . ".\n"
                  . "       ($lock is held). Concurrent builds of the same target collide on the shared\n"
                  . "       /etc/mock + /var/lib/mock chroot namespace (wrong NVR + a killed peer's\n"
                  . "       cleanup unmounts this build's chroot). Serialize them, or pass a distinct\n"
                  . "       --mock-uniqueext per build.\n";
            }
            # $BUILD_LOCK_FH is file-scoped, so the fd stays open (lock held) until this process
            # exits. Child forks inherit the fd but their exits never release it (the parent's
            # still-open fd keeps the lock), which is exactly what we want.
        }
    }

    my @rpms = product($opts{packages}, $opts{targets});
    my $pm = Parallel::ForkManager->new($opts{nproc});

    # Track which mock chroot each live child is building so abort_builds can scrub it.
    local $SIG{INT}  = \&abort_builds;
    local $SIG{TERM} = \&abort_builds;
    $pm->run_on_start(sub { my ($pid, $chroot) = @_; $MOCK_INFLIGHT{$pid} = $chroot if defined $chroot; });
    $pm->run_on_finish(sub {
        my ($pid, $exit_code, $ident, $exit_signal, $core_dump) = @_;
        delete $MOCK_INFLIGHT{$pid};
        # A child that die()s exits non-zero; one killed by a SIGNAL (SIGKILL / OOM-killer) is reaped
        # with $exit_code==0 but $exit_signal!=0 (and maybe $core_dump). Checking $exit_code alone
        # would let an OOM-killed worker through and the parent would index+sign a partial repository
        # (a core missing packages). Treat a non-zero exit, a killing signal, OR a core dump as failure.
        push @CHILD_FAILURES, ($ident // "pid=$pid") if $exit_code || $exit_signal || $core_dump;
    });

    for my $pair (@rpms) {
        my ($pkg, $target) = $pair->@*;
        my $ext = $opts{mock_uniqueext} ? "-$opts{mock_uniqueext}" : "";
        my $chroot = "$pkg-$target$ext";              # matches buildspkgs/buildpkgs `-r`
        $pm->start($chroot) and next;
        $SIG{INT} = $SIG{TERM} = 'DEFAULT';           # child: die on signal; the parent cleans up

        buildall($pkg, $target);

        $pm->finish;
    }

    $pm->wait_all_children;

    # Gate: if any package build failed, stop here -- do NOT update_repo/sign a partial core.
    if (@CHILD_FAILURES) {
        die "FATAL: build failed for: @CHILD_FAILURES\n"
          . "       refusing to index/sign a partial repository.\n";
    }

    for my $target ($opts{targets}->@*) {
        $pm->start and next;                          # no chroot ident: update_repo runs no mock
        $SIG{INT} = $SIG{TERM} = 'DEFAULT';

        update_repo($target);

        $pm->finish;
    }
    $pm->wait_all_children;

    # Gate: a failed repo index (update_repo die) must not be signed as if complete.
    if (@CHILD_FAILURES) {
        die "FATAL: repo update failed for: @CHILD_FAILURES\n"
          . "       refusing to sign an incomplete repository.\n";
    }

    if ($opts{gpg_sign}) {
        $ENV{GNUPGHOME} = $opts{gpg_home} if $opts{gpg_home};
        for my $target ($opts{targets}->@*) {
            sign_rpms($target);
        }
    }

    # Emit deployable repo metadata (after signing, so the .repo gpgkey line matches
    # the freshly written repomd.xml.key).
    for my $target ($opts{targets}->@*) {
        write_repo_metadata($target);
    }

    # Signing regenerates repository metadata, so create the direct-download
    # alias only after the final metadata pass.
    for my $target ($opts{targets}->@*) {
        write_release_alias("dist/$target/rpms");
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

Build for the specified mock target, e.g. C<alma+epel-10-ppc64le>. Exactly ONE target
is built per invocation: passing more than one C<--target> is an error (run the script
once per target). When omitted, the default is a single C<< <distro>+epel-10-<arch> >>
derived from the host. The multi-arch flat core is assembled from per-arch builds via
C<--merge-core-repos>.

A riscv64 build on an x86_64 builder needs a mock configuration that sets
C<config_opts['forcearch'] = 'riscv64'> (with the riscv64 qemu-user-static
emulator registered through binfmt); the stock C<rocky-10-riscv64.cfg> only allows
riscv64 build hosts. Copy it under a new name in C</etc/mock>, add the forcearch
option, and pass that name as C<--target>, e.g. C<--target=rocky-10-riscv64-xcat>.

=item B<--package>=I<PACKAGE>

Build only selected package(s). Repeatable.

=item B<--native-only>

Build only the arch-native packages (C<xCAT>, C<xCATsn>, C<xCAT-genesis-scripts>) -- the
ones whose rpms carry the target arch. Everything else in the default set is C<noarch> and
identical on every arch, so a secondary-arch builder (e.g. ppc64le or riscv64) uses this to avoid
rebuilding the noarch packages that the x86_64 builder already produces. Ignored if
C<--package> is given.

=item B<--nproc>=I<N>

Number of parallel workers used by C<Parallel::ForkManager>.
Default: all host CPUs.

=item B<--force>

Rebuild artifacts even if output files already exist.

=item B<--source-only>

Build source RPMs and stop. Every step up to and including C<mock --buildsrpm> runs
normally, so the srpms are the same ones a full build would produce; only the binary
C<--rebuild> is skipped.

  ./buildrpms.pl --target alma+epel-9-x86_64 --source-only

The srpms land in C<dist/E<lt>targetE<gt>/rpms/SRPMS/> and that index is regenerated.
The binary metadata under C<dist/E<lt>targetE<gt>/rpms/> is deliberately left as the
last binary build wrote it: re-indexing a directory with no binaries in it would
replace working metadata with metadata for an empty repository. For the same reason
no C<.repo> file or buildinfo is emitted, since both describe an installable binary
repo that this mode does not produce. With C<--gpg-sign> the srpms are signed.

Cannot be combined with C<--merge-core-repos>, which assembles already-built
per-arch binary trees.

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

=item B<--merge-core-repos>

Assemble the flat multi-arch C<xcat-core> from per-arch build outputs and sign it, then exit.
Requires C<--output-dir> and one or more C<--input-core-repos>. Wipes the output dir, rsyncs
every input into it (excluding each arch's own C<repodata/>; C<noarch> packages dedup), then
runs a single C<createrepo_c> plus (with C<--gpg-sign>) C<repomd.xml> signing.

=item B<--output-dir>=I<DIR>

Destination for C<--merge-core-repos>: the assembled, signed flat multi-arch core.
Wiped and recreated on each run.

=item B<--input-core-repos>=I<DIR>...

Input dirs for C<--merge-core-repos>: one or more per-arch C<dist/<target>/rpms> trees to merge
into C<--output-dir>. Repeatable, and also accepts several dirs after a single flag.

=item B<--repo-baseurl>=I<URL>

Base URL written into the generated C<xcat-core.repo> (and its C<gpgkey> line). Defaults to the
yum/devel path; override per family, e.g. C<https://xcat.org/files/xcat/repos/sles/latest/xcat-core>
for SUSE. Applies to both per-target builds and C<--merge-core-repos>.

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
