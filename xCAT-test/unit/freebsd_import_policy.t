#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use Cwd qw(abs_path);
use Carp qw(croak);
use File::Find qw(find);
use File::Temp qw(tempdir);
use JSON;
use POSIX qw(mkfifo);
use Storable qw(dclone);
use Test::More;
use xCAT::FreeBSDRepoImport;

my $root = abs_path(tempdir('freebsd-import-policy-XXXXXXXX', TMPDIR => 1, CLEANUP => 1));
my $counter = 0;
my $commands = 0;
my $digest = 'a' x 64;
my $policy = {
    format => 'xcat-freebsd-import-policy-1',
    tool => { path => '/missing/native/pkg', sha256 => 'b' x 64,
        library_directory => '/missing/native/lib', library_digest => 'c' x 64 },
    releases => { $digest => { iso_sha256 => 'd' x 64 } },
    repositories => {
        signed => { trust => { type => 'pubkey', path => '/missing/repository.pub', sha256 => 'e' x 64 } },
        offline => { trust => { type => 'operator-trusted-tree', digest => 'f' x 64 },
            catalogue_prefix => 'FreeBSD:15:amd64' },
    },
};

sub directory {
    my $path = "$root/case-" . ++$counter;
    mkdir($path, oct('0700')) or croak "Cannot create test directory: $!";
    return $path;
}

sub write_bytes {
    my ($path, $bytes, $mode) = @_;
    open(my $fh, '>:raw', $path) or croak "Cannot create test policy: $!";
    print {$fh} $bytes or croak "Cannot write test policy: $!";
    close($fh) or croak "Cannot close test policy: $!";
    chmod(defined($mode) ? $mode : oct('0600'), $path) or croak "Cannot protect test policy: $!";
    return $path;
}

sub policy_file {
    my $value = shift;
    return write_bytes(directory() . '/policy.json', JSON->new->utf8->pretty->allow_nonref->encode($value));
}

sub error_from {
    my $action = shift;
    my $ok = eval { $action->(); 1 };
    return $ok ? '' : $@;
}

sub reject_policy {
    my ($value, $pattern, $label) = @_;
    my $path = policy_file($value);
    like(error_from(sub { xCAT::FreeBSDRepoImport::load_import_policy($path) }), $pattern, $label);
    return;
}

sub inventory {
    my $path = shift;
    my %entries;
    find({ no_chdir => 1, wanted => sub {
        my @state = lstat($File::Find::name); ## no critic (Variables::ProhibitPackageVars)
        $entries{$File::Find::name} = [@state[0, 1, 2, 3, 4, 5, 7, 9, 10]]; ## no critic (Variables::ProhibitPackageVars)
    } }, $path);
    return \%entries;
}

sub valid_cases {
    my $path = policy_file($policy);
    my $before = inventory($root);
    my $loaded = eval { xCAT::FreeBSDRepoImport::load_import_policy($path) };
    is($@, '', 'human-readable administrator JSON loads');
    is_deeply($loaded, $policy, 'loading retains operator-recorded ISO provenance and profiles');
    return unless $loaded;
    my $release = xCAT::FreeBSDRepoImport::release_import_options($loaded, $digest);
    is_deeply($release, { tool => $policy->{tool},
        trust => { type => 'operator-trusted-release', digest => $digest } },
        'release selection returns native tree trust, not an ISO digest');
    my $signed = xCAT::FreeBSDRepoImport::repository_import_options($loaded, 'signed');
    is_deeply($signed, { tool => $policy->{tool}, trust => $policy->{repositories}{signed}{trust}, catalogue_prefix => '' },
        'signed selection defaults to the root catalogue');
    my $offline = xCAT::FreeBSDRepoImport::repository_import_options($loaded, 'offline');
    is_deeply($offline, { tool => $policy->{tool}, %{$policy->{repositories}{offline}} },
        'offline selection retains the pinned tree and catalogue prefix');
    $release->{tool}{path} = '/changed/pkg';
    $signed->{trust}{path} = '/changed/key';
    $offline->{tool}{library_directory} = '/changed/lib';
    is_deeply($loaded, $policy, 'returned options do not alias the loaded policy');
    is_deeply(inventory($root), $before, 'loading and selection do not change filesystem entries or metadata');
    is($commands, 0, 'policy operations do not invoke native commands');
    my $empty = { format => $policy->{format}, tool => { path => '/missing/pkg', sha256 => 'b' x 64 },
        releases => {}, repositories => {} };
    is_deeply(xCAT::FreeBSDRepoImport::load_import_policy(policy_file($empty)), $empty,
        'empty approval maps and a standalone tool are valid');
    return;
}

sub schema_cases {
    for my $field (qw(format tool releases repositories)) {
        my $value = dclone($policy);
        delete($value->{$field});
        reject_policy($value, qr/(?:policy|tool)/x, "missing $field is rejected");
    }
    for my $case (
        ['unknown root field', sub { $_[0]{extra} = 1 }],
        ['unknown tool field', sub { $_[0]{tool}{environment} = {} }],
        ['unknown release field', sub { $_[0]{releases}{$digest}{extra} = 1 }],
        ['unknown profile field', sub { $_[0]{repositories}{signed}{command} = '/bin/true' }],
        ['unknown trust field', sub { $_[0]{repositories}{signed}{trust}{extra} = 1 }],
        ['wrong format', sub { $_[0]{format} = 'xcat-freebsd-import-policy-2' }],
        ['tool array', sub { $_[0]{tool} = [] }],
        ['release array', sub { $_[0]{releases} = [] }],
        ['repository array', sub { $_[0]{repositories} = [] }],
        ['release approval array', sub { $_[0]{releases}{$digest} = [] }],
        ['profile array', sub { $_[0]{repositories}{signed} = [] }],
        ['trust array', sub { $_[0]{repositories}{signed}{trust} = [] }],
        ['trust type reference', sub { $_[0]{repositories}{signed}{trust}{type} = {} }],
        ['unsupported trust', sub { $_[0]{repositories}{signed}{trust}{type} = 'none' }],
        ['missing paired library path', sub { delete($_[0]{tool}{library_directory}) }],
        ['missing paired library digest', sub { delete($_[0]{tool}{library_digest}) }],
    ) {
        my $value = dclone($policy);
        $case->[1]->($value);
        reject_policy($value, qr/(?:Invalid|Unknown|Unsupported)/x, $case->[0]);
    }
    for my $value (undef, [], 'text', 1, JSON::true) {
        reject_policy($value, qr/Invalid.*policy/x, 'a policy must be an object');
    }
    return;
}

sub reference_cases {
    for my $bad (undef, [], 'A' x 64, 'a' x 63, 'a' x 65, 'x' x 64) {
        for my $change (
            sub { $_[0]{tool}{sha256} = $bad },
            sub { $_[0]{tool}{library_digest} = $bad },
            sub { $_[0]{releases}{$digest}{iso_sha256} = $bad },
            sub { $_[0]{repositories}{signed}{trust}{sha256} = $bad },
            sub { $_[0]{repositories}{offline}{trust}{digest} = $bad },
        ) {
            my $value = dclone($policy);
            $change->($value);
            reject_policy($value, qr/digest/x, 'invalid trust or tool digest is rejected');
        }
    }
    for my $bad ('', '/absolute', '../parent', 'with space', 'a' x 65, '-first') {
        my $value = dclone($policy);
        $value->{repositories}{$bad} = delete($value->{repositories}{signed});
        reject_policy($value, qr/profile[ ]name/x, 'invalid repository profile name is rejected');
    }
    for my $bad ('A' x 64, 'a' x 63, 'a' x 65) {
        my $value = dclone($policy);
        $value->{releases}{$bad} = delete($value->{releases}{$digest});
        reject_policy($value, qr/release.*digest/x, 'invalid release map key is rejected');
    }
    for my $bad ('relative', '/', '/one//two', '/one/./two', '/one/../two', "/one\ntwo", '/' . ('a' x 4096), []) {
        for my $change (sub { $_[0]{tool}{path} = $bad },
            sub { $_[0]{repositories}{signed}{trust}{path} = $bad }) {
            my $value = dclone($policy);
            $change->($value);
            reject_policy($value, qr/path/x, 'invalid referenced absolute path is rejected');
        }
    }
    my $colon = dclone($policy);
    $colon->{tool}{library_directory} = '/one:/two';
    reject_policy($colon, qr/colon/x, 'library path cannot extend the runtime search list');
    for my $bad (undef, [], '/', '/prefix', 'one//two', '../two', 'one/.', 'a' x 256) {
        my $value = dclone($policy);
        $value->{repositories}{signed}{catalogue_prefix} = $bad;
        reject_policy($value, qr/catalogue[ ]prefix/x, 'invalid relative catalogue prefix is rejected');
    }
    return;
}

sub selection_cases {
    like(error_from(sub { xCAT::FreeBSDRepoImport::release_import_options($policy, '0' x 64) }),
        qr/not[ ]approved/x, 'unapproved release digest is rejected');
    like(error_from(sub { xCAT::FreeBSDRepoImport::repository_import_options($policy, 'absent') }),
        qr/not[ ]approved/x, 'unapproved repository profile is rejected');
    for my $bad (undef, [], 'A' x 64, 'short') {
        like(error_from(sub { xCAT::FreeBSDRepoImport::release_import_options($policy, $bad) }),
            qr/digest/x, 'release selector is validated');
    }
    for my $bad (undef, [], '../signed', 'with space') {
        like(error_from(sub { xCAT::FreeBSDRepoImport::repository_import_options($policy, $bad) }),
            qr/profile/x, 'repository selector is validated');
    }
    my $invalid = dclone($policy);
    $invalid->{tool}{sha256} = 'changed';
    like(error_from(sub { xCAT::FreeBSDRepoImport::release_import_options($invalid, $digest) }),
        qr/digest/x, 'release selection revalidates a modified decoded policy');
    like(error_from(sub { xCAT::FreeBSDRepoImport::repository_import_options($invalid, 'signed') }),
        qr/digest/x, 'repository selection revalidates a modified decoded policy');
    return;
}

sub filesystem_cases {
    for my $mode (oct('0444'), oct('0600'), oct('0644')) {
        my $path = policy_file($policy);
        chmod($mode, $path) or croak "Cannot set policy mode: $!";
        is(error_from(sub { xCAT::FreeBSDRepoImport::load_import_policy($path) }), '', 'protected file mode is accepted');
    }
    for my $mode (oct('0666'), oct('0620'), oct('0602')) {
        my $path = policy_file($policy);
        chmod($mode, $path) or croak "Cannot set policy mode: $!";
        like(error_from(sub { xCAT::FreeBSDRepoImport::load_import_policy($path) }), qr/protected/x, 'writable file is rejected');
    }
    my $path = policy_file($policy);
    my $link = directory() . '/policy.json';
    symlink($path, $link) or croak "Cannot create test symlink: $!";
    like(error_from(sub { xCAT::FreeBSDRepoImport::load_import_policy($link) }), qr/regular[ ]file/x, 'symlink policy is rejected');
    unlink($link) or croak "Cannot remove test symlink: $!";
    link($path, $link) or croak "Cannot create test hard link: $!";
    like(error_from(sub { xCAT::FreeBSDRepoImport::load_import_policy($path) }), qr/protected/x, 'multiply linked policy is rejected');
    my $fifo = directory() . '/fifo';
    mkfifo($fifo, oct('0600')) or croak "Cannot create test FIFO: $!";
    like(error_from(sub { xCAT::FreeBSDRepoImport::load_import_policy($fifo) }), qr/regular[ ]file/x, 'FIFO policy is rejected without a writer');
    like(error_from(sub { xCAT::FreeBSDRepoImport::load_import_policy(directory()) }), qr/regular[ ]file/x, 'directory policy is rejected');
    my $parent = directory();
    my $file = write_bytes("$parent/policy.json", JSON->new->encode($policy));
    chmod(oct('0777'), $parent) or croak "Cannot set parent mode: $!";
    like(error_from(sub { xCAT::FreeBSDRepoImport::load_import_policy($file) }), qr/Writable.*directory/x, 'unsafe parent is rejected');
    chmod(oct('01777'), $parent) or croak "Cannot set sticky parent mode: $!";
    is(error_from(sub { xCAT::FreeBSDRepoImport::load_import_policy($file) }), '', 'sticky temporary ancestor is accepted');
    chmod(oct('0700'), $parent) or croak "Cannot restore parent mode: $!";
    my $alias = directory() . '/alias';
    symlink($parent, $alias) or croak "Cannot create parent symlink: $!";
    like(error_from(sub { xCAT::FreeBSDRepoImport::load_import_policy("$alias/policy.json") }), qr/symlinked.*directory/x, 'symlink parent is rejected');
    for my $bad ('relative', '/', "$parent/./policy.json", "$parent/../policy.json", "$parent//policy.json", []) {
        like(error_from(sub { xCAT::FreeBSDRepoImport::load_import_policy($bad) }), qr/path/x, 'unsafe policy path is rejected');
    }
    SKIP: {
        skip 'Owner changes require root', 2 unless $> == 0;
        chown(65534, -1, $file) == 1 or croak "Cannot set test file owner: $!";
        like(error_from(sub { xCAT::FreeBSDRepoImport::load_import_policy($file) }), qr/protected/x, 'foreign file owner is rejected');
        chown(0, -1, $file) == 1 or croak "Cannot restore test file owner: $!";
        chown(65534, -1, $parent) == 1 or croak "Cannot set test directory owner: $!";
        like(error_from(sub { xCAT::FreeBSDRepoImport::load_import_policy($file) }), qr/owner/x, 'foreign parent owner is rejected');
        chown(0, -1, $parent) == 1 or croak "Cannot restore test directory owner: $!";
    }
    return;
}

sub bytes_cases {
    my $bytes = JSON->new->encode($policy);
    my $limit = 1048576;
    my $exact = write_bytes(directory() . '/policy.json', $bytes . (' ' x ($limit - length($bytes))));
    is(error_from(sub { xCAT::FreeBSDRepoImport::load_import_policy($exact) }), '', 'one MiB human-readable JSON is allowed');
    my $large = write_bytes(directory() . '/policy.json', $bytes . (' ' x ($limit - length($bytes) + 1)));
    like(error_from(sub { xCAT::FreeBSDRepoImport::load_import_policy($large) }), qr/bounded/x, 'oversized policy is rejected');
    for my $bad ('', '{', '{} trailing', "\xff", '[' x 40 . '0' . ']' x 40) {
        my $path = write_bytes(directory() . '/policy.json', $bad);
        like(error_from(sub { xCAT::FreeBSDRepoImport::load_import_policy($path) }), qr/JSON/x, 'invalid or deeply nested JSON is rejected');
    }
    return;
}

{
    no warnings 'redefine'; ## no critic (TestingAndDebugging::ProhibitNoWarnings)
    local *xCAT::FreeBSDPkg::run_command = sub { ++$commands; croak "Policy invoked a native command\n"; };
    subtest 'protected policy selects native options without execution' => \&valid_cases;
    subtest 'policy shape is explicit' => \&schema_cases;
    subtest 'tool and repository references are constrained' => \&reference_cases;
    subtest 'only approved selections return options' => \&selection_cases;
    subtest 'policy ownership and paths are protected' => \&filesystem_cases;
    subtest 'policy reads are bounded human-readable JSON' => \&bytes_cases;
}
is($commands, 0, 'all policy cases avoid native command execution');
done_testing();
