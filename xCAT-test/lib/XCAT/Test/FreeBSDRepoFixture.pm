package XCAT::Test::FreeBSDRepoFixture;

use strict;
use warnings;
use Carp qw(croak);
use File::Path qw(make_path);
use JSON;

sub new {
    my ($class, %context) = @_;
    return bless { %context, sequence => 0, json => JSON->new->utf8->canonical }, $class;
}

sub new_directory {
    my $self = shift;
    my $path = "$self->{root}/tree-" . ++$self->{sequence};
    make_path($path);
    return $path;
}

sub create_package {
    my ($self, $directory, $name, %options) = @_;
    my $root = $self->{root};
    my $manifest = { name => $name, version => '1', origin => "misc/$name",
        comment => 'Repository inspection fixture', desc => 'Repository inspection fixture',
        maintainer => 'root@example.invalid', www => 'https://example.invalid', prefix => '/usr/local',
        abi => 'FreeBSD:15:amd64', arch => 'freebsd:15:x86:64', flatsize => 0,
        licenselogic => 'single', licenses => ['BSD2CLAUSE'], annotations => { FreeBSD_version => '1500068' },
        scripts => { 'post-install' => "touch '$root/package-script-executed'" }, %options };
    my $input = "$root/manifest-" . ++$self->{sequence};
    $self->{write_file}->($input, $self->{json}->encode($manifest));
    make_path($directory);
    $self->{run_pkg}->('create', '-M', $input, '-r', "$root/empty", '-o', $directory);
    return "$directory/$name-$manifest->{version}.pkg";
}

sub repository {
    my ($self, $signed, $definitions) = @_;
    my $root = $self->new_directory();
    for my $definition (@$definitions) {
        $self->create_package("$root/All", @$definition);
    }
    $self->{run_pkg}->('repo', $root, $signed ? ("rsa:$self->{root}/repo.key") : ());
    return $root;
}

sub release_tree {
    my ($self, $dvd) = @_;
    my @base = map { [$_, version => '15.1', origin => "base/$_",
        annotations => { FreeBSD_version => '1501000' }] }
      qw(FreeBSD-runtime FreeBSD-kernel-generic FreeBSD-set-minimal FreeBSD-set-base);
    push @base, ['pkg', version => '2.6.2_1', origin => 'ports-mgmt/pkg'];
    my $repo = $self->repository(0, \@base);
    my $root = $self->new_directory();
    $self->{write_file}->("$root/bin/freebsd-version", "USERLAND_VERSION=\"15.1-RELEASE\"\nexit 99\n");
    $self->{write_file}->("$root/bin/sh", "\x7fELF\x02\x01\x01\x09" . ("\0" x 10) . pack('v', 62));
    make_path("$root/usr/freebsd-packages");
    $self->{command}->('/usr/bin/cp', '-a', $repo, "$root/usr/freebsd-packages/offline");
    if ($dvd) {
        my $apps = "$root/packages/FreeBSD:15:amd64";
        $self->create_package("$apps/All/Hashed", 'pkg', version => '2.6.2_1', origin => 'ports-mgmt/pkg', comment => 'Application bootstrap');
        rename("$apps/All/Hashed/pkg-2.6.2_1.pkg", "$apps/All/Hashed/pkg-2.6.2_1~fixture.pkg") or croak $!;
        $self->create_package("$apps/All/Hashed", 'application');
        $self->{run_pkg}->('repo', $apps);
        make_path("$apps/Latest");
        symlink('../All/pkg-2.6.2_1.pkg', "$apps/Latest/pkg.pkg") or croak $!;
        symlink('FreeBSD:15:amd64', "$root/packages/freebsd:15:x86:64") or croak $!;
    }
    return $root;
}

1;
