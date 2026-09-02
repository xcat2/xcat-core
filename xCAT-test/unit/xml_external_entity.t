#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use File::Temp qw(tempfile);
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

# Prepend so the source-tree module wins over any installed xCAT::XML.
unshift @INC, $libdir;
require xCAT::XML;
require Data::Dumper;

my ($sfh, $secret_path) = tempfile('xcat_xxe_XXXXXX', TMPDIR => 1, UNLINK => 1);
print {$sfh} "SECRET-CONTENT-DO-NOT-LEAK";
close $sfh;

my $payload = <<"XML";
<?xml version="1.0"?>
<!DOCTYPE r [ <!ENTITY xxe SYSTEM "file://$secret_path"> ]>
<data>&xxe;</data>
XML

sub parsed_tree {
    my $parser = xCAT::XML->new;
    my $tree = eval { $parser->XMLin($payload, SuppressEmpty => undef, ForceArray => 1) };
    return ($tree, $@);
}

# The contract this file guards is that the contents of the file an external
# entity names never reach the parsed document. A parser path may deliver that
# either by parsing the payload and leaving the entity unresolved, or by
# refusing the payload. Assert the outcome, not the route.
sub check_path {
    my ($label) = @_;
    my ($tree, $error) = parsed_tree();
    my $dump = defined($tree) ? Data::Dumper::Dumper($tree) : '';
    unlike($dump, qr/SECRET-CONTENT-DO-NOT-LEAK/,
        "$label: the external entity content is not read");
    unlike($error, qr/SECRET-CONTENT-DO-NOT-LEAK/,
        "$label: the external entity content does not reach the error either");
}

# The modern path: XML::Simple with new_xml_parser.
SKIP: {
    skip 'XML::Simple lacks new_xml_parser on this system', 2
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
