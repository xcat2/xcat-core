#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../perl-xCAT";
use Carp qw(croak);
use Cwd qw(abs_path);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use Test::More;
use xCAT::FreeBSDRepoImport;

my $tmp = abs_path(tempdir(CLEANUP => 1));
my $sequence = 0;

sub directory {
    my $path = "$tmp/case-" . ++$sequence;
    mkdir($path, oct('0700')) or croak $!;
    return $path;
}

sub rejects {
    my ($action, $description) = @_;
    my $ok = eval { $action->(); 1; };
    my $error = $@;
    ok(!$ok, $description);
    my $description_error = qr/(?:publication|directory|collection)/ix;
    my $argument_error = qr/(?:create|argument|absolute|path)/ix;
    like($error, qr/(?:$description_error|$argument_error)/x,
        "$description reports its invalid directory request");
    return;
}

sub creation_cases {
    my $root = directory();
    for my $collection (qw(repositories plans)) {
        my $path = "$root/freebsd15.1/x86_64/$collection";
        rejects(sub { xCAT::FreeBSDRepoImport::publication_directory($root, $collection, 0) },
            "read-only $collection lookup rejects a missing directory");
        ok(!-e $path, "read-only $collection lookup creates nothing");
        is(xCAT::FreeBSDRepoImport::publication_directory($root, $collection, 1), $path,
            "$collection creates only its fixed release and architecture namespace");
        my @before = stat($path);
        is($before[2] & oct('7777'), oct('0755'), "$collection directory has protected permissions");
        is($before[4], $>, "$collection directory belongs to the caller");
        is(xCAT::FreeBSDRepoImport::publication_directory($root, $collection, 0), $path,
            "read-only $collection lookup returns the existing directory");
        is(xCAT::FreeBSDRepoImport::publication_directory($root, $collection, 1), $path,
            "$collection creation is repeatable");
        my @after = stat($path);
        is_deeply([@after[0, 1, 2, 4, 9, 10]], [@before[0, 1, 2, 4, 9, 10]],
            "$collection reuse changes neither its inode nor operational metadata");
    }
    return;
}

sub argument_cases {
    for my $collection (undef, '', 'boot', '../plans', 'plans/nested', [], {}) {
        my $root = directory();
        rejects(sub { xCAT::FreeBSDRepoImport::publication_directory($root, $collection, 1) },
            'unknown or non-scalar collection is rejected');
        ok(!-e "$root/freebsd15.1", 'invalid collection leaves the install root empty');
    }
    for my $create (undef, '', 2, -1, 'true', '01', [], {}) {
        my $root = directory();
        rejects(sub { xCAT::FreeBSDRepoImport::publication_directory($root, 'plans', $create) },
            'non-boolean create argument is rejected');
        ok(!-e "$root/freebsd15.1", 'invalid create argument leaves the install root empty');
    }
    for my $root (undef, '', '/', 'relative', "$tmp/./missing", "$tmp/../missing", [], {}) {
        rejects(sub { xCAT::FreeBSDRepoImport::publication_directory($root, 'plans', 1) },
            'invalid install root is rejected');
    }
    rejects(sub { xCAT::FreeBSDRepoImport::publication_directory(directory(), 'plans') },
        'omitted creation policy is rejected');
    rejects(sub { xCAT::FreeBSDRepoImport::publication_directory(directory(), 'plans', 1, 'extra') },
        'extra arguments are rejected');
    return;
}

sub ancestor_cases {
    for my $relative ('', 'freebsd15.1', 'freebsd15.1/x86_64', 'freebsd15.1/x86_64/plans') {
        for my $kind (qw(symlink writable regular)) {
            my $root = directory();
            make_path("$root/freebsd15.1/x86_64/plans");
            my $path = length($relative) ? "$root/$relative" : $root;
            if ($kind eq 'writable') {
                chmod(oct('0777'), $path) or croak $!;
            } else {
                rename($path, "$path.actual") or croak $!;
                if ($kind eq 'symlink') {
                    symlink("$path.actual", $path) or croak $!;
                } else {
                    open(my $fh, '>', $path) or croak $!;
                    close($fh) or croak $!;
                }
            }
            for my $create (0, 1) {
                rejects(sub { xCAT::FreeBSDRepoImport::publication_directory($root, 'plans', $create) },
                    "$kind ancestor is rejected with create=$create");
            }
        }
    }
    my $ancestor = directory();
    chmod(oct('1777'), $ancestor) or croak $!;
    mkdir("$ancestor/owned", oct('0700')) or croak $!;
    is(xCAT::FreeBSDRepoImport::publication_directory("$ancestor/owned", 'plans', 1),
        "$ancestor/owned/freebsd15.1/x86_64/plans", 'a sticky writable ancestor above the install root is allowed');
    chmod(oct('1777'), "$ancestor/owned") or croak $!;
    rejects(sub { xCAT::FreeBSDRepoImport::publication_directory("$ancestor/owned", 'plans', 0) },
        'a sticky writable install root is not an allowed ancestor exception');
    return;
}

sub owner_cases {
    plan(skip_all => 'Owner mutation requires root') if $> != 0;
    for my $relative ('', 'freebsd15.1', 'freebsd15.1/x86_64', 'freebsd15.1/x86_64/plans') {
        my $root = directory();
        make_path("$root/freebsd15.1/x86_64/plans");
        my $path = length($relative) ? "$root/$relative" : $root;
        chown(65534, 65534, $path) == 1 or croak $!;
        for my $create (0, 1) {
            rejects(sub { xCAT::FreeBSDRepoImport::publication_directory($root, 'plans', $create) },
                "foreign owner is rejected with create=$create");
        }
    }
    return;
}

subtest 'explicit creation and read-only validation' => \&creation_cases;
subtest 'invalid requests do not create namespaces' => \&argument_cases;
subtest 'all publication ancestors remain protected' => \&ancestor_cases;
subtest 'foreign owned publication directories' => \&owner_cases;
done_testing();
