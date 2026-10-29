#!/usr/bin/env perl
use strict;
use warnings;

# Keep modules out of an installed /opt/xcat, so the checkout is what loads.
BEGIN { $ENV{XCATROOT} = '/nonexistent/xcatroot' }

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";

use Test::More;

use xCAT::Table;
use xCAT::TableUtils;
use xCAT::SELinux;

like($INC{'xCAT/SELinux.pm'}, qr/\Q$FindBin::Bin\E/,
    'xCAT::SELinux comes from this checkout, not from /opt/xcat');

# A table with node rows and group rows. getNodesAttribs gives a node row
# before a group row, as xCAT::Table does.
package FakeTable;

sub new {
    my ($class, %args) = @_;
    return bless {%args}, $class;
}

sub getNodesAttribs {
    my ($self, $nodes, $attrs) = @_;
    my %result;
    foreach my $node (@{$nodes}) {
        my @keys = ($node, @{ $self->{groups}{$node} || [] });
        my %row;
        foreach my $attr (@{$attrs}) {
            foreach my $key (@keys) {
                my $value = $self->{rows}{$key}{$attr};
                next unless defined $value && $value ne '';
                $row{$attr} = $value;
                last;
            }
        }
        $result{$node} = [ \%row ];
    }
    return \%result;
}

sub getAttribs {
    my ($self, $keys, @attrs) = @_;
    my $row = $self->{rows}{ $keys->{imagename} } or return undef;
    return { map { $_ => $row->{$_} } @attrs };
}

sub close { }

package main;

# Runs node_modes with the given table contents.
sub modes_for {
    my (%args) = @_;

    my %groups = %{ $args{groups} || {} };
    my %tables = (
        noderes  => FakeTable->new(rows => $args{noderes}  || {}, groups => \%groups),
        nodetype => FakeTable->new(rows => $args{nodetype} || {}, groups => \%groups),
        osimage  => FakeTable->new(rows => $args{osimage}  || {}),
    );
    my @opened;

    no warnings 'redefine';
    local *xCAT::Table::new = sub {
        my ($class, $name) = @_;
        push @opened, $name;
        return $tables{$name};
    };
    local *xCAT::TableUtils::get_site_attribute = sub {
        my ($class, $attr) = @_;
        return $attr eq 'selinux' ? $args{site} : undef;
    };

    my %reasons;
    my $modes = xCAT::SELinux->node_modes($args{nodes}, \%reasons);
    return ($modes, \%reasons, \@opened);
}

my %EL9 = (os => 'rhels9.4', provmethod => 'install');

# The node row wins over the group row and over the site.
{
    my ($modes) = modes_for(
        nodes    => ['cn1'],
        groups   => { cn1 => ['compute'] },
        noderes  => { cn1 => { selinux => 'permissive' }, compute => { selinux => 'disabled' } },
        nodetype => { cn1 => {%EL9} },
        site     => 'enforcing',
    );
    is_deeply($modes, { cn1 => 'permissive' }, 'a node row wins over its group row and the site');
}

# A group row applies to every member without a node row.
{
    my ($modes) = modes_for(
        nodes    => [qw(cn1 cn2)],
        groups   => { cn1 => ['compute'], cn2 => ['compute'] },
        noderes  => { compute => { selinux => 'permissive' } },
        nodetype => { compute => {%EL9} },
        site     => 'enforcing',
    );
    is_deeply($modes, { cn1 => 'permissive', cn2 => 'permissive' },
        'a group row wins over the site for every member');
}

# With no noderes value the site value applies.
{
    my ($modes) = modes_for(
        nodes    => ['cn1'],
        nodetype => { cn1 => {%EL9} },
        site     => 'enforcing',
    );
    is_deeply($modes, { cn1 => 'enforcing' }, 'the site value applies when noderes has none');
}

# Values are case insensitive.
{
    my ($modes) = modes_for(
        nodes    => ['cn1'],
        nodetype => { cn1 => {%EL9} },
        site     => ' Enforcing ',
    );
    is_deeply($modes, { cn1 => 'enforcing' }, 'the site value is trimmed and lower cased');
}

# No noderes value and no site key means disabled.
{
    my ($modes) = modes_for(
        nodes    => ['cn1'],
        nodetype => { cn1 => {%EL9} },
        site     => undef,
    );
    is_deeply($modes, { cn1 => 'disabled' }, 'an absent site.selinux resolves to disabled');
}

# site.selinux=disabled is a default, not a ceiling.
{
    my ($modes) = modes_for(
        nodes    => [qw(cn1 cn2)],
        noderes  => { cn1 => { selinux => 'enforcing' } },
        nodetype => { cn1 => {%EL9}, cn2 => {%EL9} },
        site     => 'disabled',
    );
    is_deeply($modes, { cn1 => 'enforcing', cn2 => 'disabled' },
        'a node row enables SELinux while the site says disabled');
}

# A value that is not a mode does not enable SELinux.
{
    my ($modes, $reasons) = modes_for(
        nodes    => ['cn1'],
        noderes  => { cn1 => { selinux => 'yes' } },
        nodetype => { cn1 => {%EL9} },
        site     => 'enforcing',
    );
    is_deeply($modes, { cn1 => 'disabled' }, 'an invalid noderes value resolves to disabled');
    like($reasons->{cn1}, qr/\byes\b/, '... and the reason names the invalid value');
}

# SLES and Ubuntu have no xCAT SELinux policy.
{
    my ($modes, $reasons) = modes_for(
        nodes    => [qw(sles ubu el)],
        nodetype => {
            sles => { os => 'sles15.5',     provmethod => 'install' },
            ubu  => { os => 'ubuntu22.04',  provmethod => 'netboot' },
            el   => { os => 'alma10.0',     provmethod => 'netboot' },
        },
        site => 'enforcing',
    );
    is_deeply($modes, { sles => 'disabled', ubu => 'disabled', el => 'enforcing' },
        'SLES and Ubuntu nodes resolve to disabled, an EL node keeps the site mode');
    like($reasons->{sles}, qr/sles15\.5/,   '... and the SLES reason names the OS');
    like($reasons->{ubu},  qr/ubuntu22\.04/, '... and the Ubuntu reason names the OS');
    ok(!exists $reasons->{el}, '... and the EL node has no reason');
}

# The OS of an osimage-provisioned node comes from the osimage row.
{
    my ($modes) = modes_for(
        nodes    => [qw(a b)],
        nodetype => {
            a => { os => 'rhels9.4', provmethod => 'sles15.5-x86_64-install-compute' },
            b => { provmethod => 'rocky9.4-x86_64-netboot-compute' },
        },
        osimage => {
            'sles15.5-x86_64-install-compute' =>
              { osvers => 'sles15.5', provmethod => 'install' },
            'rocky9.4-x86_64-netboot-compute' =>
              { osvers => 'rocky9.4', provmethod => 'netboot' },
        },
        site => 'enforcing',
    );
    is_deeply($modes, { a => 'disabled', b => 'enforcing' },
        'the osimage osvers decides the platform, not a stale nodetype.os');
}

# A node with no known OS cannot be matched to a policy.
{
    my ($modes) = modes_for(
        nodes => ['cn1'],
        site  => 'enforcing',
    );
    is_deeply($modes, { cn1 => 'disabled' }, 'a node with no OS resolves to disabled');
}

# Statelite resolves to disabled in this version.
{
    my ($modes, $reasons) = modes_for(
        nodes    => [qw(lite1 lite2)],
        noderes  => { lite1 => { selinux => 'enforcing' } },
        nodetype => {
            lite1 => { os => 'rhels9.4', provmethod => 'statelite' },
            lite2 => { provmethod => 'rhels9.4-x86_64-statelite-compute' },
        },
        osimage => {
            'rhels9.4-x86_64-statelite-compute' =>
              { osvers => 'rhels9.4', provmethod => 'statelite' },
        },
        site => 'enforcing',
    );
    is_deeply($modes, { lite1 => 'disabled', lite2 => 'disabled' },
        'statelite nodes resolve to disabled, by nodetype or by osimage provmethod');
    like($reasons->{lite1}, qr/statelite/, '... and the reason names statelite');
}

# An empty list gives an empty answer.
{
    my ($modes) = modes_for(nodes => [], site => 'enforcing');
    is_deeply($modes, {}, 'no nodes give an empty answer');
}

done_testing();
