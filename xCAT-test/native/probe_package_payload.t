#!/usr/bin/env perl
use strict;
use warnings;
use File::Path qw(make_path);
use File::Slurper qw(read_binary write_text);
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib", "$FindBin::Bin/../../build-utils/lib";
use Test::More;
use XCAT::BuildUtils qw(stage_xcat_probe_sources);
use XCAT::Test::File qw(repo_path slurp_repo_file);
use XCAT::Test::Package qw(run_in);

plan skip_all => 'requires Linux package tools' unless $^O eq 'linux';
BAIL_OUT('run package builds as an unprivileged user') unless $>;
my $root = tempdir(CLEANUP => 1);
make_path(map { "$root/$_" } qw(SOURCES BUILD BUILDROOT RPMS SRPMS SPECS home));
local %ENV = (%ENV, HOME => "$root/home", LC_ALL => 'C');
delete @ENV{qw(PERL5LIB PERL5OPT PERLLIB XCATROOT XCATCFG)};
stage_xcat_probe_sources(repo_path('.'), "$root/SOURCES", '9.9.9', 1600000000);
my @helpers = qw(CommandUtils.pm GlobalDef.pm NetworkUtils.pm ServiceNodeUtils.pm);
my @commands = qw(code_template discovery osdeploy xcatmn);

sub command {
    my ($directory, @args) = @_;
    my ($rc, $out, $err) = run_in($directory, @args);
    unless (is($rc, 0, "$args[0] completes")) {
        diag($out, $err);
        BAIL_OUT("@args failed");
    }
    return $out;
}

command($root, 'rpmbuild', '-bb', '--define', "_topdir $root",
    '--define', 'version 9.9.9', '--define', 'release 1', repo_path('xCAT-probe/xCAT-probe.spec'));
my @rpms = glob("$root/RPMS/noarch/xCAT-probe-*.rpm");
is(scalar(@rpms), 1, 'build produces one probe RPM') or BAIL_OUT('missing probe RPM');
my $requires = command($root, 'rpm', '-qp', '--requires', $rpms[0]);
like($requires, qr/^iproute$/m, 'RPM requires the Linux socket tool provider');
make_path("$root/rpm");
command($root, 'bash', '-o', 'pipefail', '-c',
    'cd "$1" && rpm2cpio "$2" | cpio -idm --quiet', 'bash', "$root/rpm", $rpms[0]);
check_payload("$root/rpm", 'RPM');

sub check_payload {
    my ($destination, $label) = @_;
    my $prefix = "$destination/opt/xcat";
    my $helper_dir = "$prefix/probe/lib/perl/xCAT";
    ok(-x $helper_dir, "$label helper directory is searchable")
        or BAIL_OUT(sprintf('%s has mode %04o', $helper_dir, (stat($helper_dir))[2] & 0777));
    for my $helper (@helpers) {
        my $path = "$prefix/probe/lib/perl/xCAT/$helper";
        ok(-f $path, "$label carries $helper") or BAIL_OUT("missing $path");
        is(read_binary($path), slurp_repo_file("perl-xCAT/xCAT/$helper"),
            "$label carries the canonical $helper bytes");
        is((stat($path))[2] & 0777, 0644, "$label helper is readable without execute permission");
    }
    write_text("$prefix/bin/xcatclient", "#!/bin/sh\nprintf '[ok]:fixture client\\n'\n");
    chmod 0755, "$prefix/bin/xcatclient" or die $!;
    local $ENV{XCATROOT} = $prefix;
    local $ENV{PATH} = "$prefix/bin:$ENV{PATH}";
    for my $name (@commands) {
        my $out = command($root, "$prefix/probe/subcmds/$name", '-T');
        like($out, qr/^\[ok\]\s*:/m, "$label $name self-test is ready");
    }
    my $list = command($root, "$prefix/bin/xcatprobe", '-l');
    like($list, qr/^\Q$_\E\s/m, "$label lists $_") for @commands;
}

done_testing();
