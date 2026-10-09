#!/usr/bin/env perl
use strict;
use warnings;
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use XCAT::Test::File qw(repo_path);
use XCAT::Test::Package qw(run_in);

plan skip_all => 'requires Linux RPM tooling' unless $^O eq 'linux';
local %ENV = (%ENV, HOME => tempdir(CLEANUP => 1));
delete @ENV{qw(pcm fsm s390x)};
my @platforms = (
    ['EL7', 'rhel 7', 0], ['EL8', 'rhel 8', 1], ['EL9', 'rhel 9', 1],
    ['EL10', 'rhel 10', 1], ['Fedora', 'fedora 44', 1],
    ['SLES12', 'suse_version 1315', 0], ['SLES15', 'suse_version 1500', 1],
    ['openEuler', 'openEuler 2', 0],
);
my @images = map { "xCAT-genesis-openembedded-$_" } qw(x86_64 ppc64le riscv64 s390x);
my %legacy = (x86_64 => 'x86_64', ppc64le => 'ppc64', aarch64 => 'aarch64');
for my $platform (@platforms) {
    my ($name, $macro, $weak) = @$platform;
    for my $arch (qw(x86_64 ppc64le aarch64 riscv64 s390x)) {
        for my $pkg (qw(xCAT xCATsn)) {
            my $requires = query($pkg, $arch, $macro, '--requires');
            my $recommends = query($pkg, $arch, $macro, '--recommends');
            unlike($requires, qr/xCAT-genesis-openembedded-/, "$name $arch $pkg never requires optional images");
            my @actual = sort grep { /^xCAT-genesis-openembedded-/ } split /\n/, $recommends;
            is_deeply(\@actual, $weak ? [sort @images] : [], "$name $arch $pkg optional image recommendations");
            my @scripts = grep { /^xCAT-genesis-scripts-/ } split /\n/, $requires;
            is_deeply(\@scripts, $legacy{$arch}
                ? ["xCAT-genesis-scripts-$legacy{$arch} = 1:9.9.9-1"] : [],
                "$name $arch $pkg required legacy Genesis scripts");
            if ($arch eq 'riscv64') {
                like($requires, $pkg eq 'xCAT' ? qr/^ipmitool-xcat >= 1\.8\.18-4$/m : qr/^ipmitool-xcat >= 1\.8\.17-1$/m,
                    "$name $pkg RISC-V IPMI dependency");
                unlike($requires, qr/xCAT-genesis-scripts-|xnba-undi|syslinux-xcat|elilo-xcat|%\{/,
                    "$name $pkg RISC-V has no unavailable legacy payload or unresolved macro");
            }
        }
    }
    for my $s390 (0, 1) {
        local $ENV{s390x} = $s390;
        my $requires = query('xCAT-server', 'x86_64', $macro, '--requires');
        like($requires, qr/^perl\(Digest::SHA\)$/m, "$name server s390x=$s390 requires Digest::SHA");
        next if $s390;
        my $recommends = query('xCAT-server', 'x86_64', $macro, '--recommends');
        is(scalar(grep { $_ eq 'perl-DB_File' } split /\n/, $requires), $name eq 'EL10' ? 0 : 1,
            "$name server hard DB_File dependency");
        is(scalar(grep { $_ eq 'perl-DB_File' } split /\n/, $recommends), $name eq 'EL10' ? 1 : 0,
            "$name server weak DB_File dependency");
        like($requires, qr/^\Q$_\E$/m, "$name server keeps $_")
            for qw(perl-Net-Telnet perl-Net-DNS perl-Crypt-CBC perl-Crypt-Rijndael);
    }
}

for my $platform (@platforms) {
    my ($name, $macro) = @$platform;
    my ($rc, $filter, $err) = run_in(repo_path('.'), 'python3', '-c', <<'PY', repo_path('xCAT-server/xCAT-server.spec'), $macro);
import rpm, sys
for name in ('rhel', 'fedora', 'suse_version', 'openEuler'):
    rpm.delMacro(name)
name, value = sys.argv[2].split()
rpm.addMacro(name, value)
rpm.addMacro('version', '9.9.9')
rpm.addMacro('release', '1')
rpm.addMacro('__requires_exclude', '^retained$')
rpm.spec(sys.argv[1])
print(rpm.expandMacro('%{?__requires_exclude}'))
PY
    is($rc, 0, "$name parses server dependency generator policy") or BAIL_OUT($err);
    chomp $filter;
    ok('retained' =~ /$filter/, "$name keeps an inherited dependency filter");
    is('perl(DB_File)' =~ /$filter/ ? 1 : 0, $name eq 'EL10' ? 1 : 0,
        "$name automatic DB_File dependency exclusion");
    unlike('perl(Digest::SHA)', qr/$filter/, "$name keeps automatic Digest::SHA dependencies");
}

for my $case (['Linux', 'rhel 8', 'iproute'], ['SUSE', 'suse_version 1500', 'iproute2']) {
    my ($name, $macro, $provider) = @$case;
    my $requires = query('xCAT-probe', 'x86_64', $macro, '--requires');
    my @providers = grep { /^iproute2?$/ } split /\n/, $requires;
    is_deeply(\@providers, [$provider], "$name probe socket tool provider");
}
done_testing();

sub query {
    my ($package, $arch, $macro, $relation) = @_;
    my $format = $relation eq '--requires'
        ? '[%{REQUIRENAME} %{REQUIREFLAGS:depflags} %{REQUIREVERSION}\n]'
        : '[%{RECOMMENDNAME}\n]';
    my ($rc, $out, $err) = run_in(repo_path('.'), 'rpmspec', '-q', '--target', $arch,
        (map { ('--undefine', $_) } qw(rhel fedora suse_version openEuler)),
        '--define', $macro, '--define', 'version 9.9.9', '--define', 'release 1',
        '--qf', $format, repo_path("$package/$package.spec"));
    BAIL_OUT("$package $arch $macro: $err") if $rc;
    $out =~ s/[^\S\n]+$//mg;
    return $out;
}
