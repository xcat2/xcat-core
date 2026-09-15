#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use File::Slurper qw(read_text);
use File::Temp qw(tempdir);
use Storable qw(nstore retrieve);
use Test::More;
use XCAT::Test::File qw(repo_path);

$ENV{XCATROOT} = repo_path('xCAT-server');
my $plugin = repo_path('xCAT-server/lib/xcat/plugins/genimage.pm');
require $plugin;

sub dispatch {
    my ($os, $arch) = @_;
    my $dir = tempdir(CLEANUP => 1);
    my $out = "$dir/command";
    my $pid = fork();
    die "fork: $!" unless defined($pid);
    if (!$pid) {
        my @responses;
        no warnings qw(redefine once);
        local *xCAT::Table::new = sub {
            my ($class, $table) = @_;
            die "Unexpected table $table" unless $table eq 'osimage' || $table eq 'linuximage';
            return bless {}, 'Local::NoImageMutation';
        };
        local *xCAT::TableUtils::getInstallDir = sub { return '/install'; };
        local *xCAT::TableUtils::get_site_attribute = sub { return (); };
        local *xCAT::Utils::runcmd = sub { die 'Dry run attempted to execute an image build'; };
        xCAT_plugin::genimage::process_request({ command => ['genimage'], arg => [
            '-o', $os, '-a', $arch, '-p', 'compute', '--dryrun', '--tempfile', $out,
        ] }, sub { push @responses, @_ }, sub { die 'Dry run attempted a database update'; });
        nstore(\@responses, "$dir/responses");
        exit 0;
    }
    waitpid($pid, 0);
    die "Plugin child failed: $?" if $?;
    return (retrieve("$dir/responses"), -f $out ? read_text($out) : '');
}

for my $os (qw(openeuler20.03sp4 openeuler22.03sp4 openeuler24.03sp1 openeuler24.03sp3 openeuler24.03sp4)) {
    my ($responses, $out) = dispatch($os, 'x86_64');
    ok(!grep({ $_->{error} } @$responses), "$os resolves the native image builder");
    like($out, qr{^cd \Q$ENV{XCATROOT}\E/share/xcat/netboot/openeuler; ./genimage -a x86_64 -o \Q$os\E -p compute\n},
        "$os keeps the exact SP and shared builder entry point");
}
{
    my ($responses, $out) = dispatch('openeuler24.03', 'ppc64le');
    ok(!grep({ $_->{error} } @$responses), 'POWER GA resolves the native image builder');
    like($out, qr{netboot/openeuler; ./genimage -a ppc64le -o openeuler24\.03 -p compute\n},
        'POWER keeps its architecture and GA release');
}
for my $case (['openeuler25.03', 'x86_64'], ['openeuler24.03sp0', 'x86_64'],
    ['openeuler', 'x86_64'], ['openeuler24.03', 'aarch64']) {
    my ($responses, $out) = dispatch(@$case);
    ok(grep({ $_->{error} && $_->{errorcode}[0] == 1 } @$responses), "@$case is rejected");
    is($out, '', 'invalid native image does not produce a build command');
}
for my $case (['rhels9.6', 'rh'], ['rocky9.6', 'rocky'], ['leap15.6', 'sles']) {
    my ($os, $family) = @$case;
    my ($responses, $out) = dispatch($os, 'x86_64');
    ok(!grep({ $_->{error} } @$responses), "$os existing dispatch succeeds");
    like($out, qr{netboot/\Q$family\E; ./genimage -a x86_64 -o \Q$os\E -p compute\n},
        "$os existing family is preserved");
}

done_testing();
