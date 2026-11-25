#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use Cwd qw(getcwd);
use lib "$FindBin::Bin/../lib";
use File::Path qw(make_path);
use File::Slurper qw(read_text write_text);
use File::Temp qw(tempdir);
use Test::More;
use XCAT::Test::File qw(repo_path);
use XCAT::Test::Process qw(run_command);

my $root = tempdir(CLEANUP => 1);
my ($copy_status, $copy_output) = run_command('cp', '-R',
    repo_path('xCAT-server/share/xcat/netboot/imgutils'), "$root/imgutils");
is($copy_status, 0, 'copies the standalone image utility directory') or BAIL_OUT($copy_output);
my $asset = "$root/imgutils/xcat-dump-memory.conf";
my $policy = "[Unit]\nConditionKernelCommandLine=|crashkernel\nConditionKernelCommandLine=|fadump\n";
is(read_text($asset), $policy, 'the standalone copy contains the dump-memory policy');
write_text($asset, $policy . "# site policy fixture\n");
make_path("$root/image/usr/lib/systemd/system", "$root/image/etc/systemd/system/kdump.service.d");
write_text("$root/image/usr/lib/systemd/system/kdump.service", "[Service]\n");
my $dropin = "$root/image/etc/systemd/system/kdump.service.d/xcat-dump-memory.conf";
write_text($dropin, "old policy\n");
chmod oct('0640'), $dropin or die $!;
my @metadata = (stat($dropin))[2, 4, 5];
write_text("$root/apply.pl", <<'PERL');
use strict;
use warnings;
use lib 'imgutils';
use imgutils;
chdir 'image' or die $!;
imgutils::skip_kdump_without_dump_memory('.');
PERL
my @command = ($^X, '-I' . repo_path('perl-xCAT'), '-I' . repo_path('xCAT-server/lib/perl'),
    "$root/apply.pl");
my $previous = getcwd();
chdir($root) or die $!;
for my $pass (1, 2) {
    my ($status, $output) = run_command(@command);
    is($status, 0, "pass $pass runs the copied module after changing directory") or diag($output);
    is(read_text($dropin), $policy . "# site policy fixture\n", 'writes the delivered policy');
    is_deeply([(stat($dropin))[2, 4, 5]], \@metadata, 'preserves the destination metadata');
}
unlink($asset) or die $!;
my ($status, $output) = run_command(@command);
isnt($status, 0, 'fails when a required delivered asset is missing');
like($output, qr/Cannot read .*xcat-dump-memory\.conf/, 'identifies the missing policy');
is(read_text($dropin), $policy . "# site policy fixture\n", 'does not truncate the existing drop-in');
unlink("$root/image/usr/lib/systemd/system/kdump.service") or die $!;
($status, $output) = run_command(@command);
is($status, 0, 'an image without kdump does not need the policy asset') or diag($output);
chdir($previous) or die $!;

done_testing();
