#!/usr/bin/env perl
use strict;
use warnings;
## no critic (TestingAndDebugging::ProhibitNoWarnings, Variables::RequireLocalizedPunctuationVars)
use Errno qw(EACCES);
use FindBin;
use File::Slurper qw(read_text write_text);
use File::Temp qw(tempdir);
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../xCAT-server/share/xcat/netboot/imgutils";
use Test::More;

BEGIN {
    *CORE::GLOBAL::rename = sub { return CORE::rename($_[0], $_[1]); };
    *CORE::GLOBAL::link   = sub { return CORE::link($_[0], $_[1]); };
}
use imgutils;

my @modes = qw(statelite stateless);
my @names = ('kernel', map { "initrd-$_.gz" } @modes);

# Publishes a staged kernel and two ramdisks over an older set, failing the named link, rename, or rollback.
sub publish_case {
    my (%case) = @_;
    my $dir     = tempdir(CLEANUP => 1);
    my $staging = File::Temp->newdir('.genimage-boot.XXXXXX', DIR => $dir, CLEANUP => 1);
    write_text("$staging/$_", "new $_\n") for @names;
    if ($case{old}) {
        write_text("$dir/$_", "old $_\n") for @names;
    }
    my ($ok, $error);
    {
        no warnings 'redefine';
        local *CORE::GLOBAL::link = sub {
            if (defined $case{link} && $_[0] eq "$dir/$case{link}") {
                $! = EACCES;
                return 0;
            }
            return CORE::link($_[0], $_[1]);
        };
        local *CORE::GLOBAL::rename = sub {
            if ((defined $case{rename} && $_[0] eq "$staging/$case{rename}")
                || (defined $case{rollback} && $_[0] eq "$staging/previous-$case{rollback}")) {
                $! = EACCES;
                return 0;
            }
            return CORE::rename($_[0], $_[1]);
        };
        $ok    = eval { imgutils::publish_staged_boot_files($staging, $dir, @modes) };
        $error = $@;
    }
    undef $staging;
    my %state = map { $_ => (-e "$dir/$_" ? read_text("$dir/$_") : undef) } @names;
    return ($ok, $error, $dir, \%state);
}

sub set_of {
    my ($age) = @_;
    return { map { $_ => "$age $_\n" } @names };
}

for my $old (1, 0) {
    my $label = $old ? 'over an older set' : 'on a first build';
    my ($ok, $error, $dir, $state) = publish_case(old => $old);
    ok($ok, "publication $label completes") or diag($error);
    is_deeply($state, set_of('new'), "publication $label puts the new kernel and both ramdisks in place");
    is_deeply([ glob("$dir/.genimage*") ], [], "publication $label removes the staging directory");
}

for my $name (@names) {
    my ($ok, $error, $dir, $state) = publish_case(old => 1, link => $name);
    ok(!$ok, "a failed backup of $name stops the publication");
    like($error, qr/^Error: failed to preserve the previous (?:kernel|initial ramdisk for \w+): /, "the error names the $name backup");
    is_deeply($state, set_of('old'), "a failed backup of $name keeps the older set");
}

for my $name (@names) {
    my ($ok, $error, $dir, $state) = publish_case(old => 1, rename => $name);
    ok(!$ok, "a failed rename of $name stops the publication");
    like($error, qr/^Error: failed to publish the (?:kernel|initial ramdisk for \w+): /, "the error names the $name rename");
    is_deeply($state, set_of('old'), "a failed rename of $name puts the older set back");
    is_deeply([ glob("$dir/.genimage*") ], [], "a failed rename of $name removes the staging directory");
}

{
    my ($ok, $error, $dir, $state) = publish_case(old => 0, rename => 'initrd-stateless.gz');
    ok(!$ok, 'a failed rename on a first build stops the publication');
    is_deeply($state, { map { $_ => undef } @names }, 'a failed rename on a first build leaves no kernel or ramdisk');
}

SKIP: {
    skip 'link() of a symbolic link is checked on Linux', 2 unless $^O eq 'linux';
    my $dir     = tempdir(CLEANUP => 1);
    my $staging = File::Temp->newdir('.genimage-boot.XXXXXX', DIR => $dir, CLEANUP => 1);
    write_text("$staging/$_", "new $_\n") for @names;
    symlink('missing-kernel', "$dir/kernel") or die "symlink: $!";
    write_text("$dir/$_", "old $_\n") for grep { $_ ne 'kernel' } @names;
    my $ok;
    {
        no warnings 'redefine';
        local *CORE::GLOBAL::rename = sub {
            if ($_[0] eq "$staging/initrd-stateless.gz") {
                $! = EACCES;
                return 0;
            }
            return CORE::rename($_[0], $_[1]);
        };
        $ok = eval { imgutils::publish_staged_boot_files($staging, $dir, @modes) };
    }
    ok(!$ok, 'a failed rename over a dangling kernel link stops the publication');
    is(readlink("$dir/kernel"), 'missing-kernel', 'a dangling kernel link is put back instead of removed');
}

{
    my ($ok, $error, $dir, $state) = publish_case(old => 1, rename => 'initrd-stateless.gz', rollback => 'initrd-statelite.gz');
    ok(!$ok, 'a failed rollback stops the publication');
    like($error, qr/initial ramdisk for statelite rollback failed: .*Boot files retained in \Q$dir\E\/\.genimage-boot\./,
        'the error names the file that could not be put back and the directory that keeps it');
    is($state->{kernel}, "old kernel\n", 'the kernel is still put back after a failed rollback of a ramdisk');
    my ($kept) = glob("$dir/.genimage-boot.*/previous-initrd-statelite.gz");
    ok(defined $kept, 'the staging directory keeps the previous ramdisk that could not be put back');
    is(defined $kept ? read_text($kept) : undef, "old initrd-statelite.gz\n", 'the kept file is the previous ramdisk');
}

done_testing();
