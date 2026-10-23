use strict;
use warnings;
use File::Slurper qw(read_text);
use JSON::PP qw(decode_json encode_json);
use xCAT::Client;

my ($input) = @ARGV;
my $case = decode_json(read_text($input));
my @responses;
my $callback = sub { push @responses, $_[0]; };
delete $ENV{XCATBYPASS};
local $SIG{ALRM} = sub { die "Syncfiles request timed out\n"; };
alarm 60;
if ($case->{consumer}) {
    require xCAT_plugin::syncfiles;
    require xCAT_plugin::xdsh;
    delete @ENV{qw(DSH_FROM_USERID DSH_TO_USERID)};
    @ENV{keys %{$case->{inherited}}} = values %{$case->{inherited}};
    xCAT_plugin::syncfiles::process_request($case->{request}, $callback, sub {
        my ($request, $response) = @_;
        xCAT_plugin::xdsh::preprocess_request($request, $response, sub { die 'Unexpected remote dispatch'; });
    });
} else {
    $ENV{XCATHOST} = $case->{endpoint};
    xCAT::Client::submit_request($case->{request}, $callback,
        $case->{credential}, $case->{credential}, $case->{ca});
}
alarm 0;
print encode_json(\@responses), "\n";
