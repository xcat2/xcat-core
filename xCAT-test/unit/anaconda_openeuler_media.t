#!/usr/bin/env perl
use strict;
use warnings;

use File::Slurper qw(write_text);
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
) {
    my ($fixture, $os, $arch) = @$case;
    my $responses = inspect_media(repo_path("xCAT-test/fixtures/openeuler-media/$fixture"));
    is(scalar(@$responses), 1, "$fixture returns one inspection result");
    like($responses->[0]{info} || '', qr/^DISTNAME:\Q$os\E\nARCH:\Q$arch\E\n/,
        "$fixture retains the exact release and architecture");
}

for my $version ('20.03-LTS-SP4', '22.03-LTS-SP4', '24.03-LTS-SP1', '24.03-LTS-SP3') {
    (my $os = lc($version)) =~ s/-lts//;
    $os =~ s/-sp/sp/;
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

done_testing();
