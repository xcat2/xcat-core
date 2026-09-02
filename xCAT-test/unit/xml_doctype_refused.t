#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use Test::More;

my $libdir = "$FindBin::Bin/../../xCAT-server/lib/perl";
my $xmlpm  = "$libdir/xCAT/XML.pm";
plan skip_all => 'xCAT::XML not found' unless -r $xmlpm;
eval { require XML::Simple; require XML::Parser; 1 }
    or plan skip_all => 'XML::Simple and XML::Parser are required';

# xCAT::XML loads xCAT::MsgUtils, which loads much of the xCAT tree. The parser
# paths never call it. Stub it before loading xCAT::XML.
BEGIN { $INC{'xCAT/MsgUtils.pm'} = 1; }
{ package xCAT::MsgUtils; }

unshift @INC, $libdir;
require xCAT::XML;
require Data::Dumper;

# An entity that names another entity grows the document on every level.
my $in_text = <<'XML';
<?xml version="1.0"?>
<!DOCTYPE r [ <!ENTITY a "AAAAAAAAAA"> <!ENTITY b "&a;&a;&a;&a;&a;"> ]>
<data>&b;</data>
XML

# The same growth, with the reference inside an attribute value. The option
# that stops the parser expanding an entity does not reach an attribute, so
# this is the case that a refusal of the declaration has to cover.
my $in_attribute = <<'XML';
<?xml version="1.0"?>
<!DOCTYPE r [ <!ENTITY a "AAAAAAAAAA"> <!ENTITY b "&a;&a;&a;&a;&a;"> ]>
<data><child attr="&b;">t</child></data>
XML

# A declaration that carries no entity at all is still refused.
my $bare_doctype = <<'XML';
<?xml version="1.0"?>
<!DOCTYPE xcatrequest>
<xcatrequest><command>rpower</command></xcatrequest>
XML

# What a request normally looks like.
my $ordinary =
  '<?xml version="1.0"?><xcatrequest><command>rpower</command>'
  . '<noderange>n1</noderange><arg>stat</arg></xcatrequest>';

sub parse_doc {
    my ($doc) = @_;
    my $tree = eval { xCAT::XML->new->XMLin($doc, SuppressEmpty => undef, ForceArray => 1) };
    return ($@, defined($tree) ? Data::Dumper::Dumper($tree) : '');
}

sub check_path {
    my ($label) = @_;

    foreach my $case ([ 'in element text', $in_text ],
                      [ 'in an attribute', $in_attribute ],
                      [ 'with no entity',  $bare_doctype ]) {
        my ($name, $doc) = @$case;
        my ($err, $dump) = parse_doc($doc);
        isnt($err, '', "$label: a declaration $name is refused");
        unlike($dump, qr/AAAAAAAAAA/, "$label: nothing expands for a declaration $name");
    }

    my ($err, $dump) = parse_doc($ordinary);
    is($err, '', "$label: an ordinary request parses");
    like($dump, qr/rpower/, "$label: the command of an ordinary request survives");
    like($dump, qr/n1/,     "$label: the noderange of an ordinary request survives");
    like($dump, qr/stat/,   "$label: the argument of an ordinary request survives");
}

# The modern path: XML::Simple with new_xml_parser.
SKIP: {
    skip 'XML::Simple lacks new_xml_parser on this system', 10
        unless exists &{'XML::Simple::new_xml_parser'};
    check_path('modern path');
}

# Force the older compatibility path (build_tree_xml_parser's own code) by
# removing new_xml_parser, as on XML::Simple 2.20-2.24.
{
    no strict 'refs';
    no warnings 'redefine';
    undef *{'XML::Simple::new_xml_parser'} if exists &{'XML::Simple::new_xml_parser'};
}
ok(!exists &{'XML::Simple::new_xml_parser'}, 'compatibility path is forced');
check_path('compatibility path');

done_testing();
