#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib '/opt/xcat/lib/perl';
use File::Path qw(remove_tree);
use File::Slurper qw(read_text write_text);
use JSON::PP qw(decode_json encode_json);
use Test::More;

plan skip_all => 'set XCAT_SYNCFILES_LIVE_CONFIG for a disposable MN/SN/node lab'
  unless $ENV{XCAT_SYNCFILES_LIVE_CONFIG};
require Capture::Tiny;
die 'Run as root on the disposable management node' unless $> == 0;
my $config = decode_json(read_text($ENV{XCAT_SYNCFILES_LIVE_CONFIG}));
my ($node, $service, $work, $cache) = @{$config}{qw(node service work cache)};
die 'Unsafe fixture path' unless $work =~ m{\A/tmp/xcat-syncfiles-[A-Za-z0-9]+\z};
die 'Unsafe cache path' unless $cache =~ m{\A/[A-Za-z0-9/_-]+\z} && $cache ne '/';
for ($node, $service, $config->{management}) { die 'Unsafe host name' unless /\A[A-Za-z0-9][A-Za-z0-9.-]*\z/; }
die 'Fixture hosts must be distinct' if $node eq $service || $node eq $config->{management} || $service eq $config->{management};
for my $key (qw(operator denied ca)) {
    die "Unsafe $key credential path" unless $config->{$key} =~ m{\A/[A-Za-z0-9/_.-]+\z};
}
require xCAT::SvrUtils;
my $lists = xCAT::SvrUtils->getsynclistfile([$node]);
die 'The fixture node must use only the fixture synclist'
  unless $lists->{$node} eq "$work/synclist";

sub command {
    my (@args) = @_;
    my ($out, $err, $status) = Capture::Tiny::capture(sub { system('timeout', '90', @args) });
    die "Command failed (@args): $status\n$out$err" if $status;
    return $out;
}
sub remote {
    my ($host, @args) = @_;
    return command('ssh', '-oBatchMode=yes', "root\@$host", @args);
}
sub copy_to {
    my ($host, $file, $target) = @_;
    command('scp', '-q', $file, "root\@$host:$target");
    return;
}
my %created;
END {
    my $status = $?;
    my $failed = 0;
    for my $host (grep { $_ ne 'local' } keys %created) {
        eval { remote($host, 'rm', '-rf', '--', $work, "$cache$work"); 1 }
          or do { warn "Fixture cleanup failed on $host: $@"; $failed = 1; };
    }
    if ($created{local}) {
        remove_tree($work, {error => \my $errors});
        if (@$errors) { warn "Local fixture cleanup failed\n"; $failed = 1; }
    }
    $? = $status || $failed;
}
die 'Fixture path already exists locally' if -e $work;
for my $host ($node, $service) {
    remote($host, 'test', '!', '-e', $work);
    remote($host, 'test', '!', '-e', "$cache$work");
}
mkdir($work, 0700) or die "Cannot create $work: $!";
$created{local} = 1;
for my $host ($node, $service) {
    remote($host, 'mkdir', '-m', '0755', $work);
    $created{$host} = 1;
    copy_to($host, "$FindBin::Bin/fixtures/syncfiles-request.pl", "$work/request.pl");
}
my $payload = "$work/payload";
my $destination = "$work/delivered/payload";
write_text("$work/synclist", "$payload -> $destination\n");

sub request {
    my ($host, $case) = @_;
    write_text("$work/request.json", encode_json($case));
    copy_to($host, "$work/request.json", "$work/request.json");
    my $out = remote($host, 'perl', '-I/opt/xcat/lib/perl', "$work/request.pl", "$work/request.json");
    return decode_json($out);
}
sub errors {
    my ($responses) = @_;
    my @errors;
    for my $response (@$responses) {
        my $codes = $response->{errorcode};
        $codes = [$codes] unless ref($codes) eq 'ARRAY';
        push @errors, $response if $response->{error} ||
          grep { defined($_) && $_ ne '0' && length($_) } @$codes;
    }
    return \@errors;
}
sub authenticated {
    my ($endpoint, $principal, $request) = @_;
    return request($node, {
        endpoint => "$endpoint:3001", credential => $config->{$principal},
        ca => $config->{ca}, request => $request,
    });
}
sub delivered {
    my ($text, $user) = @_;
    is(remote($node, 'cat', $destination), $text, 'destination has the new payload');
    is(remote($node, 'stat', '-c', '%U', $destination), "$user\n", 'destination ownership matches the copy identity');
    return;
}
sub prepare_destination {
    my ($user) = @_;
    remote($node, 'mkdir', '-p', "$work/delivered");
    remote($node, 'rm', '-f', $destination);
    remote($node, 'chown', $user, "$work/delivered");
    return;
}

subtest 'authenticated node request traverses the MN/SN hierarchy' => sub {
    write_text($payload, "hierarchy payload\n");
    prepare_destination('root');
    my $responses = authenticated($config->{management}, 'operator', {command => ['syncfiles'], arg => [], username => ['denied']});
    is_deeply(errors($responses), [], 'the authorized certificate is accepted despite the supplied username');
    delivered("hierarchy payload\n", 'root');
    is(remote($service, 'cat', "$cache$payload"), "hierarchy payload\n", 'the service node receives the staged payload');
};

subtest 'authenticated node request consumes the service-node cache' => sub {
    write_text($payload, "service cache payload\n");
    copy_to($service, $payload, "$cache$payload");
    prepare_destination('root');
    my $responses = authenticated($service, 'operator', {command => ['syncfiles'], arg => []});
    is_deeply(errors($responses), [], 'the service node accepts the certificate');
    delivered("service cache payload\n", 'root');
};

subtest 'unauthorized certificate cannot trigger a copy' => sub {
    write_text($payload, "must not be delivered\n");
    copy_to($service, $payload, "$cache$payload");
    my $responses = authenticated($service, 'denied', {command => ['syncfiles'], arg => [], username => ['root']});
    my @denials = map { @{$_->{error} || []} } @{errors($responses)};
    ok(scalar(grep { $_ eq 'Permission denied for request' } @denials),
        'authorization rejects the certificate despite the supplied root username');
    delivered("service cache payload\n", 'root');
};

for my $case (
    ['unset', {}, 'root'],
    ['empty', {DSH_FROM_USERID => '', DSH_TO_USERID => ''}, 'root'],
    ['sender only', {DSH_FROM_USERID => 'sender'}, 'sender'],
    ['receiver only', {DSH_TO_USERID => 'receiver'}, 'root'],
    ['both', {DSH_FROM_USERID => 'sender', DSH_TO_USERID => 'receiver'}, 'sender'],
) {
    my ($name, $inherited, $user) = @$case;
    subtest "real copy consumer with $name inherited" => sub {
        my $text = "consumer $name\n";
        write_text($payload, $text);
        copy_to($service, $payload, "$cache$payload");
        prepare_destination($user);
        my $responses = request($service, {
            consumer => 1, inherited => $inherited,
            request => {command => ['syncfiles'], arg => [], _xcat_clienthost => [$node]},
        });
        is_deeply(errors($responses), [], 'the real copy consumer reports no error');
        delivered($text, $user);
    };
}

subtest 'updatenode preserves the authenticated non-root identity across the hierarchy' => sub {
    write_text($payload, "updatenode payload\n");
    prepare_destination('operator');
    my $responses = authenticated($config->{management}, 'operator', {
        command => ['updatenode'], noderange => [$node], arg => ['-F'], username => ['root'],
    });
    is_deeply(errors($responses), [], 'updatenode completes without an earlier error being hidden');
    delivered("updatenode payload\n", 'operator');
};

done_testing();
