#!/usr/bin/env perl
use strict;
use warnings;

# Keep modules out of an installed /opt/xcat, so the checkout is what loads.
BEGIN { $ENV{XCATROOT} = '/nonexistent/xcatroot' }

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-probe/lib/perl";

use Test::More;

require probe_utils;

like($INC{'probe_utils.pm'}, qr/\Q$FindBin::Bin\E/, 'probe_utils comes from this checkout');

# semodule -l prints one module per line; EL8 adds a version column.
my $loaded_el9  = "abrt\nxcat\nzosremote\n";
my $loaded_el8  = "abrt\t1.4.1\nxcat\t1.0.0\n";
my $not_loaded  = "abrt\nxcatlike\nzosremote\n";
my @good_labels = (
    [ '/install',  'public_content_t', 'system_u:object_r:public_content_t:s0' ],
    [ '/tftpboot', 'tftpdir_t',        'system_u:object_r:tftpdir_t:s0' ],
);

my ($flag, $msg) = probe_utils::selinux_policy_verdict('disabled', '', []);
is($flag, 'o', 'SELinux disabled is ok, whatever the module');
like($msg, qr/disabled/, 'the message names the disabled mode');

foreach my $modules ($loaded_el9, $loaded_el8) {
    ($flag, $msg) = probe_utils::selinux_policy_verdict('enforcing', $modules, \@good_labels);
    is($flag, 'o', 'enforcing with the xcat module and the expected labels is ok');
}

($flag, $msg) = probe_utils::selinux_policy_verdict('enforcing', $not_loaded, \@good_labels);
is($flag, 'f', 'enforcing without the xcat module fails');
like($msg, qr/xcat SELinux module is not loaded/, 'the failure names the missing module');
unlike($msg, qr{/install}, 'the failure does not blame a label that is correct');

my @bad_labels = (
    [ '/install',  'public_content_t', 'system_u:object_r:default_t:s0' ],
    [ '/tftpboot', 'tftpdir_t',        undef ],
);
($flag, $msg) = probe_utils::selinux_policy_verdict('enforcing', $loaded_el9, \@bad_labels);
is($flag, 'f', 'enforcing with a wrong label fails');
like($msg, qr{/install has type default_t, expected public_content_t}, 'the failure names the path, its type and the expected type');
like($msg, qr{/tftpboot has no SELinux label, expected tftpdir_t}, 'a path with no label is a failure');
unlike($msg, qr/module/, 'the failure does not blame a module that is loaded');

($flag, $msg) = probe_utils::selinux_policy_verdict('permissive', $not_loaded, \@bad_labels);
is($flag, 'w', 'permissive turns the same findings into a warning');
like($msg, qr/module.*default_t/s, 'the warning lists every finding');

($flag, $msg) = probe_utils::selinux_policy_verdict('permissive', $loaded_el9, \@good_labels);
is($flag, 'o', 'permissive with the module and the labels is ok');

done_testing();
