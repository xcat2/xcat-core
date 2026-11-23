#!/usr/bin/env perl
use strict;
use warnings;
use File::Temp ();
BEGIN {
    $ENV{XCATCFG} = 'SQLite:' . File::Temp::tempdir('xcat-freebsd-definitions-XXXXXXXX', TMPDIR => 1, CLEANUP => 1); ## no critic (Variables::RequireLocalizedPunctuationVars)
}
use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT", "$FindBin::Bin/../../xCAT-server/lib/perl";
use Carp qw(croak);
use POSIX ();
use Storable qw(dclone nstore_fd fd_retrieve);
use Test::More;
use xCAT::DBobjUtils;
use xCAT::Table;
use xCAT::Utils;

my $plugin = $ENV{XCAT_FREEBSD_DEFINITION_PLUGIN}
  || "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/DBobjectdefs.pm";
require $plugin;

sub command {
    my ($verb, $name, $force, $attributes) = @_;
    my @arguments = ('-t', 'osimage', '-o', $name, '--nocache');
    push @arguments, '-f' if $force;
    push @arguments, map { "$_=$attributes->{$_}" } sort keys %$attributes;
    pipe(my $reader, my $writer) or croak "pipe: $!";
    my $pid = xCAT::Utils->xfork();
    croak "fork: $!" unless defined($pid);
    if (!$pid) {
        close($reader) or croak "close pipe reader: $!";
        my @responses;
        xCAT_plugin::DBobjectdefs::process_request({ command => [$verb], stdin => [''], arg => \@arguments },
            sub { push @responses, dclone($_[0]) if defined($_[0]); },
            sub { croak "Unexpected external definition request\n"; });
        nstore_fd(\@responses, $writer);
        close($writer) or croak "close pipe writer: $!";
        POSIX::_exit(0);
    }
    close($writer) or croak "close parent pipe writer: $!";
    my $responses = fd_retrieve($reader);
    close($reader) or croak "close parent pipe reader: $!";
    waitpid($pid, 0) == $pid or croak "waitpid: $!";
    croak "Definition request process failed: $?" if $?;
    my @errors = grep { $_->{errorcode} && $_->{errorcode}[0] } @$responses;
    return (scalar(@errors), $responses);
}

sub attributes {
    my %attributes = @_;
    return { imagetype => 'freebsd', osname => 'FreeBSD', osvers => 'freebsd15.1',
        osarch => 'x86_64', provmethod => 'install', profile => 'compute', %attributes };
}

sub rows {
    my $name = shift;
    my %result;
    for my $table (qw(osimage freebsdimage linuximage winimage)) {
        my $handle = xCAT::Table->new($table, -create => 0);
        next unless $handle;
        my $entries = $handle->getAllEntries(1);
        my @matches = grep { defined($_->{imagename}) && $_->{imagename} eq $name } @$entries;
        $result{$table} = dclone(\@matches) if @matches;
        $handle->close();
    }
    return \%result;
}

sub definition {
    my $name = shift;
    local $::opt_nc = 1; ## no critic (Variables::ProhibitPackageVars)
    my %objects = ($name => 'osimage');
    my %definitions = xCAT::DBobjUtils->getobjdefs(\%objects);
    return $definitions{$name};
}

sub successful_command {
    my ($verb, $name, $force, $attributes, $label) = @_;
    my ($errors, $responses) = command($verb, $name, $force, $attributes);
    is($errors, 0, $label);
    diag(explain($responses)) if $errors;
    return;
}

sub rejected_replacement {
    my ($changes, $label) = @_;
    my $before = rows('legacy');
    my ($errors) = command('mkdef', 'legacy', 1, attributes(%$changes));
    ok($errors, "$label reports failure through the public command");
    is_deeply(rows('legacy'), $before, "$label preserves every existing image row");
    return;
}

successful_command('mkdef', 'legacy', 0,
    attributes(pkgdir => '/legacy/media', template => '/legacy/template', partitionfile => '/legacy/disk'),
    'public mkdef creates a legacy FreeBSD image in the private SQLite database');
is(definition('legacy')->{pkgdir}, '/legacy/media', 'legacy attributes round-trip through the real object reader');
ok(!exists(rows('legacy')->{linuximage}), 'legacy FreeBSD metadata does not create a Linux image row');

subtest 'invalid forced replacements retain the previous object' => sub {
    for my $version ('0', '3', '01', '2 ') {
        rejected_replacement({ imageversion => $version }, "invalid imageversion $version");
    }
    for my $field (qw(bootdir pkglist otherpkgdir otherpkglist)) {
        rejected_replacement({ imageversion => '1', $field => '/metadata/value' }, "legacy replacement with $field");
    }
    rejected_replacement({ imageversion => '2', bootdir => 'relative/boot' }, 'relative v2 boot directory');
    rejected_replacement({ imageversion => '2', pkgdir => '/repo/../base' }, 'noncanonical v2 base directory');
    rejected_replacement({ imageversion => '2', pkglist => '/policy/base,,/policy/kernel' }, 'empty v2 package-list member');
    rejected_replacement({ imageversion => '2', otherpkgdir => '/repo/apps,/repo/apps' }, 'duplicate v2 application repository');
};

my %metadata = (imageversion => '2', bootdir => '/images/boot', pkgdir => '/repositories/release/base',
    pkglist => '/policy/base,/policy/kernel', otherpkgdir => '/repositories/apps,/repositories/local',
    otherpkglist => '/policy/applications');
successful_command('mkdef', 'new-v2', 0, attributes(%metadata), 'public mkdef accepts complete v2 metadata');
my $created = definition('new-v2');
for my $field (sort keys %metadata) {
    is($created->{$field}, $metadata{$field}, "new v2 $field round-trips through the real object reader");
}
ok(!exists(rows('new-v2')->{linuximage}), 'v2 metadata does not create a Linux image row');

successful_command('mkdef', 'legacy', 1, attributes(%metadata), 'public mkdef -f accepts a valid v2 replacement');
my $replacement = definition('legacy');
for my $field (sort keys %metadata) {
    is($replacement->{$field}, $metadata{$field}, "replacement v2 $field is stored");
}
ok(!defined($replacement->{template}) && !defined($replacement->{partitionfile}),
    'valid forced replacement removes obsolete legacy fields through the real removal path');

successful_command('mkdef', 'incomplete-v2', 0, attributes(imageversion => '2'),
    'public mkdef accepts incomplete v2 metadata without claiming deployment readiness');
is(definition('incomplete-v2')->{imageversion}, '2', 'incomplete metadata retains its explicit version');
my $before = rows('new-v2');
my ($errors) = command('chdef', 'new-v2', 0, { imageversion => '1' });
ok($errors, 'partial chdef rejects a downgrade that retains v2-only metadata');
is_deeply(rows('new-v2'), $before, 'effective-value rejection preserves all v2 rows');
($errors) = command('chdef', 'new-v2', 0, { otherpkglist => 'relative/list' });
ok($errors, 'partial chdef validates a v2 field using the stored version');
is_deeply(rows('new-v2'), $before, 'invalid partial update preserves all stored rows');

successful_command('chdef', 'new-v2', 0, { map { $_ => '' } qw(bootdir pkglist otherpkgdir otherpkglist) },
    'public chdef permits explicit clearing of optional v2 metadata');
my $cleared = definition('new-v2');
for my $field (qw(bootdir pkglist otherpkgdir otherpkglist)) {
    ok(!defined($cleared->{$field}) || $cleared->{$field} eq '', "$field is cleared without an inferred default");
}
is($cleared->{imageversion}, '2', 'clearing optional fields retains the version');

successful_command('mkdef', 'linux-control', 0,
    { imagetype => 'linux', osname => 'Linux', osvers => 'rhels10', osarch => 'x86_64',
        provmethod => 'install', profile => 'compute', pkgdir => 'legacy-relative-path' },
    'non-FreeBSD image creation retains existing path semantics');
is(definition('linux-control')->{pkgdir}, 'legacy-relative-path', 'Linux metadata is not subject to FreeBSD canonical-path rules');
ok(!exists(rows('linux-control')->{freebsdimage}), 'Linux metadata does not create a FreeBSD image row');

done_testing();
