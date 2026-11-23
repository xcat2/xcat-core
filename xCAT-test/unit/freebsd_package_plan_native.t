#!/usr/bin/env perl
use strict;
use warnings;

use Carp qw(croak);
use Digest::SHA qw(sha256_hex);
use Encode qw(encode_utf8);
use File::Temp qw(tempdir);
use FindBin;
use JSON::PP;
use Test::More;

plan skip_all => 'requires native FreeBSD flua'
    unless $^O eq 'freebsd' && -x '/usr/libexec/flua';

my $fixtures = $ENV{XCAT_FREEBSD_PLAN_FIXTURES};
BAIL_OUT('Set XCAT_FREEBSD_PLAN_FIXTURES to the controller-generated fixture directory')
    unless defined($fixtures) && -d $fixtures;
my $decoder = $ENV{XCAT_FREEBSD_PLAN_DECODER}
    || "$FindBin::Bin/../../xCAT-server/share/xcat/install/freebsd/xcat-package-plan.lua";
my $task = tempdir('xcat-plan-decoder.XXXXXX', TMPDIR => 1, CLEANUP => 1);

sub read_file {
    my ($path, $limit) = @_;
    croak "Invalid fixture file: $path" if !-f $path || -l $path || -s $path > $limit;
    open(my $fh, '<', $path) or croak "$path: $!";
    binmode($fh) or croak "$path: $!";
    local $/ = undef;
    my $bytes = <$fh>;
    close($fh) or croak "$path: $!";
    croak "Fixture grew: $path" if length($bytes // '') > $limit;
    return $bytes // '';
}

sub write_file {
    my ($path, $bytes) = @_;
    open(my $fh, '>', $path) or croak "$path: $!";
    print {$fh} $bytes or croak "$path: $!";
    close($fh) or croak "$path: $!";
    return;
}

sub lua_string {
    my $value = shift;
    $value =~ s/([^A-Za-z0-9_ .:\/-])/sprintf('\\%03d', ord($1))/gex;
    return '"' . $value . '"';
}

sub run {
    my @argv = @_;
    open(my $pipe, '-|', '/bin/sh', '-c', 'exec "$@" 2>&1', 'sh', @argv) or croak $!;
    binmode($pipe) or croak $!;
    local $/ = undef;
    my $output = <$pipe>;
    close($pipe);
    my $status = $?;
    return (($status & 127) ? 128 + ($status & 127) : $status >> 8, $output // '');
}

sub output_summary {
    my $output = shift;
    return 'Decoder output bytes/SHA256: ' . length($output) . '/' . sha256_hex($output);
}

sub framed {
    my $value = shift;
    return "s\0" . encode_utf8("$value") . "\0" unless ref($value);
    my @keys = ref($value) eq 'ARRAY' ? (1 .. @$value) : sort keys %$value;
    my $result = 't' . "\0" . scalar(@keys) . "\0";
    for my $key (@keys) {
        $result .= (ref($value) eq 'ARRAY' ? 'n' : 's') . "\0" . $key . "\0";
        $result .= framed(ref($value) eq 'ARRAY' ? $value->[$key - 1] : $value->{$key});
    }
    return $result;
}

my $decoder_bytes = read_file($decoder, 1048576);
my $manifest_bytes = read_file("$fixtures/manifest.json", 67108864);
my $manifest = JSON::PP->new->utf8->decode($manifest_bytes);
BAIL_OUT('Unsupported controller fixture manifest') unless ref($manifest) eq 'HASH'
    && $manifest->{format} eq 'xcat-freebsd-plan-fixtures-1'
    && $manifest->{controller_sha256} =~ /\A[0-9a-f]{64}\z/x
    && ref($manifest->{cases}) eq 'ARRAY' && @{$manifest->{cases}};
diag("Controller source SHA256: $manifest->{controller_sha256}");
diag('Decoder SHA256: ' . sha256_hex($decoder_bytes));
diag('Fixture manifest SHA256: ' . sha256_hex($manifest_bytes));

my $driver = <<'LUA';
local decoder = assert(loadfile(arg[1]))()
local input = assert(io.open(arg[2], 'rb'))
local bytes = assert(input:read('*a'))
assert(input:close())
local plan = decoder.parse(bytes)
local function emit(value)
    if type(value) ~= 'table' then
        assert(type(value) == 'string', 'decoded value is not a string')
        io.write('s', '\0', value, '\0')
        return
    end
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys)
    io.write('t', '\0', tostring(#keys), '\0')
    for _, key in ipairs(keys) do
        io.write(type(key) == 'number' and 'n' or 's', '\0', tostring(key), '\0')
        emit(value[key])
    end
end
emit(plan)
LUA
write_file("$task/driver.lua", $driver);

my %names;
sub validate_case {
    my $case = shift;
    BAIL_OUT('Invalid or duplicate controller case') unless ref($case) eq 'HASH'
        && $case->{name} =~ /\A[a-z0-9-]+\z/x
        && $case->{file} =~ /\A[a-z0-9-]+[.]plan\z/x
        && $case->{sha256} =~ /\A[0-9a-f]{64}\z/x
        && ($case->{accepted} eq 'yes' || $case->{accepted} eq 'no');
    BAIL_OUT('Duplicate controller case') if $names{$case->{name}}++;
    return;
}

sub check_case {
    my $case = shift;
    my $path = "$fixtures/$case->{file}";
    my $bytes = read_file($path, 8388609);
    is(sha256_hex($bytes), $case->{sha256}, 'input matches the controller fixture bytes');
    local %ENV = (PATH => '/sbin:/bin:/usr/sbin:/usr/bin', LC_ALL => 'C');
    my ($status, $output) = run('/usr/bin/timeout', '-k', '2', '30',
        '/usr/libexec/flua', "$task/driver.lua", $decoder, $path);
    if ($case->{accepted} eq 'yes') {
        if (is($status, 0, 'native decoder agrees with controller acceptance')) {
            my $expected = framed($case->{expected});
            ok($output eq $expected, 'every decoded field matches the controller object')
                or diag('Actual/expected framed SHA256: ' . sha256_hex($output)
                    . '/' . sha256_hex($expected));
        } else {
            diag(output_summary($output));
        }
    } else {
        isnt($status, 0, 'native decoder agrees with controller rejection');
        isnt($status, 124, 'rejection does not depend on the outer timeout');
        ok(scalar($output =~ qr/FreeBSD[ ]package[ ]plan:/x), 'rejection comes from the production decoder')
            or diag(output_summary($output));
        ok(scalar($output !~ qr/\At\0/x), 'rejected input emits no decoded object')
            or diag(output_summary($output));
    }
    is(sha256_hex(read_file($path, 8388609)), $case->{sha256}, 'decoder leaves the input unchanged');
    done_testing();
    return;
}

for my $case (@{$manifest->{cases}}) {
    validate_case($case);
    subtest $case->{name} => sub { check_case($case); };
}

subtest 'parse argument contract' => sub {
    for my $arguments ('', 'nil', '{}', '42', 'true', "'', nil") {
        my $code = 'local decoder = assert(loadfile(' . lua_string($decoder) . '))();'
            . ' decoder.parse(' . $arguments . ')';
        my ($status, $output) = run('/usr/bin/timeout', '10', '/usr/libexec/flua', '-e', $code);
        isnt($status, 0, "invalid argument list [$arguments] fails");
        ok(scalar($output =~ qr/FreeBSD[ ]package[ ]plan:/x), 'invalid arguments raise a decoder error')
            or diag(output_summary($output));
    }
    done_testing();
};

is(sha256_hex(read_file($decoder, 1048576)), sha256_hex($decoder_bytes), 'decoder source is unchanged');
is(sha256_hex(read_file("$fixtures/manifest.json", 67108864)), sha256_hex($manifest_bytes),
    'controller oracle manifest is unchanged');
done_testing();
