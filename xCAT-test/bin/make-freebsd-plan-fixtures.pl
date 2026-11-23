#!/usr/bin/env perl
use strict;
use warnings;
use Carp qw(croak);
use Cwd qw(abs_path);
use Digest::SHA qw(sha256_hex);
use Encode qw(encode_utf8);
use File::Basename qw(dirname);
use File::Path qw(make_path);
use JSON::PP;

croak "Linux fixture generation only\n" unless $^O eq 'linux';
my ($source, $output) = @ARGV;
croak "Usage: make-freebsd-plan-fixtures.pl source empty-output-directory\n"
    unless @ARGV == 2 && -d $source && -d $output;
$source = abs_path($source);
$output = abs_path($output);
opendir(my $dh, $output) or croak $!;
my @old = grep { $_ ne '.' && $_ ne '..' } readdir($dh);
closedir($dh) or croak $!;
croak "Output directory must be empty\n" if @old;
unshift @INC, "$source/xCAT-test/lib", "$source/xCAT-server/lib/perl", "$source/perl-xCAT";
require xCAT::FreeBSDPackagePlan;
require xCAT::FreeBSDRepo;
require xCAT::FreeBSDRepoImport;
require xCAT::FreeBSDPkg;
require XCAT::Test::FreeBSDRepoFixture;

my $json = JSON::PP->new->utf8->canonical;
my $work = "$output/build";
make_path("$work/empty", "$work/repos");
my $native = abs_path($ENV{XCAT_FREEBSD_NATIVE_PKG} || croak 'Missing native pkg path');
my $libraries = abs_path($ENV{XCAT_FREEBSD_NATIVE_LIBDIR} || croak 'Missing native library directory');
my %environment = (PATH => '/usr/bin:/bin', LC_ALL => 'C', LD_LIBRARY_PATH => $libraries);

sub read_file {
    my $path = shift;
    open(my $fh, '<', $path) or croak "$path: $!";
    binmode($fh) or croak $!;
    local $/ = undef;
    my $bytes = <$fh>;
    close($fh) or croak $!;
    return $bytes // '';
}

sub write_file {
    my ($path, $bytes) = @_;
    make_path(dirname($path));
    open(my $fh, '>', $path) or croak "$path: $!";
    binmode($fh) or croak $!;
    print {$fh} $bytes or croak $!;
    close($fh) or croak $!;
    return;
}

sub command {
    my @argv = @_;
    my $result = xCAT::FreeBSDPkg::run_command(\@argv, cwd => $work,
        environment => \%environment, timeout => 60, stdout_limit => 67108864);
    croak "Fixture command failed: $result->{stderr}" if $result->{exitcode} || $result->{signal};
    return $result->{stdout};
}

my $tool = {path => $native, sha256 => sha256_hex(read_file($native)),
    library_directory => $libraries, library_digest => xCAT::FreeBSDRepo::snapshot_tree($libraries)->{digest}};
my $controller_path = "$source/xCAT-server/lib/perl/xCAT/FreeBSDPackagePlan.pm";
my $controller_sha = sha256_hex(read_file($controller_path));
write_file("$work/pkg.conf", $json->encode({ABI => 'FreeBSD:15:amd64', OSVERSION => 1501000,
    PKG_DBDIR => "$work/db", PKG_CACHEDIR => "$work/cache", REPOS_DIR => ["$work/repos"],
    REPO_AUTOUPDATE => JSON::PP::false, PKG_ENABLE_PLUGINS => JSON::PP::false,
    PKG_TRIGGERS_ENABLE => JSON::PP::false, RUN_SCRIPTS => JSON::PP::false,
    HANDLE_RC_SCRIPTS => JSON::PP::false, SYSLOG => JSON::PP::false}));
sub run_pkg {
    my @arguments = @_;
    return command($native, '-C', "$work/pkg.conf", @arguments);
}
croak 'Unexpected native pkg version' unless run_pkg('-v') eq "2.8.2\n";
my $fixture = XCAT::Test::FreeBSDRepoFixture->new(root => $work,
    run_pkg => \&run_pkg, command => \&command, write_file => \&write_file);
command('/usr/bin/openssl', 'genpkey', '-algorithm', 'RSA', '-pkeyopt', 'rsa_keygen_bits:2048',
    '-out', "$work/repo.key");
command('/usr/bin/openssl', 'pkey', '-in', "$work/repo.key", '-pubout', '-out', "$work/repo.pub");
my $installroot = "$work/install";
make_path($installroot);
my $release = $fixture->release_tree(1);
my $dvd = xCAT::FreeBSDRepoImport::import_release($release, $installroot, tool => $tool,
    trust => {type => 'operator-trusted-release', digest => xCAT::FreeBSDRepo::inspect_release_tree($release)->{digest}});
my $supplement = $fixture->repository(1, [['test-app'], ['test-dep']]);
my $nested = $fixture->new_directory();
command('/usr/bin/cp', '-a', $supplement, "$nested/FreeBSD:15:amd64");
my $signed = xCAT::FreeBSDRepoImport::import_repository($nested, $installroot, tool => $tool,
    catalogue_prefix => 'FreeBSD:15:amd64',
    trust => {type => 'pubkey', path => "$work/repo.pub", sha256 => sha256_hex(read_file("$work/repo.pub"))});
sub identity {
    my ($repository, $name, $version, $origin) = @_;
    return {repository => $repository, identity => [$name, $version, $origin, 'FreeBSD:15:amd64']};
}
my @base_selection = map { identity(0, $_, '15.1', "base/$_") }
    qw(FreeBSD-runtime FreeBSD-kernel-generic FreeBSD-set-minimal FreeBSD-set-base);
push @base_selection, identity(0, 'pkg', '2.6.2_1', 'ports-mgmt/pkg');
my %base = (installroot => $installroot,
    resolver => {version => '2.8.2', sha256 => $tool->{sha256}, library_digest => $tool->{library_digest}},
    repositories => [{publication => $dvd->{path}, role => 'base'}], components => ['base'],
    applications => [], selected => \@base_selection);
my $base_wire = xCAT::FreeBSDPackagePlan::compose(%base);
my $dvd_wire = xCAT::FreeBSDPackagePlan::compose(%base,
    repositories => [@{$base{repositories}}, {publication => $dvd->{path}, role => 'applications'}],
    selected => [@base_selection, identity(1, 'application', '1', 'misc/application')],
    applications => [identity(1, 'application', '1', 'misc/application')]);
my $signed_wire = xCAT::FreeBSDPackagePlan::compose(%base,
    repositories => [@{$base{repositories}}, {publication => $signed->{path}, role => 'repository'}],
    selected => [@base_selection, identity(1, 'test-app', '1', 'misc/test-app'), identity(1, 'test-dep', '1', 'misc/test-dep')],
    applications => [identity(1, 'test-dep', '1', 'misc/test-dep'), identity(1, 'test-app', '1', 'misc/test-app')]);

my @cases;
my %names;
sub add_case {
    my ($name, $bytes, $accepted) = @_;
    croak "Duplicate fixture $name" if $names{$name}++;
    my $expected = eval { xCAT::FreeBSDPackagePlan::parse($bytes) };
    my $error = $@;
    croak "Controller expectation differs for $name: $error" if ($accepted && $error) || (!$accepted && !$error);
    my $file = "$name.plan";
    write_file("$output/$file", $bytes);
    push @cases, {name => $name, file => $file, sha256 => sha256_hex($bytes),
        accepted => $accepted ? 'yes' : 'no', $accepted ? (expected => $expected) : ()};
    return;
}
sub changed {
    my ($wire, $change) = @_;
    my $plan = xCAT::FreeBSDPackagePlan::parse($wire);
    $change->($plan);
    # Negative fixtures require encoding without controller validation.
    return xCAT::FreeBSDPackagePlan::_encode($plan); ## no critic (Subroutines::ProtectPrivateSubs)
}
sub rows {
    my ($wire, $change) = @_;
    my @rows = map { [split(/\t/x, $_, -1)] } split(/\n/x, $wire);
    $change->(\@rows);
    return join('', map { join("\t", @$_) . "\n" } @rows);
}

add_case('composed-base', $base_wire, 1);
add_case('composed-dvd-applications', $dvd_wire, 1);
add_case('composed-signed-prefix', $signed_wire, 1);
add_case('without-resolver-libraries', xCAT::FreeBSDPackagePlan::compose(%base,
    resolver => {version => '2.8.2', sha256 => $tool->{sha256}}), 1);
add_case('empty-components', xCAT::FreeBSDPackagePlan::compose(%base, components => []), 1);
add_case('opaque-unicode', changed($base_wire, sub { $_[0]{packages}[0]{version} = "A\x{e9} 'quoted';\$(ignored)" }), 1);
add_case('identity-1024-characters', changed($base_wire, sub { $_[0]{packages}[0]{version} = "\x{e9}" x 1024 }), 1);
add_case('identity-1025-characters', changed($base_wire, sub { $_[0]{packages}[0]{version} = "\x{e9}" x 1025 }), 0);
add_case('path-component-255', changed($base_wire, sub { $_[0]{packages}[0]{repopath} = ('A' x 251) . '.pkg' }), 1);
add_case('path-component-256', changed($base_wire, sub { $_[0]{packages}[0]{repopath} = ('A' x 252) . '.pkg' }), 0);
my $suffix = (('A' x 250) . '/') x 16;
$suffix .= ('B' x (4096 - length($suffix) - 4)) . '.pkg';
add_case('source-suffix-4096', changed($base_wire, sub { $_[0]{packages}[0]{path} = "base/$suffix" }), 1);
add_case('source-suffix-4097', changed($base_wire, sub { $_[0]{packages}[0]{path} = "base/A$suffix" }), 0);
add_case('logical-path-4096', changed($base_wire, sub { $_[0]{packages}[0]{repopath} = $suffix }), 1);
add_case('logical-path-4097', changed($base_wire, sub { $_[0]{packages}[0]{repopath} = "A$suffix" }), 0);
sub add_size_cases {
    my ($base_input, $signed_input) = @_;
    for my $field (['size', 17179869184], ['native_sum', 256]) {
        my ($name, $maximum) = @$field;
        for my $value (0, $maximum, $maximum + 1) {
            next if $name eq 'native_sum' && !$value;
            my $wire = changed($base_input, sub {
                $_[0]{packages}[0]{$name} = $name eq 'native_sum' ? 'A' x $value : "$value";
            });
            add_case("package-$name-$value" =~ s/_/-/grx, $wire, $value <= $maximum);
        }
    }
    for my $specification (['meta', 65536], ['catalogue', 67108864], ['key', 1048576]) {
        my ($kind, $maximum) = @$specification;
        for my $value (0, $maximum, $maximum + 1) {
            my $wire = changed($kind eq 'key' ? $signed_input : $base_input, sub {
                my $plan = shift;
                my ($file) = grep { $_->{kind} eq $kind }
                    map { @{$_->{files}} } @{$plan->{repositories}};
                $file->{size} = "$value";
            });
            add_case("$kind-size-$value", $wire, $value <= $maximum);
        }
    }
    return;
}
add_size_cases($base_wire, $signed_wire);
add_case('component-64', changed($base_wire, sub { $_[0]{components} = ['a' x 64] }), 1);
add_case('ordered-unicode-package-names', changed($base_wire, sub {
    my $packages = $_[0]{packages};
    $_->{name} = "\x{e9}" . $_->{name} for @$packages;
}), 1);

my @changes = (
    ['resolver-version', sub { $_[0]{resolver}{version} = '2.6.2' }],
    ['resolver-digest', sub { $_[0]{resolver}{sha256} = 'bad' }],
    ['library-digest', sub { $_[0]{resolver}{library_digest} = 'bad' }],
    ['repository-id', sub { $_[0]{repositories}[0]{id} = 'r00' }],
    ['repository-publication', sub { $_[0]{repositories}[0]{publication} = 'bad' }],
    ['repository-role', sub { $_[0]{repositories}[0]{role} = 'applications' }],
    ['repository-trust', sub { $_[0]{repositories}[0]{trust_type} = 'pubkey' }],
    ['trust-digest', sub { $_[0]{repositories}[0]{trust_digest} = 'bad' }],
    ['prefix-traversal', sub { $_[0]{repositories}[0]{prefix} = '../bad' }],
    ['missing-catalogue', sub { shift @{$_[0]{repositories}[0]{files}} }],
    ['duplicate-file', sub { push @{$_[0]{repositories}[0]{files}}, $_[0]{repositories}[0]{files}[0] }],
    ['foreign-file', sub { $_[0]{repositories}[0]{files}[0]{path} = 'base/foreign.pkg' }],
    ['file-digest', sub { $_[0]{repositories}[0]{files}[0]{sha256} = 'bad' }],
    ['file-size', sub { $_[0]{repositories}[0]{files}[0]{size} = '01' }],
    ['duplicate-component', sub { $_[0]{components} = ['base', 'base'] }],
    ['component-case', sub { $_[0]{components} = ['Base'] }],
    ['component-overflow', sub { $_[0]{components} = ['a' x 65] }],
    ['application-reference', sub { $_[0]{applications} = ['p999'] }],
    ['base-application', sub { $_[0]{applications} = ['p0'] }],
    ['package-id', sub { $_[0]{packages}[0]{id} = 'p00' }],
    ['package-repository', sub { $_[0]{packages}[0]{repository} = 'r9' }],
    ['package-order', sub { $_[0]{packages}[0]{name} = 'zzzz' }],
    ['duplicate-name', sub { $_[0]{packages}[1]{name} = $_[0]{packages}[0]{name} }],
    ['duplicate-source', sub { $_[0]{packages}[1]{path} = $_[0]{packages}[0]{path} }],
    ['duplicate-logical', sub { $_[0]{packages}[1]{repopath} = $_[0]{packages}[0]{repopath} }],
    ['source-role', sub { $_[0]{packages}[0]{path} = 'applications/All/a.pkg' }],
    ['source-traversal', sub { $_[0]{packages}[0]{path} = 'base/../a.pkg' }],
    ['logical-dot', sub { $_[0]{packages}[0]{repopath} = 'All/./a.pkg' }],
    ['logical-empty-component', sub { $_[0]{packages}[0]{repopath} = 'All//a.pkg' }],
    ['logical-nonascii', sub { $_[0]{packages}[0]{repopath} = "All/\x{e9}.pkg" }],
    ['logical-absolute', sub { $_[0]{packages}[0]{repopath} = '/All/a.pkg' }],
    ['archive-extension', sub { $_[0]{packages}[0]{repopath} = 'All/a.txz' }],
    ['package-size', sub { $_[0]{packages}[0]{size} = '01' }],
    ['package-digest', sub { $_[0]{packages}[0]{sha256} = 'bad' }],
    ['native-sum', sub { $_[0]{packages}[0]{native_sum} = 'bad/sum' }],
    ['identity-control', sub { $_[0]{packages}[0]{version} = "bad\x7f" }],
    ['identity-empty', sub { $_[0]{packages}[0]{version} = '' }],
);
add_case($_->[0], changed($base_wire, $_->[1]), 0) for @changes;
add_case('signed-key-mismatch', changed($signed_wire, sub {
    my ($key) = grep { $_->{kind} eq 'key' } @{$_[0]{repositories}[1]{files}};
    $key->{sha256} = '0' x 64;
}), 0);
add_case('duplicate-application', changed($signed_wire, sub { push @{$_[0]{applications}}, $_[0]{applications}[0] }), 0);
add_case('missing-packages', changed($base_wire, sub { $_[0]{packages} = [] }), 0);
add_case('duplicate-publication-role', changed($dvd_wire, sub {
    my $copy = $json->decode($json->encode($_[0]{repositories}[1]));
    $copy->{id} = 'r2';
    push @{$_[0]{repositories}}, $copy;
}), 0);
add_case('operator-trusted-repository', changed($signed_wire, sub {
    my $repository = $_[0]{repositories}[1];
    $repository->{trust_type} = 'operator-trusted-tree';
    $repository->{files} = [grep { $_->{kind} ne 'key' } @{$repository->{files}}];
}), 1);
add_case('source-extension-is-opaque', changed($base_wire, sub {
    $_[0]{packages}[0]{path} = 'base/All/native-archive.bin';
}), 1);
add_case('empty-bytes', '', 0);
add_case('missing-final-lf', substr($base_wire, 0, -1), 0);
add_case('extra-final-lf', "$base_wire\n", 0);
add_case('crlf', join("\r\n", split(/\n/x, $base_wire)) . "\r\n", 0);
add_case('unknown-record', "unknown\tfield\n$base_wire", 0);
add_case('group-order', rows($base_wire, sub { my $first = shift @{$_[0]}; push @{$_[0]}, $first }), 0);
add_case('duplicate-format', "format\txcat-freebsd-package-plan-1\n$base_wire", 0);
add_case('missing-format', rows($base_wire, sub { shift @{$_[0]} }), 0);
add_case('bad-arity', rows($base_wire, sub { push @{$_[0][0]}, 'extra' }), 0);
add_case('invalid-utf8', rows($base_wire, sub { my ($p) = grep { $_->[0] eq 'package' } @{$_[0]}; $p->[4] = "bad\xff" }), 0);
add_case('record-too-long', "unknown\t" . ('x' x 32768) . "\n", 0);
for my $kind (qw(target resolver resolver-libraries)) {
    add_case("duplicate-$kind", rows($base_wire, sub {
        my ($row) = grep { $_->[0] eq $kind } @{$_[0]};
        push @{$_[0]}, [@$row];
    }), 0);
    next if $kind eq 'resolver-libraries';
    add_case("missing-$kind", rows($base_wire, sub {
        @{$_[0]} = grep { $_->[0] ne $kind } @{$_[0]};
    }), 0);
}
for my $index (1 .. 3) {
    add_case("unsupported-target-field-$index", rows($base_wire, sub {
        my ($row) = grep { $_->[0] eq 'target' } @{$_[0]};
        $row->[$index] = 'unsupported';
    }), 0);
}
add_case('file-order', rows($base_wire, sub {
    my @indices = grep { $_[0][$_][0] eq 'file' } 0 .. $#{$_[0]};
    @{$_[0]}[@indices] = reverse @{$_[0]}[@indices];
}), 0);
add_case('duplicate-prefix', rows($signed_wire, sub {
    my ($row) = grep { $_->[0] eq 'prefix' } @{$_[0]};
    push @{$_[0]}, [@$row];
}), 0);
add_case('unknown-file-repository', rows($base_wire, sub {
    my ($row) = grep { $_->[0] eq 'file' } @{$_[0]};
    $row->[1] = 'r9';
}), 0);

sub selection_package {
    my ($example, $index) = @_;
    my $name = sprintf('P%05d', $index);
    return { %$example, id => "p$index", name => $name, origin => 'A',
        repopath => "All/$name.pkg", path => "base/All/$name.pkg" };
}

sub selection {
    my $count = shift;
    return changed($base_wire, sub {
        my $plan = shift;
        my $example = $plan->{packages}[0];
        $plan->{components} = [];
        $plan->{packages} = [map { selection_package($example, $_) } 0 .. $count - 1];
    });
}
sub add_count_cases {
    my $base_input = shift;
    my $many = selection(8192);
    add_case('packages-8192', $many, 1);
    add_case('packages-8193', selection(8193), 0);
    my $header_count = () = $many =~ /\n/gx;
    my $remaining_records = 16384 - $header_count;
    my $max_records = changed($many, sub { $_[0]{components} = [map { sprintf('c%05d', $_) } 0 .. $remaining_records - 1] });
    add_case('records-16384', $max_records, 1);
    add_case('records-16385', changed($max_records, sub { push @{$_[0]{components}}, 'overflow' }), 0);
    my $max_bytes = changed($many, sub {
        my $remaining = 8388608 - length($many);
        for my $package (@{$_[0]{packages}}) {
            my $added = $remaining < 1023 ? $remaining : 1023;
            $package->{origin} .= 'A' x $added;
            $remaining -= $added;
            last unless $remaining;
        }
        croak 'Cannot construct exact byte boundary' if $remaining;
    });
    croak 'Wrong byte boundary fixture' unless length($max_bytes) == 8388608;
    add_case('bytes-8388608', $max_bytes, 1);
    add_case('bytes-8388609', changed($max_bytes, sub {
        my ($room) = grep { length($_->{origin}) < 1024 } @{$_[0]{packages}};
        $room->{origin} .= 'A';
    }), 0);
    for my $count (32, 33) {
        my $wire = changed($base_input, sub {
            my $plan = shift;
            for my $index (1 .. $count - 1) {
                my $repo = $json->decode($json->encode($plan->{repositories}[0]));
                $repo->{id} = "r$index";
                $repo->{role} = 'applications';
                $repo->{publication} = sprintf('%064x', $index);
                $_->{path} =~ s{\Abase/}{applications/}x for @{$repo->{files}};
                push @{$plan->{repositories}}, $repo;
            }
        });
        add_case("repositories-$count", $wire, $count == 32);
    }
    return;
}
add_count_cases($base_wire);
croak 'Controller source changed' unless sha256_hex(read_file($controller_path)) eq $controller_sha;
write_file("$output/manifest.json", $json->encode({format => 'xcat-freebsd-plan-fixtures-1',
    controller_sha256 => $controller_sha, cases => \@cases}) . "\n");
printf "Generated %d controller-qualified cases\n", scalar @cases;

__END__

=head1 NAME

make-freebsd-plan-fixtures.pl - generate controller-qualified decoder fixtures

=head1 SYNOPSIS

  perl xCAT-test/bin/make-freebsd-plan-fixtures.pl source empty-output-directory

=head1 USAGE

Run on Linux. Set C<source> to the xCAT checkout and create an empty output directory.
Set C<XCAT_FREEBSD_NATIVE_PKG> to the native pkg 2.8.2 executable.
Set C<XCAT_FREEBSD_NATIVE_LIBDIR> to its library directory.
Both paths must meet the controller's native tool protection requirements.

For native tests, copy only the output directory's top-level C<*.plan> files and C<manifest.json>.
The C<build/> directory contains a fixture private signing key and repositories. Exclude it from the native payload.

=cut
