#!/usr/bin/env perl
use strict;
use warnings;

use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

my $repo_root = File::Spec->rel2abs(File::Spec->catdir($FindBin::Bin, '..', '..'));
my @helpers = qw(
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

my $builder = read_file('buildrpms.pl');
like($builder, qr/sub prepare_xcat_probe_source_tar\b/, 'RPM builder has dedicated xCAT-probe source preparation');
like(
    $builder,
    qr/for my \$helper \(\@XCAT_PROBE_HELPERS\).*?cp "perl-xCAT\/xCAT\/\$helper", \$destination;/s,
    'RPM builder copies every declared helper into the staged package tree'
);
like($builder, qr/tempfile\(.*?DIR\s*=>\s*\$SOURCES/s, 'RPM builder writes a unique archive in the source directory');
like($builder, qr/--use-compress-program="gzip -n"/, 'RPM builder normalizes gzip metadata');
like($builder, qr/rename\s+\$archive_path,\s*\$source_tarball/, 'RPM builder publishes the source archive atomically');
like(
    $builder,
    qr/elsif \(\$pkg eq "xCAT-probe"\)\s*\{.*?\breturn;/s,
    'target workers reuse the source archive prepared before the fork'
);

my $prepare_call = rindex($builder, 'prepare_xcat_probe_source_tar()');
my $worker_fanout = index($builder, 'Parallel::ForkManager->new');
ok(
    $prepare_call >= 0 && $worker_fanout >= 0 && $prepare_call < $worker_fanout,
    'xCAT-probe source preparation runs before worker processes fork'
);

for my $helper (@helpers) {
    my $source = File::Spec->catfile($repo_root, 'perl-xCAT', 'xCAT', $helper);
    ok(-f $source, "$helper source exists");
    like($builder, qr/^\s*\Q$helper\E\s*$/m, "RPM builder stages $helper");
}

my $tmpdir = tempdir(CLEANUP => 1);
my $xcatroot = File::Spec->catdir($tmpdir, 'opt', 'xcat');
my $probe_root = File::Spec->catdir($xcatroot, 'probe');
my $bin_dir = File::Spec->catdir($xcatroot, 'bin');
my $subcmd_dir = File::Spec->catdir($probe_root, 'subcmds');
my $helper_dir = File::Spec->catdir($probe_root, 'lib', 'perl', 'xCAT');

make_path($probe_root, $bin_dir);
copy_tree(File::Spec->catdir($repo_root, 'xCAT-probe', 'lib'), File::Spec->catdir($probe_root, 'lib'));
copy_tree(File::Spec->catdir($repo_root, 'xCAT-probe', 'subcmds'), $subcmd_dir);

my $xcatprobe_source = File::Spec->catfile($repo_root, 'xCAT-probe', 'xcatprobe');
my $xcatprobe = File::Spec->catfile($bin_dir, 'xcatprobe');
copy($xcatprobe_source, $xcatprobe) or die "copy $xcatprobe_source: $!";
chmod 0755, $xcatprobe or die "chmod $xcatprobe: $!";

make_path($helper_dir, File::Spec->catdir($subcmd_dir, 'bin'));
for my $helper (@helpers) {
    my $source = File::Spec->catfile($repo_root, 'perl-xCAT', 'xCAT', $helper);
    my $destination = File::Spec->catfile($helper_dir, $helper);
    copy($source, $destination) or die "copy $source: $!";
    chmod 0644, $destination or die "chmod $destination: $!";
}

my $xcatclient = File::Spec->catfile($bin_dir, 'xcatclient');
write_file($xcatclient, "#!/bin/sh\nprintf '[ok]:dummy xcatclient\\n'\n");
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

sub read_file {
    my ($file) = @_;
    my $path = File::Spec->catfile($repo_root, $file);

    open(my $fh, '<', $path) or die "open $path: $!";
    my $contents = do { local $/; <$fh> };
    close($fh) or die "close $path: $!";
    return $contents;
}

sub copy_tree {
    my ($source, $destination) = @_;
    my $rc = system('cp', '-R', $source, $destination);
    is($rc, 0, "copied $source into the package fixture")
        or BAIL_OUT("unable to create package fixture from $source");
}

sub run_command {
    my (@command) = @_;
    open(my $fh, '-|', @command) or die "run @command: $!";
    my $output = do { local $/; <$fh> };
    close($fh);
    return ($? >> 8, $output // '');
}

sub write_file {
    my ($path, $contents) = @_;
    open(my $fh, '>', $path) or die "open $path: $!";
    print {$fh} $contents;
    close($fh) or die "close $path: $!";
}
