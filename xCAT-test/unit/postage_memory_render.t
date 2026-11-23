#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT", "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib grep { defined($_) } $ENV{XCAT_POSTAGE_MODULE_DIR};
use lib "$FindBin::Bin/../lib";
use Carp qw(croak);
use Storable qw(dclone);
use Test::More;

use XCAT::Test::PostageFixture qw(fixture write_file read_file inventory
    $root $custom $stock $callback $template $expected @responses);
require xCAT::Postage;

{
    package XCAT::PostageTest;
    sub fail_expansion { die "fixture expansion failed\n"; }
}

sub render {
    return scalar xCAT::Postage::makescript(['node1'], 'install', $callback, 0, 0, 'memory');
}

sub errors {
    return join('', map { @{$_->{error} || []} } @responses);
}

subtest 'custom in-memory rendering retains exact bytes without publishing' => sub {
    fixture(1);
    my $before = inventory();
    my $rows = dclone(\%xCAT::Table::rows);
    is(render(), $expected, 'real renderer preserves custom text, blank lines, arguments and ordered selection');
    is_deeply(inventory(), $before, 'template, stock template and all fixture paths are unchanged');
    is_deeply(\%xCAT::Table::rows, $rows, 'existing table records are unchanged');
    is_deeply(\@responses, [], 'private environment is not returned through ordinary callbacks');
    is(render(), $expected, 'repeat rendering returns the same bytes');
    is_deeply(inventory(), $before, 'repeat rendering creates no publication or template backup');
    done_testing();
};

subtest 'stock template and legacy return and publication modes' => sub {
    fixture(0);
    my $stock_expected = $expected;
    $stock_expected =~ s/ORIGIN='custom'/ORIGIN='stock'/;
    is(render(), $stock_expected, 'absence of an override selects the existing stock template');
    ok(!-e "$root/tftp/mypostscripts", 'memory rendering creates no public directory');
    my @legacy = xCAT::Postage::makescript(['node1'], 'install', $callback, 1, 1);
    ok(@legacy > 1, 'legacy nofiles caller still receives a line array');
    unlike(join('', @legacy), qr/\n\n/, 'legacy nofiles caller still omits blank lines');
    ok(-d "$root/tftp/mypostscripts", 'legacy directory behavior remains unchanged');
    is(xCAT::Postage::makescript(['node1'], 'install', $callback, 1, 0), 0,
        'legacy file caller keeps its success return');
    is(read_file("$root/tftp/mypostscripts/mypostscript.node1"), $stock_expected,
        'legacy publication keeps the full rendered file');
    fixture(1);
    my @custom_legacy = xCAT::Postage::makescript(['node1'], 'install', $callback, 1, 1);
    ok(@custom_legacy > 1, 'legacy custom-template caller still renders');
    is(read_file("$custom.backup"), $template, 'legacy addexports still retains its original template backup');
    like(read_file($custom), qr/^ZONENAME=\$ZONENAME$/m, 'legacy addexports still updates the custom template');
    done_testing();
};

subtest 'memory rendering retains the caller state before nodeset publishes it' => sub {
    for my $prior (qw(boot offline discover)) {
        fixture(0);
        write_file("$root/tftp/xcat/xnba/nodes/node1", "#!gpxe\n#$prior\n");
        write_file($stock, $template . "NODESETSTATE=\$NSETSTATE\n");
        like(render(), qr/^NODESETSTATE=install$/m,
            "sealed installation ignores prior $prior state");
        my $fallback = xCAT::Postage::makescript(['node1'], undef, $callback, 0, 0, 'memory');
        like($fallback, qr/^NODESETSTATE=\Q$prior\E$/m,
            "memory rendering without a supplied state uses published $prior state");
        my @legacy = xCAT::Postage::makescript(['node1'], 'install', $callback, 1, 1);
        like(join('', @legacy), qr/^NODESETSTATE=\Q$prior\E$/m,
            "legacy rendering still reads published $prior state");
    }
    done_testing();
};

subtest 'existing Ubuntu phase selection remains in the real renderer' => sub {
    fixture(0);
    $xCAT::Table::rows{nodetype}[0]{os} = 'ubuntu24.04';
    $xCAT::Table::rows{osimage}[0]{osvers} = 'ubuntu24.04';
    $xCAT::Table::rows{postscripts}[0]{postscripts} = 'syncfiles,first';
    my $text = render();
    like($text, qr/^# ubuntu-deferred-postbootscripts-start-here\nsyncfiles\n/m,
        'full renderer defers syncfiles on Ubuntu diskful install');
    my ($post) = $text =~ /# postscripts-start-here\n(.*?)# postscripts-end-here/s;
    unlike($post, qr/^syncfiles$/m, 'deferred entry is absent from the postscript phase');
    fixture(0);
    $xCAT::Table::rows{postscripts}[0]{postscripts} = 'syncfiles,first';
    like(render(), qr/^# defaults-postscripts-start-here\nsyncfiles\n/m,
        'FreeBSD retains its selected postscript entry');
    done_testing();
};

subtest 'invalid mode and node arguments fail before rendering side effects' => sub {
    for my $case (
        [['node1'], 'invalid', 'Invalid postscript rendering mode'],
        [['node1'], [], 'Invalid postscript rendering mode'],
        [[], 'memory', 'Memory rendering requires exactly one node'],
        [['node1', 'node2'], 'memory', 'Memory rendering requires exactly one node'],
        [[undef], 'memory', 'Memory rendering requires exactly one node'],
        [[''], 'memory', 'Memory rendering requires exactly one node'],
        [[{}], 'memory', 'Memory rendering requires exactly one node'],
        [undef, 'memory', 'Memory rendering requires exactly one node'],
    ) {
        fixture(1);
        my $before = inventory();
        my $result = xCAT::Postage::makescript($case->[0], 'install', $callback, 0, 0, $case->[1]);
        ok(!defined($result), 'invalid request returns no rendered text');
        is(errors(), $case->[2], 'invalid request reports its exact reason');
        is_deeply(\@xCAT::Table::opened, [], 'invalid request does not open tables');
        is_deeply(inventory(), $before, 'invalid request does not change files');
    }
    fixture(1);
    my $before = inventory();
    my ($result, $message);
    {
        open(my $capture, '>', \$message) or croak "stderr capture: $!";
        local *STDERR = $capture;
        $result = xCAT::Postage::makescript(['node1'], 'install', undef, 0, 0, 'memory');
    }
    ok(!defined($result), 'missing callback returns no text');
    is($message, "Memory rendering requires a callback\n", 'missing callback has an explicit error');
    is_deeply(\@xCAT::Table::opened, [], 'missing callback does not open tables');
    is_deeply(inventory(), $before, 'missing callback does not change files');
    done_testing();
};

subtest 'missing template, unknown node and excluded node never return a snapshot' => sub {
    fixture(0);
    unlink($stock) or croak "$stock: $!";
    my $before = inventory();
    ok(!defined(render()), 'missing template returns no text');
    like(errors(), qr/No mypostscript template exists/, 'missing template reports its existing error');
    is_deeply(inventory(), $before, 'missing template creates no public output');
    fixture(1);
    $xCAT::Table::rows{nodelist} = [];
    $before = inventory();
    ok(!defined(render()), 'unknown node returns no text');
    is(errors(), 'Unknown postscript node', 'unknown node has an explicit error');
    is_deeply(inventory(), $before, 'unknown node does not rewrite its template');
    fixture(1);
    $xCAT::Table::rows{nodetype}[0]{os} = '';
    $xCAT::Table::rows{nodetype}[0]{arch} = '';
    $before = inventory();
    ok(!defined(render()), 'excluded node returns no text');
    like(errors(), qr/No os or arch setting/, 'excluded node retains the renderer diagnostic');
    is_deeply(inventory(), $before, 'excluded node does not publish partial text');
    done_testing();
};

subtest 'reported and thrown expansion failures cannot return successful text' => sub {
    fixture(1);
    write_file($custom, $template . "export INVALID-NAME\n");
    my $before = inventory();
    ok(!defined(render()), 'invalid rendered export returns no text');
    like(errors(), qr/invalid charactor '-' .*INVALID-NAME/, 'invalid export retains its renderer error');
    is_deeply(inventory(), $before, 'reported expansion failure does not publish');
    fixture(1);
    write_file($custom, $template . '#Subroutine:XCAT::PostageTest::fail_expansion:$NODE#' . "\n");
    $before = inventory();
    my $result;
    my $ok = eval { $result = render(); 1; };
    ok(!$ok, 'real trusted expansion hook exception propagates');
    is($@, "fixture expansion failed\n", 'expansion exception is not replaced by a successful render');
    ok(!defined($result), 'throwing hook produces no text result');
    is_deeply(inventory(), $before, 'throwing hook leaves renderer-owned artifacts unchanged');
    done_testing();
};

done_testing();
