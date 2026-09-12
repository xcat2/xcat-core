#!/usr/bin/env perl
# gettimezone names the timezone that goes into a kickstart or an autoyast profile, where the
# value must be one token. It found the name by comparing /etc/localtime against every file under
# /usr/share/zoneinfo, and when that pipeline failed it returned the sentence "Could not determine
# timezone checksum" as if it were a name.
#
# A Rocky 10.2 riscv64 cloud image has no /etc/localtime at all and runs on UTC. The compute node
# xcat56-cn was therefore written /install/autoinst/xcat56-cn line 21
# "timezone Could not determine timezone checksum --utc", anaconda answered "One or zero arguments
# are expected for the timezone command", and the install stopped before it installed one package.
# The node stayed at status=installing for 59 minutes until retry_install.sh reinstalled over it.
#
# Utils.pm cannot be loaded here, so the routine is extracted and driven against a scratch root
# with the two collaborators it calls replaced.
use strict;
use warnings;

use File::Path qw(make_path);
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

my $source = "$FindBin::Bin/../../perl-xCAT/xCAT/Utils.pm";
open(my $source_fh, '<', $source) or die "open $source: $!";
my $content = do { local $/; <$source_fh> };
close($source_fh) or die "close $source: $!";

my @routines;
for my $name (qw(gettimezone _zone_from_path)) {
    my ($routine) = $content =~ /^(sub \Q$name\E\s*\n?\{.*?^\})/ms;
    BAIL_OUT("could not extract $name from Utils.pm") unless $routine;
    push(@routines, $routine);
}
# The routines call each other unqualified and the caller reaches them through the class, so
# they go back into the package they came from.
eval "package xCAT::Utils;\n" . join("\n", @routines); ## no critic (BuiltinFunctions::ProhibitStringyEval)
BAIL_OUT("could not load the timezone routines: $@") if $@;

# The collaborators gettimezone calls. The scan runs `find`, which must never look at the host
# this test runs on, so it answers from the scratch root instead.
our $SCAN_OUT = '';
our $SCAN_RC  = 1;
{
    no warnings 'once';
    *xCAT::Utils::isAIX = sub { return 0 };
    *xCAT::Utils::runcmd = sub { $::RUNCMD_RC = $SCAN_RC; return $SCAN_OUT };
}

#-----------------------------------------------------------------------------------------------
=head3 scratch_root

Descriptions:
    A root with a zoneinfo tree, and /etc/localtime as a symlink into it when a zone is named.
Arguments:
    $zone - the zone to link /etc/localtime to, or undef for a root with no /etc/localtime
Returns:
    The root directory.
=cut
#-----------------------------------------------------------------------------------------------
sub scratch_root {
    my ($zone) = @_;
    my $root = tempdir(CLEANUP => 1);
    make_path("$root/etc", "$root/usr/share/zoneinfo/America");
    for my $name ('UTC', 'America/Sao_Paulo') {
        open(my $fh, '>', "$root/usr/share/zoneinfo/$name") or die "create $name: $!";
        print {$fh} "TZif";
        close($fh) or die "close $name: $!";
    }
    symlink("../usr/share/zoneinfo/$zone", "$root/etc/localtime") or die "symlink: $!"
        if defined $zone;
    return $root;
}

is(xCAT::Utils->gettimezone(root => scratch_root('America/Sao_Paulo')), 'America/Sao_Paulo',
    'the /etc/localtime symlink names the zone');

# The failure that stopped the riscv64 install: no /etc/localtime, so the scan reports nothing.
my $none = xCAT::Utils->gettimezone(root => scratch_root(undef));
is($none, 'UTC', 'a root with no /etc/localtime falls back to UTC');
unlike($none, qr/\s/,
    'the value is one token, which is all the kickstart timezone command accepts');

# /etc/timezone is consulted before the fallback.
my $root = scratch_root(undef);
open(my $tz_fh, '>', "$root/etc/timezone") or die "create /etc/timezone: $!";
print {$tz_fh} "America/Sao_Paulo\n";
close($tz_fh) or die "close /etc/timezone: $!";
is(xCAT::Utils->gettimezone(root => $root), 'America/Sao_Paulo',
    '/etc/timezone names the zone when there is no symlink');

# The scan still answers for a root whose /etc/localtime is a copy rather than a symlink.
$root = scratch_root(undef);
open(my $copy_fh, '>', "$root/etc/localtime") or die "create /etc/localtime: $!";
print {$copy_fh} "TZif";
close($copy_fh) or die "close /etc/localtime: $!";
{
    local $SCAN_OUT = "$root/usr/share/zoneinfo/America/Sao_Paulo\n";
    local $SCAN_RC  = 0;
    is(xCAT::Utils->gettimezone(root => $root), 'America/Sao_Paulo',
        'the zoneinfo scan names the zone when /etc/localtime is a copy');
}

done_testing();
