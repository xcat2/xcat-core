#!/usr/bin/env perl
use strict;
use warnings;

# Keep modules out of an installed /opt/xcat, so the checkout is what loads.
BEGIN { $ENV{XCATROOT} = '/nonexistent/xcatroot' }

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";

use Test::More;

use xCAT::Schema;

like($INC{'xCAT/Schema.pm'}, qr/\Q$FindBin::Bin\E/,
    'xCAT::Schema comes from this checkout, not from /opt/xcat');

# noderes keys on a node or a group name, so one column gives the node and the
# group settings.
my $noderes = $xCAT::Schema::tabspec{noderes};
ok((grep { $_ eq 'selinux' } @{ $noderes->{cols} }),
    'noderes has a selinux column');
my $coldoc = $noderes->{descriptions}{selinux};
ok(defined $coldoc, '... and the column has a description');
like($coldoc // '', qr/\benforcing\b/,  '... that names enforcing');
like($coldoc // '', qr/\bpermissive\b/, '... and permissive');
like($coldoc // '', qr/\bdisabled\b/,   '... and disabled');
like($coldoc // '', qr/site\.selinux/,  '... and says site.selinux is the fallback');

foreach my $type (qw(node group)) {
    my @attrs = grep { $_->{attr_name} eq 'selinux' }
      @{ $xCAT::Schema::defspec{$type}{attrs} };
    is(scalar(@attrs), 1, "a $type object has one selinux attribute");
    is($attrs[0] && $attrs[0]{tabentry}, 'noderes.selinux',
        "... and the $type attribute is stored in noderes.selinux");
    is($attrs[0] && $attrs[0]{access_tabentry}, 'noderes.node=attr:node',
        "... and the $type row is found by the node column");
}

my $sitedoc = $xCAT::Schema::tabspec{site}{descriptions}{key};
my ($selinux_help) = $sitedoc =~ /^( selinux:.*?)(?:\n\n|\z)/ms;
ok(defined $selinux_help, 'the site table help describes the selinux key');
like($selinux_help // '', qr/\benforcing\b/,  '... with the enforcing value');
like($selinux_help // '', qr/\bpermissive\b/, '... the permissive value');
like($selinux_help // '', qr/\bdisabled\b/,   '... and the disabled value');
like($selinux_help // '', qr/not set.*\bdisabled\b/s,
    '... and says an unset key means disabled');
like($selinux_help // '', qr/noderes\.selinux/,
    '... and names the node and group override');

done_testing();
