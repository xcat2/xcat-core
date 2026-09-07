#!/usr/bin/env perl
use strict;
use warnings;
BEGIN { $ENV{XCATCFG} ||= 'SQLite:/tmp'; }
use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";
use Test::More;
use xCAT::DBobjUtils;
use xCAT::Schema;

for my $column (qw(imagename template pkgdir partitionfile comments disable)) {
    is(scalar(grep { $_ eq $column } @{$xCAT::Schema::tabspec{freebsdimage}{cols}}),
        1, "FreeBSD extension retains one $column column");
}
is_deeply($xCAT::Schema::tabspec{freebsdimage}{keys}, ['imagename'],
    'FreeBSD extension uses the logical image name');

my %attrs = (
    objtype => 'osimage', imagetype => 'freebsd', osname => 'FreeBSD',
    osvers => 'freebsd15.1', osarch => 'x86_64', provmethod => 'install',
    template => '/opt/xcat/share/xcat/install/freebsd/compute.tmpl',
    pkgdir => '/install/freebsd15.1/x86_64/bundle',
    partitionfile => '/install/custom/freebsd/disk.conf', usercomment => 'test image',
);
my @errors = xCAT::DBobjUtils->validate_only_if_attrs('test-image', 'osimage', \%attrs, {});
is_deeply(\@errors, [], 'object validation accepts the FreeBSD configuration fields');
for my $attr (qw(boottarget addkcmdline rootimgdir kernelver driverupdatesrc)) {
    my %invalid = (objtype => 'osimage', imagetype => 'freebsd', $attr => 'unsupported');
    my @failures = xCAT::DBobjUtils->validate_only_if_attrs('test-image', 'osimage', \%invalid, {});
    is(scalar(@failures), 1, "FreeBSD rejects unsupported $attr");
    is($failures[0]{attr}, $attr, 'validation identifies the rejected field');
}
for my $family (qw(linux windows)) {
    my %existing = (objtype => 'osimage', imagetype => $family, template => '/tmp/template');
    my @failures = xCAT::DBobjUtils->validate_only_if_attrs('existing-image', 'osimage', \%existing, {});
    is_deeply(\@failures, [], "$family template routing remains valid");
}

{
    package FreeBSDImageSchema::Table;
    sub setAttribs {
        my ($self, $keys, $updates) = @_;
        push @{$self->{writes}}, { table => $self->{name}, keys => {%$keys}, updates => {%$updates} };
        return (1, undef);
    }
    sub delEntries {
        my ($self, $keys) = @_;
        push @{$self->{deletes}}, $self->{name};
        return 1;
    }
    sub commit { return 1; }
}
{
    my (@writes, @deletes);
    no warnings 'redefine';
    local *xCAT::DBobjUtils::getobjdefs = sub { return (); };
    local *xCAT::Table::getTableSchema = sub { return {keys => ['imagename']}; };
    local *xCAT::Table::new = sub {
        return bless {name => $_[1], writes => \@writes, deletes => \@deletes}, 'FreeBSDImageSchema::Table';
    };
    my %legacy_with_pkglist = (%attrs, pkglist => '/tmp/base.pkglist');
    is(xCAT::DBobjUtils->setobjdefs({'legacy-invalid' => \%legacy_with_pkglist}), 1,
        'legacy FreeBSD rejects pkglist through the public object writer');
    is_deeply(\@writes, [], 'legacy pkglist rejection performs no table writes');
    is(xCAT::DBobjUtils->setobjdefs({'test-image' => \%attrs}), 0, 'generic object writer accepts FreeBSD image');
    my @extensions = grep { $_->{table} =~ /image$/ && $_->{table} ne 'osimage' } @writes;
    is_deeply([map { $_->{table} } @extensions], ['freebsdimage'], 'configuration goes only to FreeBSD extension');
    is_deeply($extensions[0]{keys}, {imagename => 'test-image'}, 'extension row uses the image key');
    for my $attr (qw(template pkgdir partitionfile)) {
        is($extensions[0]{updates}{$attr}, $attrs{$attr}, "$attr reaches the FreeBSD extension");
    }
    is($extensions[0]{updates}{comments}, $attrs{usercomment}, 'user comment reaches the FreeBSD extension');
    is(xCAT::DBobjUtils->rmobjdefs({'test-image' => 'osimage'}), 0, 'generic object removal accepts image');
    ok(scalar(grep { $_ eq 'freebsdimage' } @deletes), 'image removal includes FreeBSD extension');
}
done_testing();
