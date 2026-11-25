#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../build-utils/lib", "$FindBin::Bin/../lib";
use File::Slurper qw(read_text write_text);
use File::Temp qw(tempdir);
use Test::More;
use XCAT::BuildUtils qw(generated_policy_plan sync_generated_policy);
use XCAT::Test::Process qw(run_command);

my $root = tempdir(CLEANUP => 1);
my %options = (root => $root, source => 'policy.sh', label => 'fixture',
    command => 'sync-fixture', artifacts => ['consumer.sh']);
my $begin = "# BEGIN generated fixture policy: sync-fixture --write\n";
my $end = "# END generated fixture policy\n";
write_text("$root/policy.sh", "policy() { printf '%s' new; }\n");
my $original = "#!/bin/sh\n$begin" . "policy() { printf '%s' old; }\n$end" . "policy\n";
write_text("$root/consumer.sh", $original);
chmod oct('0750'), "$root/consumer.sh" or die $!;
my $plan = generated_policy_plan(%options);
is_deeply([map { $_->{relative} } @{$plan->{artifacts}}], ['consumer.sh'], 'plans the requested artifact');
is(read_text("$root/consumer.sh"), $original, 'planning leaves the consumer unchanged');
my $check = sync_generated_policy(%options, mode => 'check');
is_deeply($check->{stale}, ['consumer.sh'], 'check finds a stale consumer');
is_deeply($check->{written}, [], 'check writes nothing');
is_deeply($check->{messages}, ['consumer.sh is out of date; run sync-fixture --write'],
    'diagnostic names the policy-specific repair command');
my $write = sync_generated_policy(%options, mode => 'write');
is_deeply($write->{written}, ['consumer.sh'], 'regenerates the consumer');
my ($status, $output) = run_command('/bin/sh', "$root/consumer.sh");
is($status, 0, 'executes the regenerated consumer');
is($output, 'new', 'the consumer uses the new policy');
is((stat("$root/consumer.sh"))[2] & oct('0777'), oct('0750'), 'retains its mode');
is_deeply(sync_generated_policy(%options, mode => 'write')->{written}, [],
    'a repeated write changes nothing');

write_text("$root/policy.sh", "policy() { printf '%s' newer; }\n");
write_text("$root/broken.sh", "#!/bin/sh\n$end$begin");
my $before = read_text("$root/consumer.sh");
for my $mode (qw(check write)) {
    my $result = eval { sync_generated_policy(%options, mode => $mode,
        artifacts => ['consumer.sh', 'broken.sh']) };
    is($result, undef, "$mode rejects malformed markers in a later artifact");
    like($@, qr/broken\.sh must contain one fixture policy block/, 'identifies the malformed artifact');
    is(read_text("$root/consumer.sh"), $before, 'leaves the earlier stale consumer unchanged');
}

done_testing();
