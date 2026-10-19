use strict;
use warnings;
use File::Copy qw(copy);
use File::Slurper qw(read_text write_text);
use IO::Socket::INET;
use JSON::PP qw(decode_json encode_json);
use POSIX qw(_exit);

alarm 90;
my $commands = decode_json(read_text('/fixture/commands.json'));
copy('/fixture/autoinstall.yaml', '/autoinstall.yaml') or die $!;
my $listener = IO::Socket::INET->new(
    LocalAddr => '127.0.0.1', LocalPort => 3002, Listen => 1, ReuseAddr => 1,
) or die "Cannot start install monitor: $!";
my $pid = fork();
die "fork: $!" unless defined $pid;
if (!$pid) {
    alarm 60;
    my $client = $listener->accept() or _exit(1);
    $client->autoflush(1);
    print {$client} "ready\n";
    my $request = <$client>;
    write_text('/fixture/monitor-request', $request // '');
    print {$client} "done\n" if defined($request) && $request eq "next\n";
    close($client);
    _exit(0);
}
close($listener);
my @statuses;
my $status = 0;
for my $phase (qw(early-commands late-commands)) {
    for my $command (@{$commands->{$phase}}) {
        my @arguments = ref($command) eq 'ARRAY' ? @$command : ('/bin/sh', '-c', $command);
        system(@arguments);
        $status = $? == -1 ? 255 : $? & 127 ? 128 + ($? & 127) : $? >> 8;
        push @statuses, [$phase, $status];
        last if $status;
    }
    last if $status;
}
kill 'TERM', $pid if $status;
waitpid($pid, 0);
write_text('/fixture/monitor-status', "$?\n");
write_text('/fixture/statuses.json', encode_json(\@statuses));
copy('/autoinstall.yaml', '/fixture/final-autoinstall.yaml') or die $!;
exit $status;
