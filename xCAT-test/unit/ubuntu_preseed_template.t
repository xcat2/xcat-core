#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use XCAT::Test::Source qw(slurp_repo_file);

use Test::More;

my $tmpl = slurp_repo_file('xCAT-server/share/xcat/install/ubuntu/compute.tmpl');

like($tmpl, qr/^d-i apt-setup\/multiverse boolean false$/m, 'legacy Ubuntu preseed disables multiverse');
like($tmpl, qr/^d-i apt-setup\/universe boolean false$/m, 'legacy Ubuntu preseed disables universe');
like($tmpl, qr/^d-i apt-setup\/backports boolean false$/m, 'legacy Ubuntu preseed disables backports');
like($tmpl, qr/^d-i apt-setup\/updates boolean false$/m, 'legacy Ubuntu preseed disables release updates');
like($tmpl, qr/^d-i apt-setup\/services-select multiselect\s*$/m, 'legacy Ubuntu preseed disables security/update services for offline installs');
unlike($tmpl, qr/^d-i apt-setup\/services-select multiselect .*\S/m, 'legacy Ubuntu preseed does not select any external apt services');
like($tmpl, qr/sed -i .*security.*updates.*backports.*\/target\/etc\/apt\/sources\.list/s,
    'legacy Ubuntu late command comments disabled apt service suites in the installed target');

{
    my $template_pm = slurp_repo_file('xCAT-server/lib/perl/xCAT/Template.pm');

    like($template_pm, qr/\$ENV\{HTTPPORT\} \|\| \$ENV\{httpport\} \|\| '80'/,
        'legacy Ubuntu mirror spec uses the rendered HTTP port for local mirrors');
    like($template_pm, qr/d-i apt-setup\/security_host string \$security_host/,
        'legacy Ubuntu mirror spec redirects installer security host to rendered xCAT master');
    like($template_pm, qr/d-i apt-setup\/security_path string \$pkgdir/,
        'legacy Ubuntu mirror spec redirects installer security path to the local pkgdir');
}

done_testing();
