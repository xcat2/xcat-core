package XCAT::Test::RPM;

use strict;
use warnings;
use parent 'XCAT::Test::Lifecycle';
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use XCAT::Test::File qw(repo_path slurp_repo_file);
use lib repo_path('build-utils/lib');
use XCAT::BuildUtils qw(stage_xcatsn_templates);

sub build {
    my ($class, $package, $release, @defines) = @_;
    my $top = tempdir(CLEANUP => 1);
    make_path("$top/SOURCES");
    my $version = slurp_repo_file('Version');
    chomp $version;
    XCAT::Test::Lifecycle::checked('tar', '-czf', "$top/SOURCES/$package-$version.tar.gz",
        '-C', repo_path('.'), $package);
    if ($package eq 'xCAT' || $package eq 'xCATsn') {
        XCAT::Test::Lifecycle::checked('/bin/sh', repo_path('build-utils/sync-xcat-apache-configs'), '--stage', "$top/SOURCES");
        stage_xcatsn_templates(repo_path('.'), "$top/SOURCES", 0);
        XCAT::Test::Lifecycle::checked('tar', '-czf', "$top/SOURCES/etc.tar.gz", '-C', repo_path('xCAT'), 'etc');
        if ($package eq 'xCAT') {
            XCAT::Test::Lifecycle::checked('tar', '--exclude', 'upflag', '-czf', "$top/SOURCES/postscripts.tar.gz",
                '-C', repo_path('xCAT'), 'postscripts', 'LICENSE.html');
            for my $source (qw(prescripts winpostscripts)) {
                XCAT::Test::Lifecycle::checked('tar', '-czf', "$top/SOURCES/$source.tar.gz", '-C', repo_path('xCAT'), $source);
            }
            copy(repo_path('xCAT/xCATMN'), "$top/SOURCES/xCATMN") or die "copy xCATMN: $!";
        } else {
            XCAT::Test::Lifecycle::checked('tar', '-czf', "$top/SOURCES/license.tar.gz", '-C', repo_path('xCATsn'), 'LICENSE.html');
            copy(repo_path('xCATsn/xCATSN'), "$top/SOURCES/xCATSN") or die "copy xCATSN: $!";
        }
    }
    XCAT::Test::Lifecycle::checked('rpmbuild', '-bb', '--nodeps',
        '--define', "_topdir $top", '--define', "version $version",
        '--define', "release $release", @defines, repo_path("$package/$package.spec"));
    my @rpms = glob "$top/RPMS/*/*.rpm";
    die "Expected one $package RPM, found @rpms" unless @rpms == 1;
    return $rpms[0];
}

sub new {
    my ($class, %options) = @_;
    my $self = $class->SUPER::new;
    make_path(map { $self->path("/etc/rc.d/rc$_.d") } 0..6);
    make_path($self->path('/etc/rc.d/init.d'));
    unless ($options{init_directory}) {
        rmdir $self->path('/etc/init.d') or die "rmdir init.d: $!";
        symlink('rc.d/init.d', $self->path('/etc/init.d')) or die "symlink: $!";
    }
    for my $level (0..6) {
        symlink("rc.d/rc$level.d", $self->path("/etc/rc$level.d")) or die "symlink: $!";
    }
    my $sysimage = $self->path('/usr/lib/sysimage');
    unlink($sysimage) or die "unlink sysimage link: $!" if -l $sysimage;
    make_path("$sysimage/rpm");
    my ($status, $out, $err) = $self->run('rpm', '--initdb');
    die "Initializing RPM database failed: $out$err" if $status;
    return $self;
}

sub build_fixture {
    my ($class, $name, @defines) = @_;
    my $top = tempdir(CLEANUP => 1);
    XCAT::Test::Lifecycle::checked('rpmbuild', '-bb', '--define', "_topdir $top",
        '--define', 'xcat_source ' . repo_path('.'), @defines,
        repo_path("xCAT-test/fixtures/package-lifecycle/$name.spec"));
    my @rpms = glob "$top/RPMS/*/*.rpm";
    die 'Expected one fixture RPM' unless @rpms == 1;
    return $rpms[0];
}

sub install {
    my ($self, $rpm, @options) = @_;
    copy($rpm, $self->path('/tmp/package.rpm')) or die "copy RPM: $!";
    return $self->run('rpm', '--nodeps', '-U', @options, '/tmp/package.rpm');
}

1;
