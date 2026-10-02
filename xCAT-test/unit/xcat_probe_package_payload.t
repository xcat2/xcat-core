#!/usr/bin/env perl
use strict;
use warnings;

use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Slurper qw(write_text);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../build-utils/lib";
use Test::More;

use XCAT::BuildUtils qw(XCAT_PROBE_HELPERS stage_probe_helpers);
use XCAT::Test::File qw(repo_path slurp_repo_file);

my @helpers = qw(
    CommandUtils.pm
    GlobalDef.pm
    NetworkUtils.pm
    ServiceNodeUtils.pm
);
my @affected_subcommands = qw(
    code_template
    discovery
    osdeploy
    xcatmn
);

# How buildrpms.pl stages the xCAT-probe sources is asserted by
# xcat_probe_sources_staged.t, which runs the staging and reads the archive. Seven assertions
# here matched the text of buildrpms.pl instead, and four of them could not fail: three matched
# the xCAT-release routine, which stages the same way, and one spanned the rest of the file. All
# seven stayed green while the staging directory was unset and every RPM target died.
my $installed_probe_test =
  slurp_repo_file('xCAT-test/autotest/testcase/probe/xcatproble_list');
my $rpm_spec = slurp_repo_file('xCAT-probe/xCAT-probe.spec');
my $debian_control = slurp_repo_file('xCAT-probe/debian/control');
like(
    $rpm_spec,
    qr/%if 0%\{\?suse_version\}\s+Requires: iproute2\s+%else\s+Requires: iproute\s+%endif/s,
    'RPM package requires the distro-specific provider of ss'
);
like(
    $debian_control,
    qr/^Depends:.*\biproute2\s*\|\s*net-tools\b/m,
    'Debian package requires ss or the legacy netstat provider'
);

# The Debian builder stages the helpers by calling stage_probe_helpers, so run it and
# look at what it produced. The predecessor matched a `cp -f` line in build-ubunturepo,
# which passed whenever that text was reformatted and failed whenever it moved.
my $staged_probe_dir = File::Spec->catdir(tempdir(CLEANUP => 1), 'lib', 'perl', 'xCAT');
stage_probe_helpers(repo_path(File::Spec->catdir('perl-xCAT', 'xCAT')), $staged_probe_dir);

for my $helper (@helpers) {
    my $source = repo_path(File::Spec->catfile('perl-xCAT', 'xCAT', $helper));
    ok(-f $source, "$helper source exists");
    ok(
        scalar(grep { $_ eq $helper } XCAT_PROBE_HELPERS),
        "the shared builder helper list carries $helper"
    );
    ok(
        -f File::Spec->catfile($staged_probe_dir, $helper),
        "Debian builder stages $helper"
    );
    like(
        $installed_probe_test,
        qr/cmd:for module in [^;]*\b\Q$helper\E\b[^;]*; do test -r/,
        "installed probe payload checks $helper"
    );
}

my $tmpdir = tempdir(CLEANUP => 1);
my $xcatroot = File::Spec->catdir($tmpdir, 'opt', 'xcat');
my $probe_root = File::Spec->catdir($xcatroot, 'probe');
my $bin_dir = File::Spec->catdir($xcatroot, 'bin');
my $subcmd_dir = File::Spec->catdir($probe_root, 'subcmds');
my $helper_dir = File::Spec->catdir($probe_root, 'lib', 'perl', 'xCAT');

make_path($probe_root, $bin_dir);
copy_tree(repo_path(File::Spec->catdir('xCAT-probe', 'lib')), File::Spec->catdir($probe_root, 'lib'));
copy_tree(repo_path(File::Spec->catdir('xCAT-probe', 'subcmds')), $subcmd_dir);

my $xcatprobe_source = repo_path(File::Spec->catfile('xCAT-probe', 'xcatprobe'));
my $xcatprobe = File::Spec->catfile($bin_dir, 'xcatprobe');
copy($xcatprobe_source, $xcatprobe) or die "copy $xcatprobe_source: $!";
chmod 0755, $xcatprobe or die "chmod $xcatprobe: $!";

make_path($helper_dir, File::Spec->catdir($subcmd_dir, 'bin'));
for my $helper (@helpers) {
    my $source = repo_path(File::Spec->catfile('perl-xCAT', 'xCAT', $helper));
    my $destination = File::Spec->catfile($helper_dir, $helper);
    copy($source, $destination) or die "copy $source: $!";
    chmod 0644, $destination or die "chmod $destination: $!";
}

my $xcatclient = File::Spec->catfile($bin_dir, 'xcatclient');
write_text($xcatclient, "#!/bin/sh\nprintf '[ok]:dummy xcatclient\\n'\n");
chmod 0755, $xcatclient or die "chmod $xcatclient: $!";

local $ENV{XCATROOT} = $xcatroot;
local $ENV{PATH} = "$bin_dir:$ENV{PATH}";
local $ENV{PERL5LIB};
local $ENV{PERL5OPT};
local $ENV{PERLLIB};
delete $ENV{PERL5LIB};
delete $ENV{PERL5OPT};
delete $ENV{PERLLIB};

for my $subcommand (@affected_subcommands) {
    my $command = File::Spec->catfile($subcmd_dir, $subcommand);
    my ($rc, $output) = run_command($command, '-T');
    is($rc, 0, "$subcommand self-test exits successfully") or diag($output);
    like($output, qr/^\[ok\]\s*:/m, "$subcommand self-test reports ready");
}

my ($list_rc, $list_output) = run_command($xcatprobe, '-l');
is($list_rc, 0, 'xcatprobe list exits successfully') or diag($list_output);
my %listed = map { /^([^\s].*?)\s/ ? ($1 => 1) : () } split /\n/, $list_output;
for my $subcommand (@affected_subcommands) {
    ok($listed{$subcommand}, "xcatprobe lists $subcommand") or diag($list_output);
}

done_testing();

sub copy_tree {
    my ($source, $destination) = @_;
    my $rc = system('cp', '-R', $source, $destination);
    is($rc, 0, "copied $source into the package fixture")
        or die("unable to create package fixture from $source");
}

sub run_command {
    my (@command) = @_;
    open(my $fh, '-|', @command) or die "run @command: $!";
    my $output = do { local $/; <$fh> };
    close($fh);
    return ($? >> 8, $output // '');
}
