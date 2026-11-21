#!/usr/bin/env perl
use strict;
use warnings;

use File::Path qw(make_path);
use File::Slurper qw(read_text write_text);
use File::Temp qw(tempdir);
use FindBin;
use Storable qw(dclone);
use Test::More;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use XCAT::Test::File qw(repo_path);

$ENV{XCATROOT} = repo_path('xCAT-server');
my $plugin = repo_path('xCAT-server/lib/xcat/plugins/anaconda.pm');
require $plugin;

sub inspect_media {
    my ($media, @options) = @_;
    my $request = { command => ['copycd'], arg => ['-m', $media, '-i', @options] };
    my $original = dclone($request);
    my (@responses, $output);
    {
        local @ARGV;
        open(my $stdout, '>', \$output) or die "open scalar output: $!";
        local *STDOUT = $stdout;
        no warnings 'redefine';
        local *xCAT::Table::new = sub {
            my ($class, $table, @args) = @_;
            die "Inspection opened writable table $table" if $table ne 'site' || @args;
            return bless {}, 'Local::OpenEulerSite';
        };
        local *xCAT::TableUtils::get_site_attribute = sub { return '/unused-install-root'; };
        xCAT_plugin::anaconda::process_request($request, sub { push @responses, @_ }, sub {
            die 'Inspection dispatched a mutating request';
        });
    }
    is_deeply($request, $original, 'inspection preserves the request for other plugins');
    return \@responses;
}

sub media_tree {
    my ($version, $arch, $extra, $discarch) = @_;
    my $root = tempdir(CLEANUP => 1);
    write_text("$root/.treeinfo", "[general]\nfamily = openEuler\nversion = $version\narch = $arch\n" . ($extra || ''));
    write_text("$root/.discinfo", "1234567890\n\n" . ($discarch || $arch) . "\n");
    return $root;
}

for my $case (
    ['24.03-ppc64le', 'openeuler24.03', 'ppc64le'],
    ['24.03sp4-x86_64', 'openeuler24.03sp4', 'x86_64'],
    ['24.03sp3-riscv64', 'openeuler24.03sp3', 'riscv64'],
) {
    my ($fixture, $os, $arch) = @$case;
    my $responses = inspect_media(repo_path("xCAT-test/fixtures/openeuler-media/$fixture"));
    is(scalar(@$responses), 1, "$fixture returns one inspection result");
    like($responses->[0]{info} || '', qr/^DISTNAME:\Q$os\E\nARCH:\Q$arch\E\n/,
        "$fixture retains the exact release and architecture");
}

for my $case (['20.03-LTS-SP4', '20.03sp4'], ['22.03-LTS-SP4', '22.03sp4'],
              ['24.03-LTS-SP1', '24.03sp1'], ['24.03-LTS-SP3', '24.03sp3']) {
    my ($version, $os) = @$case;
    my $responses = inspect_media(media_tree($version, 'x86_64'));
    like($responses->[0]{info} || '', qr/^DISTNAME:openeuler\Q$os\E\n/,
        "$version keeps its service pack");
}

my $media = media_tree('24.03-LTS-SP4', 'x86_64');
my $responses = inspect_media($media, '-a', 'ppc64le');
like($responses->[0]{error} || '', qr/Requested distribution architecture ppc64le, but media is x86_64/,
    'an explicit architecture mismatch is rejected');
is_deeply($responses->[0]{errorcode}, [1], 'an architecture mismatch reports failure');

$responses = inspect_media($media, '-n', 'openeuler24.03sp4', '-p', '/custom/media');
like($responses->[0]{info} || '', qr/^DISTNAME:openeuler24\.03sp4\nARCH:x86_64\n/,
    'an explicit distro and custom destination remain observational');

for my $case (
    ['25.03-LTS', 'x86_64', '', 'Unsupported openEuler LTS version'],
    ['24.09', 'x86_64', '', 'Unsupported openEuler LTS version'],
    ['', 'x86_64', '', 'Unsupported openEuler LTS version'],
    ['24.03-LTS-SP4', 'aarch64', '', 'Unsupported openEuler architecture'],
    ['24.03-LTS-SP4', 'x86_64', "version = 22.03-LTS-SP4\n", 'Duplicate openEuler media identity'],
    ['24.03-LTS-SP4', 'x86_64', "family = Rocky Linux\n", 'Duplicate openEuler media identity'],
) {
    my ($version, $arch, $extra, $error) = @$case;
    $responses = inspect_media(media_tree($version, $arch, $extra));
    like($responses->[0]{error} || '', qr/\Q$error\E/, "$version/$arch is rejected explicitly");
    is_deeply($responses->[0]{errorcode}, [1], 'invalid metadata reports failure');
}

$responses = inspect_media(media_tree('24.03-LTS-SP4', 'x86_64', '', 'ppc64le'));
like($responses->[0]{error} || '', qr/Conflicting openEuler media architectures/,
    'conflicting discinfo and treeinfo architectures are rejected');

my $tree_only = media_tree('24.03-LTS-SP4', 'x86_64');
unlink "$tree_only/.discinfo" or die "unlink discinfo: $!";
$responses = inspect_media($tree_only);
like($responses->[0]{info} || '', qr/^DISTNAME:openeuler24\.03sp4\nARCH:x86_64\n/,
    'treeinfo identifies media without discinfo');

my $other = tempdir(CLEANUP => 1);
write_text("$other/.treeinfo", "[general]\nfamily = Rocky Linux\nversion = 9.6\narch = x86_64\n");
write_text("$other/.discinfo", "1234567890\nRocky Linux 9.6\nx86_64\n1\n");
$responses = inspect_media($other);
like($responses->[0]{info} || '', qr/^DISTNAME:rocky9\.6\nARCH:x86_64\n/,
    'existing Rocky media detection is preserved');
$responses = inspect_media($other, '-n', 'openeuler24.03');
like($responses->[0]{error} || '', qr/openEuler media requires an openEuler .treeinfo identity/,
    'a requested openEuler name cannot relabel foreign media');

is(xCAT_plugin::anaconda::getplatform('openeuler24.03sp4'), 'openeuler',
    'openEuler resolves its native template platform');
ok(xCAT_plugin::anaconda::using_dracut('openeuler20.03sp4'), 'openEuler 20.03 uses dracut');
ok(xCAT_plugin::anaconda::using_dracut('openeuler24.03'), 'POWER GA uses dracut');
ok(!xCAT_plugin::anaconda::using_dracut('openeuler24.09'), 'a non-LTS token is not admitted');

{
    my $request = { command => ['copycd'], arg => ['-m', $media] };
    my $original = dclone($request);
    my @responses;
    my $output;
    {
        open(my $stdout, '>', \$output) or die "open scalar output: $!";
        local *STDOUT = $stdout;
        no warnings 'redefine';
        local *xCAT::Table::new = sub {
            my ($class, $table, @args) = @_;
            die "Incomplete media opened writable table $table" if $table ne 'site' || @args;
            return bless {}, 'Local::OpenEulerSite';
        };
        local *xCAT::TableUtils::get_site_attribute = sub { return '/unused-install-root'; };
        xCAT_plugin::anaconda::process_request($request, sub { push @responses, @_ }, sub {
            die 'Incomplete media dispatched a mutating request';
        });
    }
    like($responses[0]{error} || '', qr/Incomplete openEuler installation media:/,
        'metadata-only media cannot be imported');
    is_deeply($responses[0]{errorcode}, [1], 'missing payload reports failure');
    is_deeply($request, $original, 'missing payload is rejected before claiming or changing media');
}

# Complete riscv64 media whose .discinfo names a build, as the RVA23 DVD does.
sub build_media {
    my ($description, $arch) = @_;
    $arch ||= 'riscv64';
    my $root = media_tree('24.03-LTS-SP3', $arch, '', $arch);
    write_text("$root/.discinfo", "1234567890\n$description\n$arch\n");
    make_path("$root/images/pxeboot", "$root/repodata");
    write_text("$root/$_", "payload\n")
      for qw(images/pxeboot/vmlinuz images/pxeboot/initrd.img images/install.img repodata/repomd.xml);
    return $root;
}

# Copies media to $target. The table stub stops a copy that passes the build
# check at its first table, before anything is written.
sub copy_media {
    my ($media, $target) = @_;
    my $request = { command => ['copycd'], arg => ['-m', $media, '-p', $target] };
    my (@responses, $output, $stopped);
    {
        open(my $stdout, '>', \$output) or die "open scalar output: $!";
        local *STDOUT = $stdout;
        no warnings 'redefine';
        local *xCAT::Table::new = sub {
            my ($class, $table, @args) = @_;
            die "copy reached table $table\n" if $table ne 'site' || @args;
            return bless {}, 'Local::OpenEulerSite';
        };
        local *xCAT::TableUtils::get_site_attribute = sub { return '/unused-install-root'; };
        eval {
            xCAT_plugin::anaconda::process_request($request, sub { push @responses, @_ }, sub {
                die "copy dispatched a request\n";
            });
            1;
        } or $stopped = $@;
    }
    return (\@responses, $stopped);
}

sub copied_target {
    my ($description) = @_;
    my $target = tempdir(CLEANUP => 1);
    write_text("$target/.discinfo", "1234567800\n$description\nriscv64\n") if defined $description;
    return $target;
}

for my $case (['RVA23', '', 'RVA23'], ['', 'RVA23', 'no build name']) {
    my ($copied, $media, $named) = @$case;
    my $target = copied_target($copied);
    my ($responses, $stopped) = copy_media(build_media($media), $target);
    like($responses->[0]{error} || '', qr/\Q$target\E holds openEuler media of another build \(\Q$named\E\)/,
        "media of build '$media' are refused over a copy of build '$copied'");
    is_deeply($responses->[0]{errorcode}, [1], 'the refusal reports failure');
    is($stopped, undef, 'the refusal comes before any table is opened');
    is(read_text("$target/.discinfo"), "1234567800\n$copied\nriscv64\n", 'the existing copy is unchanged');
}

for my $case (['RVA23', 'RVA23', 'riscv64'], ['rva23', 'RVA23', 'riscv64'], [undef, 'RVA23', 'riscv64'],
              ['', '', 'x86_64']) {
    my ($copied, $media, $arch) = @$case;
    my $label = defined $copied ? "a copy of build '$copied'" : 'an empty target';
    my ($responses, $stopped) = copy_media(build_media($media, $arch), copied_target($copied));
    ok(!grep({ ($_->{error} // '') =~ /another build/ } @$responses), "$arch media of build '$media' copy over $label");
    is($stopped, "copy reached table osdistro\n", 'the copy continues past the build check');
}

done_testing();
