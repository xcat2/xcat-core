#!/usr/bin/env perl
use strict;
use warnings;

use Carp qw(croak);
use Digest::SHA qw(sha256_hex);
use File::Basename qw(dirname);
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use FindBin;
use Test::More;
use Time::HiRes qw(time);

plan skip_all => 'requires a disposable native FreeBSD root'
    unless $^O eq 'freebsd' && $> == 0 && -x '/usr/libexec/flua';

my $source = $ENV{XCAT_FREEBSD_PKGBASE_NATIVE} || '/usr/libexec/bsdinstall/pkgbase';
my $directory = "$FindBin::Bin/../../xCAT-server/share/xcat/install/freebsd";
my $patcher = $ENV{XCAT_FREEBSD_PKGBASE_PATCH} || "$directory/patch-bsdinstall-pkgbase.sh";
my $adapter = $ENV{XCAT_FREEBSD_PKGBASE_ADAPTER} || "$directory/xcat-pkgbase.lua";
my $timer = $ENV{XCAT_FREEBSD_PKGBASE_TIMER} || '/usr/local/libexec/xcat-postscript-time';
my $task = tempdir('xcat-pkgbase-adapter.XXXXXX', TMPDIR => 1, CLEANUP => 1);
my $native_digest = '502e4f8330e06f6c939a074315bf1b70fbd7b68e8f17e91cdaf12147c81ae778';
my @package_fields = qw(id repository name version origin abi repopath path size sha256 native_sum);

sub contents {
    my $path = shift;
    open(my $fh, '<', $path) or croak "$path: $!";
    binmode($fh) or croak "$path: $!";
    local $/ = undef;
    my $bytes = <$fh>;
    close($fh) or croak "$path: $!";
    return defined($bytes) ? $bytes : '';
}

sub write_file {
    my ($path, $bytes, $mode) = @_;
    make_path(dirname($path));
    open(my $fh, '>', $path) or croak "$path: $!";
    binmode($fh) or croak "$path: $!";
    print {$fh} $bytes or croak "$path: $!";
    close($fh) or croak "$path: $!";
    return chmod(defined($mode) ? $mode : oct('0600'), $path) || croak "$path: $!";
}

sub run {
    my @argv = @_;
    open(my $pipe, '-|', '/bin/sh', '-c', 'exec "$@" 2>&1', 'sh', @argv) or croak $!;
    local $/ = undef;
    my $output = <$pipe>;
    close($pipe);
    my $status = $?;
    return (($status & 127) ? 128 + ($status & 127) : $status >> 8, $output // '');
}

sub checked {
    my @argv = @_;
    my ($status, $output) = run(@argv);
    croak "Fixture command failed ($status): @argv\n$output" if $status;
    return $output;
}

sub lua_string {
    my $value = shift;
    $value =~ s/([^A-Za-z0-9_ .:\/-])/sprintf('\\%03d', ord($1))/gex;
    return '"' . $value . '"';
}

sub lua_value {
    my $value = shift;
    return 'nil' unless defined($value);
    return '{' . join(',', map { lua_value($_) } @$value) . '}' if ref($value) eq 'ARRAY';
    return '{' . join(',', map { '[' . lua_string($_) . ']=' . lua_value($value->{$_}) }
        sort keys %$value) . '}' if ref($value) eq 'HASH';
    croak 'Unsupported fixture value' if ref($value);
    return lua_string($value);
}

sub copy_runtime {
    my ($root, @executables) = @_;
    my %files = map { $_ => 1 } ('/libexec/ld-elf.so.1', @executables);
    for my $executable (@executables) {
        my $output = checked('/usr/bin/ldd', $executable);
        while ($output =~ /=>\s+(\/[^\s]+)\s/gx) {
            $files{$1} = 1;
        }
        croak "Unresolved fixture library: $output" if $output =~ /not\ found/x;
    }
    for my $path (sort keys %files) {
        make_path(dirname("$root$path"));
        copy($path, "$root$path") or croak "$path: $!";
        chmod(oct('0755'), "$root$path") or croak "$root$path: $!";
    }
    return;
}

sub package_record {
    my ($number, $name, %overrides) = @_;
    return { id => "p$number", repository => 'r0', name => $name,
        version => '15.1', origin => "base/$name", abi => 'FreeBSD:15:amd64',
        repopath => "All/$name.pkg", path => "base/All/$name.pkg", size => '123',
        sha256 => sha256_hex($name), native_sum => '2$' . sha256_hex($name), %overrides };
}

my $fixture_pkg = <<'SH';
#!/bin/sh
set -eu
printf '%s\0' "$#" "$@" >> /fixture/pkg.argv
/usr/bin/env > /fixture/pkg.environment
IFS= read -r mode < /fixture/mode
lastarg=
for value do lastarg=$value; done
if [ "$lastarg" = -v ]; then
    case "$mode" in
        bad-version) printf '2.8.2\n' ;;
        *) printf '2.6.2\n' ;;
    esac
    exit 0
fi
case "$mode" in
    query) exec /bin/cat /fixture/catalogue ;;
    mutate-adapter) printf '\n-- changed\n' >> /usr/local/libexec/xcat-pkgbase.lua ;;
    mutate-installer) printf '\n-- changed\n' >> /usr/libexec/bsdinstall/pkgbase ;;
    mutate-tool) printf '\n# changed\n' >> '/fixture/pkg client;opaque' ;;
    fail) printf 'fixture catalogue failure\n' >&2; exit 41 ;;
    hang) exec /bin/sleep 90 ;;
    *) printf 'unexpected fixture mode\n' >&2; exit 42 ;;
esac
exec /bin/cat /fixture/catalogue
SH

BAIL_OUT('native pkgbase source does not match the release')
    unless sha256_hex(contents($source)) eq $native_digest;
my $generated = checked('/bin/sh', $patcher, $source);
my $adapter_bytes = contents($adapter);
my $template = "$task/runtime";
make_path($template);
copy_runtime($template, qw(/usr/libexec/flua /bin/sh /bin/cat /bin/sleep
    /usr/bin/env /bin/timeout /usr/bin/stat /sbin/sha256));
write_file("$template/usr/libexec/bsdinstall/pkgbase", $generated, oct('0755'));
write_file("$template/usr/local/libexec/xcat-pkgbase.lua", $adapter_bytes, oct('0644'));
BAIL_OUT('native monotonic helper is unavailable') unless -f $timer && -x $timer;
write_file("$template/usr/local/libexec/xcat-postscript-time", contents($timer), oct('0555'));
write_file("$template/dev/null", '');
my $footprint = checked('/usr/bin/du', '-sk', $template);
my ($template_kib) = $footprint =~ /\A([0-9]+)\s/x;
BAIL_OUT('cannot bound native fixture space') unless defined($template_kib);
diag "Native fixture template: $template_kib KiB; at most 80 private copies";
BAIL_OUT('native fixtures exceed the 700 MiB RAM-root budget') if $template_kib * 80 > 716800;
my $fixture_count = 0;

sub fixture {
    my (%options) = @_;
    BAIL_OUT('native fixture count exceeds its space bound') if ++$fixture_count > 80;
    my $root = tempdir('root.XXXXXX', DIR => $task, CLEANUP => 1);
    checked('/bin/cp', '-a', "$template/.", $root);
    my $tool = '/fixture/pkg client;opaque';
    my %paths = (repository_directory => '/fixture/repos with spaces;opaque',
        database_directory => '/fixture/database', cache_directory => '/fixture/cache');
    make_path(map { "$root$_" } values %paths);
    chmod(oct('0700'), map { "$root$_" } values %paths) or croak $!;
    write_file("$root$tool", $fixture_pkg, oct('0700'));
    write_file("$root/fixture/mode", ($options{mode} || 'query') . "\n");
    my $packages = $options{packages} || [package_record(0, 'FreeBSD-set-minimal'),
        package_record(1, 'FreeBSD-kernel-generic'), package_record(2, 'FreeBSD-ssh'),
        package_record(3, 'FreeBSD-bsdconfig')];
    my $catalogue = $options{catalogue} || $packages;
    write_file("$root/fixture/catalogue", join('', map {
        join("\t", @{$_}{qw(name version origin abi)}) . "\n"
    } @$catalogue));
    my $context = { components => $options{components} || [], packages => $packages,
        plan_sha256 => 'a' x 64, %paths, installer_sha256 => sha256_hex($generated),
        adapter_sha256 => sha256_hex($adapter_bytes),
        tool => { path => $tool, sha256 => sha256_hex($fixture_pkg) } };
    return { root => $root, context => $context };
}

sub invoke {
    my ($fixture, $operation) = @_;
    $operation ||= 'preflight';
    my $driver = <<'LUA';
local api = assert(loadfile('/usr/libexec/bsdinstall/pkgbase'))('xcat-freebsd-pkgbase-selection-api-1')
local function snapshot(value)
    if type(value) ~= 'table' then return type(value) .. ':' .. tostring(value) end
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local result = '{'
    for _, key in ipairs(keys) do result = result .. snapshot(key) .. '=' .. snapshot(value[key]) .. ';' end
    return result .. '}'
end
LUA
    $driver .= 'local context = ' . lua_value($fixture->{context}) . "\n";
    $driver .= "local before = snapshot(context)\n";
    $driver .= 'local ok, result = pcall(api[' . lua_string($operation) . "], context)\n";
    $driver .= <<'LUA';
assert(snapshot(context) == before, 'adapter changed its input records')
if not ok then error(result, 0) end
assert(type(result) == 'string', 'adapter did not return a receipt')
io.write(result)
LUA
    write_file("$fixture->{root}/fixture/driver.lua", $driver);
    local %ENV = (PATH => '/nonexistent', COMPONENTS => 'src tests debug',
        BSDINSTALL_PKG_REPOS_DIR => '/public-fallback', PACKAGESITE => 'https://invalid.example/',
        LC_ALL => 'C');
    return run('/bin/timeout', '-k', '2', '75', '/usr/sbin/chroot', $fixture->{root},
        '/usr/libexec/flua', '/fixture/driver.lua');
}

sub package_calls {
    my ($fixture, $name) = @_;
    $name ||= 'pkg.argv';
    my $path = "$fixture->{root}/fixture/$name";
    return [] unless -e $path;
    my @words = split(/\0/x, contents($path), -1);
    croak 'Unterminated argument log' unless pop(@words) eq '';
    my @calls;
    while (@words) {
        my $count = shift @words;
        croak 'Invalid argument log' if $count !~ /\A[0-9]+\z/x || $count > @words;
        push @calls, [splice(@words, 0, $count)];
    }
    return \@calls;
}

sub receipt_rows {
    my $receipt = shift;
    croak 'Unterminated receipt' unless $receipt =~ /\n\z/x;
    return [map { [split(/\t/x, $_, -1)] } split(/\n/x, $receipt)];
}

sub expected_header {
    my $context = shift;
    return [
        ['format', 'xcat-freebsd-pkgbase-roots-1'],
        ['scope', 'selection-only'],
        ['plan-reference', $context->{plan_sha256}],
        ['native-source', $native_digest],
        ['installer', '/usr/libexec/bsdinstall/pkgbase', $context->{installer_sha256}],
        ['adapter', '/usr/local/libexec/xcat-pkgbase.lua', $context->{adapter_sha256}],
        ['pkg', $context->{tool}{path}, '2.6.2', $context->{tool}{sha256}],
        ['repositories', $context->{repository_directory}],
        ['database', $context->{database_directory}],
        ['cache', $context->{cache_directory}],
    ];
}

sub expected_calls {
    my $context = shift;
    my @common = ('-C', '/dev/null', '--repo-conf-dir', $context->{repository_directory});
    push @common, map { ('-o', $_) } (
        'ABI=FreeBSD:15:amd64', 'OSVERSION=1501000',
        "PKG_DBDIR=$context->{database_directory}", "PKG_CACHEDIR=$context->{cache_directory}",
        'REPO_AUTOUPDATE=false', 'PKG_ENABLE_PLUGINS=false', 'PKG_TRIGGERS_ENABLE=false',
        'RUN_SCRIPTS=false', 'HANDLE_RC_SCRIPTS=false', 'IGNORE_OSVERSION=false',
        'SYSLOG=false', 'CONSERVATIVE_UPGRADE=true');
    return [[@common, '-v'], [@common, 'rquery', '-U', '-r', 'FreeBSD-base', "%n\t%v\t%o\t%q"]];
}

sub selected_records {
    my ($receipt, $packages) = @_;
    my $rows = receipt_rows($receipt);
    my @roots = grep { $_->[0] eq 'root' } @$rows;
    return is_deeply(\@roots, [map { ['root', @{$_}{@package_fields}] } @$packages],
        'receipt retains each selected immutable record in native order');
}

sub succeeds {
    my ($fixture, $packages, $description) = @_;
    my ($status, $receipt) = invoke($fixture);
    if (!is($status, 0, $description || 'real native selector returns a receipt')) {
        diag $receipt;
        return;
    }
    my $rows = receipt_rows($receipt);
    is_deeply([@$rows[0 .. 9]], expected_header($fixture->{context}),
        'receipt identifies selection-only scope, reference and exact runtime inputs');
    my @components = grep { $_->[0] eq 'component' } @$rows;
    is_deeply(\@components, [map { ['component', $_] } @{$fixture->{context}{components}}],
        'receipt preserves explicit component order');
    selected_records($receipt, $packages);
    is(scalar(@$rows), 10 + @components + @$packages, 'receipt contains no other approval records');
    is_deeply(package_calls($fixture), expected_calls($fixture->{context}),
        'exact argv uses one version probe and one explicit read-only base query');
    my %environment = map { split(/=/x, $_, 2) }
        split(/\n/x, contents("$fixture->{root}/fixture/pkg.environment"));
    is($environment{PATH}, '/sbin:/bin:/usr/sbin:/usr/bin', 'package process has the fixed native path');
    is($environment{LC_ALL}, 'C', 'package process has the fixed locale');
    my %allowed = map { $_ => 1 } qw(PATH LC_ALL PWD);
    is_deeply([sort grep { !$allowed{$_} } keys %environment], [],
        'package process receives no inherited repository or component settings');
    ok(!exists($environment{PWD}) || $environment{PWD} eq '/',
        'shell fixture can add only its chroot working directory');
    ok(!-e "$fixture->{root}/fixture/injected", 'shell punctuation executes no extra process');
    return $receipt;
}

sub rejects {
    my ($fixture, $diagnostic, $description) = @_;
    my ($status, $output) = invoke($fixture);
    isnt($status, 0, "$description fails");
    like($output, $diagnostic, "$description reports its rejected condition");
    unlike($output, qr/^format\txcat-freebsd-pkgbase-roots-1$/mx,
        "$description publishes no partial receipt");
    return ($status, $output);
}

subtest 'generator accepts only the pinned native source' => sub {
    is(sha256_hex(contents($source)), $native_digest, 'source is the exact release selector');
    is(checked('/bin/sh', $patcher, $source), $generated, 'generation is deterministic');
    is((run('/usr/libexec/flua', '-e',
        'assert(loadfile(' . lua_string("$template/usr/libexec/bsdinstall/pkgbase") . '))'))[0],
        0, 'generated selector compiles under native flua');
    my $changed = "$task/changed-native";
    write_file($changed, contents($source) . "\n");
    my ($status, $output) = run('/bin/sh', $patcher, $changed);
    isnt($status, 0, 'changed native source is rejected');
    like($output, qr/Unsupported\ FreeBSD\ 15\.1\ pkgbase\ checksum/x, 'changed source reports identity failure');
    unlike($output, qr/^\#!/mx, 'changed source emits no generated script');
    symlink($source, "$task/native-link") or croak $!;
    isnt((run('/bin/sh', $patcher, "$task/native-link"))[0], 0, 'source symlink is rejected');
    done_testing();
};

subtest 'explicit empty components select only mandatory native roots' => sub {
    my $fixture = fixture();
    succeeds($fixture, $fixture->{context}{packages});
    done_testing();
};

subtest 'native optional pkg and selected components retain native order' => sub {
    my @names = qw(FreeBSD-set-minimal FreeBSD-kernel-generic pkg FreeBSD-set-base
        FreeBSD-set-src FreeBSD-set-tests FreeBSD-set-base-dbg FreeBSD-kernel-generic-dbg
        FreeBSD-ssh FreeBSD-bsdconfig);
    my @packages = map { package_record($_, $names[$_]) } 0 .. $#names;
    my $fixture = fixture(packages => \@packages,
        components => [qw(base src tests debug kernel-dbg)]);
    succeeds($fixture, [@packages[0, 2, 1, 3, 6, 4, 5, 7, 8, 9]]);
    done_testing();
};

subtest 'optional debug companions differ from an explicit kernel-dbg request' => sub {
    my @packages = (package_record(0, 'FreeBSD-set-minimal'),
        package_record(1, 'FreeBSD-kernel-generic'), package_record(2, 'FreeBSD-set-src'),
        package_record(3, 'FreeBSD-set-tests'), package_record(4, 'FreeBSD-ssh'),
        package_record(5, 'FreeBSD-bsdconfig'));
    my $fixture = fixture(packages => \@packages, components => [qw(src tests debug)]);
    succeeds($fixture, \@packages);
    my $missing = fixture(packages => \@packages, components => ['kernel-dbg']);
    rejects($missing, qr/Unavailable\ native\ component/x, 'explicit missing kernel symbols');
    is(scalar(@{package_calls($missing)}), 2, 'missing explicit component performs no retry');
    done_testing();
};

subtest 'opaque identities survive without interpreting package names' => sub {
    my $opaque = q{15.1 'quoted';$(touch /fixture/injected)};
    my @packages = (package_record(0, 'FreeBSD-set-minimal', version => $opaque,
            origin => q{base/root "quoted";$(touch /fixture/injected)}),
        package_record(1, 'FreeBSD-kernel-generic'),
        package_record(2, q{application 'name';$(touch /fixture/injected)}, repository => 'r1',
            repopath => 'All/application.pkg', path => 'applications/All/application.pkg'),
        package_record(3, 'FreeBSD-ssh'), package_record(4, 'FreeBSD-bsdconfig'));
    my $fixture = fixture(packages => \@packages);
    succeeds($fixture, [@packages[0, 1, 3, 4]]);
    done_testing();
};

subtest 'overlapping explicit selections produce one immutable root record' => sub {
    my $fixture = fixture(components => [qw(minimal kernel)]);
    succeeds($fixture, $fixture->{context}{packages});
    done_testing();
};

subtest 'repeated selection is deterministic and a plan pin remains only a reference' => sub {
    my $fixture = fixture();
    my ($first_status, $first) = invoke($fixture);
    my ($repeat_status, $repeat) = invoke($fixture);
    is($first_status, 0, 'first preflight succeeds');
    is($repeat_status, 0, 'second preflight succeeds');
    is($repeat, $first, 'same inputs produce the same immutable receipt');
    $fixture->{context}{plan_sha256} = 'b' x 64;
    my ($changed_status, $changed) = invoke($fixture);
    is($changed_status, 0, 'another well-formed plan reference is accepted without claiming plan verification');
    my $expected = $first;
    $expected =~ s/^plan-reference\t[a-f0-9]{64}$/"plan-reference\t" . ('b' x 64)/mex;
    is($changed, $expected, 'only the plan-reference row changes');
    done_testing();
};

subtest 'unconfigured installation entry points refuse before package commands' => sub {
    my $fixture = fixture();
    local %ENV = %ENV;
    delete @ENV{qw(XCAT_WORK BSDINSTALL_CHROOT)};
    my $refusal = qr/Invalid\ installation\ workspace\ or\ target/x;
    my ($status, $output) = run('/bin/timeout', '10', '/usr/sbin/chroot', $fixture->{root},
        '/usr/libexec/flua', '/usr/libexec/bsdinstall/pkgbase', '--non-interactive');
    isnt($status, 0, 'ordinary bsdinstall invocation refuses');
    like($output, $refusal,
        'ordinary invocation requires an installation workspace and target');
    ($status, $output) = invoke($fixture, 'install');
    isnt($status, 0, 'API installation refuses');
    like($output, $refusal,
        'API invocation requires the same installation inputs');
    is_deeply(package_calls($fixture), [], 'refused entry points run no package command');
    done_testing();
};

sub selected_identity_cases {
    for my $field (qw(version origin abi repository)) {
        my $fixture = fixture();
        $fixture->{context}{packages}[0]{$field} = $field eq 'repository' ? 'r1' : 'different';
        $fixture->{context}{packages}[0]{path} = 'applications/All/minimal.pkg'
            if $field eq 'repository';
        rejects($fixture, qr/Native\ root\ (?:identity\ differs|is\ absent)/x, "changed $field");
        is(scalar(@{package_calls($fixture)}), 2, "changed $field uses only the bounded query");
    }
    my $missing = fixture();
    pop @{$missing->{context}{packages}};
    rejects($missing, qr/Native\ root\ is\ absent/x, 'missing selected root');
    for my $name (qw(FreeBSD-ssh FreeBSD-bsdconfig)) {
        my $fixture = fixture();
        my $path = "$fixture->{root}/fixture/catalogue";
        my $bytes = contents($path);
        $bytes =~ s/^\Q$name\E\t[^\n]*\n//mx;
        write_file($path, $bytes);
        rejects($fixture, qr/Native\ root\ is\ absent/x, "missing managed-node package $name");
        is(scalar(@{package_calls($fixture)}), 2, "$name is required without a repository fallback");
    }
    return done_testing();
}
subtest 'selected native identities must match base plan records' => \&selected_identity_cases;

subtest 'invalid context and package records fail before commands' => sub {
    my @cases = (
        ['missing components', sub { delete $_[0]{components} }],
        ['unknown context field', sub { $_[0]{approved} = 'yes' }],
        ['invalid plan reference', sub { $_[0]{plan_sha256} = 'bad' }],
        ['duplicate component', sub { $_[0]{components} = ['src', 'src'] }],
        ['unknown package field', sub { $_[0]{packages}[0]{approved} = 'yes' }],
        ['nonsequential package ID', sub { $_[0]{packages}[0]{id} = 'p4' }],
        ['noncanonical repository ID', sub { $_[0]{packages}[0]{repository} = 'r00' }],
        ['duplicate package name', sub { $_[0]{packages}[1]{name} = $_[0]{packages}[0]{name} }],
        ['identity control character', sub { $_[0]{packages}[0]{origin} = "base/\nname" }],
        ['malformed UTF-8 identity', sub { $_[0]{packages}[0]{version} = pack('C*', 0xc3, 0x28) }],
        ['overlong identity', sub { $_[0]{packages}[0]{version} = 'v' x 1025 }],
        ['package traversal', sub { $_[0]{packages}[0]{path} = '../escape.pkg' }],
        ['invalid archive checksum', sub { $_[0]{packages}[0]{sha256} = 'bad' }],
        ['invalid native checksum', sub { $_[0]{packages}[0]{native_sum} = '2$bad!' }],
        ['noncanonical byte count', sub { $_[0]{packages}[0]{size} = '0123' }],
    );
    for my $case (@cases) {
        my ($name, $change) = @$case;
        my $fixture = fixture();
        $change->($fixture->{context});
        rejects($fixture, qr/xCAT\ pkgbase\ selection:/x, $name);
        is_deeply(package_calls($fixture), [], "$name runs no package command");
    }
    done_testing();
};

subtest 'identity and archive path bounds match the package-plan fields' => sub {
    my $unicode = fixture();
    my $identity = pack('C*', 0xc3, 0xa9) x 1024;
    $unicode->{context}{packages}[0]{version} = $identity;
    write_file("$unicode->{root}/fixture/catalogue", join('', map {
        join("\t", @{$_}{qw(name version origin abi)}) . "\n"
    } @{$unicode->{context}{packages}}));
    succeeds($unicode, $unicode->{context}{packages}, '1024-character Unicode identity is accepted');
    $unicode->{context}{packages}[0]{version} .= pack('C*', 0xc3, 0xa9);
    rejects($unicode, qr/Invalid\ package\ identity/x, '1025-character Unicode identity');

    my $component = fixture();
    $component->{context}{packages}[0]{repopath} = 'All/' . ('r' x 251) . '.pkg';
    $component->{context}{packages}[0]{path} = 'base/' . $component->{context}{packages}[0]{repopath};
    succeeds($component, $component->{context}{packages}, '255-byte archive path component is accepted');
    $component->{context}{packages}[0]{repopath} = 'All/' . ('r' x 252) . '.pkg';
    rejects($component, qr/Invalid\ package\ path\ component/x, '256-byte archive path component');

    my $suffix = join('/', (map { 'd' x 250 } 1 .. 16), ('f' x 76) . '.pkg');
    is(length($suffix), 4096, 'source suffix fixture is exactly 4096 ASCII bytes');
    my $long = fixture();
    $long->{context}{packages}[0]{path} = 'base/' . $suffix;
    succeeds($long, $long->{context}{packages}, '4096-byte source suffix is accepted');
    $long->{context}{packages}[0]{path} .= 'x';
    rejects($long, qr/Invalid\ package\ (?:source\ )?path/x, '4097-byte source suffix');
    done_testing();
};

sub runtime_protection_cases {
    for my $field (qw(installer_sha256 adapter_sha256)) {
        my $fixture = fixture();
        $fixture->{context}{$field} = '0' x 64;
        rejects($fixture, qr/Native\ identity\ checksum\ mismatch/x, "changed $field");
        is_deeply(package_calls($fixture), [], "$field mismatch runs no package command");
    }
    my $tool = fixture();
    $tool->{context}{tool}{sha256} = '0' x 64;
    rejects($tool, qr/Native\ identity\ checksum\ mismatch/x, 'changed tool identity');
    is_deeply(package_calls($tool), [], 'wrong tool digest cannot execute');
    my $default = fixture();
    delete $default->{context}{tool};
    rejects($default, qr/Invalid\ canonical\ path/x, 'missing default static client');
    is_deeply(package_calls($default), [], 'missing static client does not bootstrap');
    my $writable = fixture();
    chmod(oct('0777'), "$writable->{root}$writable->{context}{repository_directory}") or croak $!;
    rejects($writable, qr/Unprotected\ native\ path/x, 'writable repository directory');
    is_deeply(package_calls($writable), [], 'unprotected directory cannot reach pkg');
    my $linked = fixture();
    symlink($linked->{context}{repository_directory}, "$linked->{root}/fixture/repo-link") or croak $!;
    $linked->{context}{repository_directory} = '/fixture/repo-link';
    rejects($linked, qr/Invalid\ canonical\ path/x, 'repository symlink');
    is_deeply(package_calls($linked), [], 'noncanonical directory cannot reach pkg');
    my $parent = fixture();
    chmod(oct('0775'), "$parent->{root}/fixture") or croak $!;
    rejects($parent, qr/Unprotected\ native\ path/x, 'group-writable ancestor');
    is_deeply(package_calls($parent), [], 'writable ancestor cannot reach pkg');
    my $sticky = fixture();
    chmod(oct('01700'), "$sticky->{root}$sticky->{context}{repository_directory}") or croak $!;
    rejects($sticky, qr/Unprotected\ native\ path/x, 'sticky final repository directory');
    is_deeply(package_calls($sticky), [], 'sticky final directory cannot reach pkg');
    my $set_id = fixture();
    chmod(oct('04700'), "$set_id->{root}$set_id->{context}{tool}{path}") or croak $!;
    rejects($set_id, qr/Unprotected\ native\ path/x, 'set-ID package executable');
    is_deeply(package_calls($set_id), [], 'set-ID executable cannot run');
    return done_testing();
}
subtest 'runtime identities and private path protection are enforced' => \&runtime_protection_cases;

subtest 'runtime changes during the catalogue query invalidate the receipt' => sub {
    for my $target (qw(adapter installer tool)) {
        my $fixture = fixture(mode => "mutate-$target");
        rejects($fixture, qr/Native\ identity\ checksum\ mismatch/x, "changed $target after selection");
        is(scalar(@{package_calls($fixture)}), 2, "changed $target performs no package retry");
    }
    done_testing();
};

sub catalogue_failure_cases {
    my %changes = (
        empty => sub { $_[0] = ''; return; },
        unterminated => sub { chop $_[0]; return; },
        duplicate => sub { $_[0] .= $_[0]; return; },
        'bad-fields' => sub { $_[0] = "name\tversion\torigin\n"; return; },
        'bad-utf8' => sub { $_[0] =~ s/^FreeBSD-set-minimal/pack('C*', 0xc3, 0x28)/ex; return; },
        'missing-kernel' => sub { $_[0] =~ s/^FreeBSD-kernel[^\n]*\n//mx; return; },
        'missing-minimal' => sub { $_[0] =~ s/^FreeBSD-set-minimal[^\n]*\n//mx; return; },
    );
    for my $case ('empty', 'unterminated', 'duplicate', 'bad-fields', 'bad-utf8', 'missing-kernel', 'missing-minimal') {
        my $fixture = fixture();
        my $path = "$fixture->{root}/fixture/catalogue";
        my $bytes = contents($path);
        $changes{$case}->($bytes);
        write_file($path, $bytes);
        my $diagnostic = $case =~ /\Amissing-/x
            ? qr/(?:assertion\ failed|nil\ value)/x : qr/xCAT\ pkgbase\ selection:/x;
        rejects($fixture, $diagnostic, $case);
        is(scalar(@{package_calls($fixture)}), 2, "$case does not query another repository");
    }
    return done_testing();
}
subtest 'catalogue ambiguity and incomplete data publish no receipt' => \&catalogue_failure_cases;

sub catalogue_bound_cases {
    my $many = fixture();
    my $catalogue = contents("$many->{root}/fixture/catalogue");
    for my $index (1 .. 99996) {
        $catalogue .= "unselected-$index\t1\tmisc/unselected\tFreeBSD:15:amd64\n";
    }
    cmp_ok(length($catalogue), '<=', 8388608, 'record-limit fixture fits the old byte limit');
    write_file("$many->{root}/fixture/catalogue", $catalogue);
    succeeds($many, $many->{context}{packages}, '100000 catalogue records can supply four selected roots');
    write_file("$many->{root}/fixture/catalogue",
        $catalogue . "unselected-extra\t1\tmisc/unselected\tFreeBSD:15:amd64\n");
    rejects($many, qr/Ambiguous\ native\ catalogue/x, '100001 catalogue records');
    is(scalar(@{package_calls($many)}), 4, 'record overflow adds only one version probe and query');

    my $wide = fixture();
    $catalogue = contents("$wide->{root}/fixture/catalogue");
    my $origin = 'o' x 1024;
    for my $index (1 .. 8188) {
        $catalogue .= "unselected-$index\t1\t$origin\tFreeBSD:15:amd64\n";
        push @{$wide->{context}{packages}}, package_record($index + 3, "unselected-$index");
    }
    cmp_ok(length($catalogue), '>', 8388608, '8192-record fixture exceeds the old byte limit');
    write_file("$wide->{root}/fixture/catalogue", $catalogue);
    succeeds($wide, [@{$wide->{context}{packages}}[0 .. 3]],
        'catalogue above 8 MiB supplies four roots from 8192 plan records');
    push @{$wide->{context}{packages}}, package_record(8192, 'unselected-extra');
    rejects($wide, qr/Invalid\ array/x, '8193 selected-plan records');
    is(scalar(@{package_calls($wide)}), 2, 'selected-plan overflow runs no additional package command');
    return done_testing();
}
subtest 'source catalogue bounds are independent of selected package bounds' => \&catalogue_bound_cases;

subtest 'version, command and output failures are bounded without retry' => sub {
    my $version = fixture(mode => 'bad-version');
    rejects($version, qr/Unsupported\ native\ pkg\ version/x, 'wrong client version');
    is(scalar(@{package_calls($version)}), 1, 'wrong version stops before catalogue query');
    my $failure = fixture(mode => 'fail');
    rejects($failure, qr/Native\ command\ failed\ or\ exceeded\ its\ bound/x, 'catalogue process failure');
    is(scalar(@{package_calls($failure)}), 2, 'failed query has no retry or fallback');
    my $large = fixture();
    write_file("$large->{root}/fixture/catalogue", 'x' x 67108865);
    rejects($large, qr/Native\ command\ failed\ or\ exceeded\ its\ bound/x, 'oversized catalogue output');
    is(scalar(@{package_calls($large)}), 2, 'oversized output has no retry');
    my $hang = fixture(mode => 'hang');
    my $start = time();
    my ($status) = rejects($hang, qr/Native\ command\ failed\ or\ exceeded\ its\ bound/x, 'stalled query');
    cmp_ok(time() - $start, '<', 72, 'adapter command deadline wins before outer fixture timeout');
    isnt($status, 124, 'outer timeout did not produce the failure');
    is(scalar(@{package_calls($hang)}), 2, 'timed-out query has no retry');
    done_testing();
};

sub monotonic_budget_case {
    my ($fixture, $operation, $case, $clock, $native_timer) = @_;
    my $root = $fixture->{root};
    unlink("$root/fixture/pkg.argv", "$root/fixture/clock-first.argv", "$root/fixture/clock.count");
    my $mode = $case->{mode} || 'values';
    my $helper = "$root/usr/local/libexec/xcat-postscript-time";
    write_file($helper, $clock, oct('0555'));
    if ($mode eq 'native') {
        copy($native_timer, $helper) or croak $!;
        chmod(oct('0555'), $helper) or croak $!;
    } elsif ($mode eq 'missing') {
        unlink($helper) or croak $!;
    }
    write_file("$root/fixture/clock.control", 'return ' . lua_value({
        mode => $mode, values => $case->{values} || ["100\n", "101\n"] }) . "\n");
    my $driver = 'local wall = ' . lua_value($case->{wall} || [1000000, 1000001]) . "\n";
    $driver .= <<'LUA';
local reads = 0
os.time = function()
    reads = reads + 1
    return tonumber(wall[math.min(reads, #wall)])
end
local api = assert(loadfile('/usr/libexec/bsdinstall/pkgbase'))('xcat-freebsd-pkgbase-selection-api-1')
LUA
    $driver .= 'local function invoke() return pcall(api.' . $operation
        . ($operation eq 'prepare' ? ', "/clock/work/config", "/clock/work"' : '') . ") end\n";
    $driver .= "local ok, result = invoke()\nio.write(tostring(result), '\\n')\n";
    if ($case->{retry}) {
        $driver .= <<'LUA';
os.rename('/fixture/pkg.argv', '/fixture/clock-first.argv')
local output = assert(io.open('/fixture/clock.control', 'w'))
assert(output:write('return {values={"100\\n","101\\n"}}\n'))
assert(output:close())
os.remove('/fixture/clock.count')
os.time = function() return 1000000 end
local retried, message = invoke()
assert(not retried and tostring(message):find('Invalid installer configuration field', 1, true), tostring(message))
io.write('retry reached configuration validation\n')
LUA
    }
    $driver .= "os.exit(ok and 0 or 1)\n";
    write_file("$root/fixture/clock-driver.lua", $driver);
    local %ENV = (PATH => '/nonexistent', LC_ALL => 'C',
        XCAT_WORK => '/clock/work', BSDINSTALL_CHROOT => '/target');
    my $started = time();
    my ($status, $output) = run('/bin/timeout', '-k', '2', '12', '/usr/sbin/chroot', $root,
        '/usr/libexec/flua', '/fixture/clock-driver.lua');
    is($status, 1, 'public API rejects the controlled invalid input');
    like($output, $case->{error} || qr/Invalid installer configuration field/,
        'rejection occurs at the expected boundary');
    cmp_ok(time() - $started, '<', 10, 'native deadline precedes the outer fixture deadline')
        if $mode eq 'hang';
    my $calls = package_calls($fixture, $case->{retry} ? 'clock-first.argv' : 'pkg.argv');
    my @commands = grep { $_->[3] ne '/usr/local/libexec/xcat-postscript-time' } @$calls;
    if ($case->{error}) {
        is(scalar(@commands), 0, 'clock rejection starts no preparation command');
    } else {
        cmp_ok(scalar(@commands), '>', 0, 'valid monotonic time admits native input validation');
        is_deeply([map { $_->[2] } @commands],
            [map { $case->{seconds} || 60 } @commands], 'every command receives the remaining budget');
    }
    like($output, qr/retry reached configuration validation/, 'failure releases the operation budget')
        if $case->{retry};
    is(contents("$root/clock/work/config"), "invalid\n", 'the input remains unchanged');
    ok(!-e "$root/clock/work/pkgbase", 'rejection creates no preparation state');
    done_testing();
    return;
}

sub monotonic_budget_cases {
    my $fixture = fixture();
    my $root = $fixture->{root};
    copy("$root/bin/timeout", "$root/bin/timeout.real") or croak $!;
    chmod(oct('0755'), "$root/bin/timeout.real") or croak $!;
    write_file("$root/bin/timeout", <<'SH', oct('0555'));
#!/bin/sh
printf '%s\0' "$#" "$@" >> /fixture/pkg.argv
exec /bin/timeout.real "$@"
SH
    make_path("$root/clock/work", "$root/target");
    chmod(oct('0700'), "$root/clock/work") or croak $!;
    write_file("$root/clock/work/config", "invalid\n");
    my $clock = <<'LUA';
#!/usr/libexec/flua
assert(arg[1] == 'uptime' and arg[2] == nil)
local control = dofile('/fixture/clock.control')
if control.mode == 'hang' then os.execute('/bin/sleep 90') end
if control.mode == 'fail' then os.exit(7) end
local input = io.open('/fixture/clock.count', 'r')
local count = input and tonumber(input:read('*a')) or 0
if input then input:close() end
count = count + 1
local output = assert(io.open('/fixture/clock.count', 'w'))
assert(output:write(tostring(count)))
assert(output:close())
io.write(control.values[math.min(count, #control.values)])
LUA
    for my $operation (qw(prepare install)) {
        my $duration = $operation eq 'prepare' ? 1800 : 3600;
        my $remaining = 100 + $duration - 31;
        my @cases = (
            { name => 'steady' },
            { name => 'wall-forward', wall => [1000000, 1004000] },
            { name => 'wall-backward', wall => [1000000, 999700] },
            { name => 'wall-backward-within-budget', seconds => 31,
                wall => [1000000, 1000000 + $duration - 31, 1000000 + $duration - 100],
                values => ["100\n", "$remaining\n"] },
            { name => 'remaining-budget', seconds => 31, values => ["100\n", "$remaining\n"] },
            { name => 'zero-uptime', values => ["0\n", "1\n"] },
            { name => 'largest-uptime', values => ["999999999998\n", "999999999999\n"] },
            { name => 'expired', values => ["100\n", (100 + $duration) . "\n"],
                error => qr/Native operation exceeded its time bound/, retry => 1 },
            { name => 'regressing', values => ["100\n", "99\n"],
                error => qr/Native operation exceeded its time bound/, retry => 1 },
            (map { { name => $_->[0], values => [$_->[1]],
                error => qr/Invalid native monotonic time/ } }
                ['empty', ''], ['leading-zero', "01\n"], ['negative', "-1\n"],
                ['fractional', "1.5\n"], ['unterminated', '1'], ['multiple-lines', "1\n2\n"]),
            { name => 'oversized', values => ["1000000000000\n"],
                error => qr/Native command failed or exceeded its bound/ },
            { name => 'malformed-during-operation', values => ["100\n", "broken\n"],
                error => qr/Invalid native monotonic time/, retry => 1 },
            { name => 'helper-failure', mode => 'fail',
                error => qr/Native command failed or exceeded its bound/ },
            { name => 'helper-missing', mode => 'missing',
                error => qr/Native command failed or exceeded its bound/ },
            { name => 'helper-hang', mode => 'hang',
                error => qr/Native command failed or exceeded its bound/ },
            { name => 'native-helper', mode => 'native', wall => [1000000, 999700] },
        );
        for my $case (@cases) {
            subtest "$operation $case->{name}" => sub {
                monotonic_budget_case($fixture, $operation, $case, $clock, $timer);
            };
        }
    }
    done_testing();
    return;
}

subtest 'prepare and install use bounded monotonic budgets' => \&monotonic_budget_cases;

is(sha256_hex(contents($source)), $native_digest, 'the original native source is unchanged');
is(sha256_hex(contents($adapter)), sha256_hex($adapter_bytes), 'the production adapter input is unchanged');
done_testing();
