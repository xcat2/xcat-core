#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

my $tmpl_path = defined $ENV{XCATROOT} ? "$ENV{XCATROOT}/share/xcat/install/ubuntu/compute.subiquity.tmpl" : '';
$tmpl_path = "xCAT-server/share/xcat/install/ubuntu/compute.subiquity.tmpl"
    unless -f $tmpl_path;

plan skip_all => "compute.subiquity.tmpl not found" unless -f $tmpl_path;

my $tmpl = do { local $/; open my $fh, '<', $tmpl_path or die $!; <$fh> };

like($tmpl, qr/^#cloud-config/, 'template starts with #cloud-config');
like($tmpl, qr/autoinstall:/, 'template has autoinstall: key');
like($tmpl, qr/version:\s*1/, 'template has version: 1');

like($tmpl, qr/^\s*identity:/m, 'template has an identity section so subiquity does not prompt');
like($tmpl, qr/kernel:/, 'template has kernel section');
like($tmpl, qr/package:\s*linux-generic/, 'template specifies linux-generic kernel');
like($tmpl, qr/#UBUNTU_SUBIQUITY_APT_CONFIG#/, 'template renders apt section from osimage context');
unlike($tmpl, qr/^\s*apt:/m, 'template does not carry a static apt section');
unlike($tmpl, qr/WARN: no partitionfile/, 'template does not silently fall back when xCAT pre-script fails');
unlike($tmpl, qr/INSTALL_DISK=""/, 'template does not guess an install disk in early-commands');
unlike($tmpl, qr/geoip:\s*true/, 'template does not enable geoip');

like($tmpl, qr/ssh:/, 'template has ssh section');
like($tmpl, qr/install-server:\s*true/, 'template enables ssh install-server');

unlike($tmpl, qr/package_update:\s*true/, 'template does not enable package_update');
unlike($tmpl, qr/^\s*-\s+nfs-common\s*$/m, 'template does not require nfs-common from offline ISO packages');

# YAML safety: use printf with single-quoted arguments instead of shell-specific
# escape sequences. dash does not portably interpret printf \xNN.
unlike($tmpl, qr/echo.*GRUB_CMDLINE.*\\"/, 'no escaped double quotes in echo GRUB line');
unlike($tmpl, qr/\\\\x22/, 'template does not rely on non-portable printf hex escapes');
like($tmpl, qr/printf ''%s\\n'' ''GRUB_CMDLINE_LINUX="#TABLEBLANKOKAY:bootparams:\$NODE:kcmdline#"''/, 'GRUB line uses portable printf quoting');
like($tmpl, qr/\/target\/etc\/netplan\/00-xcat-install\.yaml/, 'template writes an xCAT-owned target netplan file');
# Regression: an UNSET noderes.installnic must not fatally break Subiquity xnba generation, and
# the interface must still be resolved in xCAT's order (installnic -> primarynic -> mac.mac). The
# template read #TABLE:noderes:$NODE:installnic#, and Template.pm's tabdb raises "Unable to find
# requested field <installnic> from table <noderes>" -> "Failed to generate xnba configurations"
# when the node carries no installnic, so the Ubuntu diskful install never started. The resolution
# now happens in Perl (xCAT::Template, via xCAT::NetworkUtils::gen_net_boot_params) and reaches the
# template already resolved, so no part of that order is re-derived in shell. The resolution itself
# and the netplan it produces are covered by ubuntu_subiquity_installnic.t.
unlike($tmpl, qr/noderes:\$NODE:(?:installnic|primarynic)/,
    'the template does not read installnic/primarynic itself (fatal when unset, and it would have to redo the fallback)');
like($tmpl, qr/installnic="#SUBIQUITYINSTALLNIC#"/,
    'the target netplan uses the interface name xCAT resolved for this node');
like($tmpl, qr/installmac="#SUBIQUITYINSTALLMAC#"/,
    'the target netplan uses the MAC address xCAT resolved for this node');
like($tmpl, qr/if \[ -z "\$\{installnic\}" \]; then/,
    'no resolved interface name means match by MAC alone, with no set-name rename');
unlike($tmpl, qr/tr ''A-F'' ''a-f''/,
    'the shell no longer normalizes the MAC (Template.pm resolves mac.mac entries)');
unlike($tmpl, qr/cut -d''\|'' -f1/,
    'the shell no longer splits mac.mac entries (Template.pm resolves them for this node)');
like($tmpl, qr/printf ''%s\\n'' "network:" "  version: 2" "  ethernets:" "    xcat-install:" "      match:" "        macaddress: \\"\$\{installmac\}\\"" "      set-name: \$\{installnic\}" "      dhcp4: true" >\/target\/etc\/netplan\/00-xcat-install\.yaml;/, 'target netplan printf stays on one shell line');
like($tmpl, qr/"        macaddress: \\"\$\{installmac\}\\""/, 'target netplan matches by MAC address');
like($tmpl, qr/"      set-name: \$\{installnic\}"/, 'target netplan sets the expected installnic name');
like($tmpl, qr/"\s+dhcp4: true"/, 'target netplan enables DHCPv4 on installnic');
like($tmpl, qr/printf ''%s\\n'' ''#HOSTNAME#'' >\/target\/etc\/hostname/, 'template writes target hostname before disabling cloud-init');
like($tmpl, qr/sed -i ''s\/\^127\\\.0\\\.1\\\.1\.\*\/127\.0\.1\.1 #HOSTNAME#\/'' \/target\/etc\/hosts/, 'template updates target hosts entry for hostname');
like($tmpl, qr/touch \/target\/etc\/cloud\/cloud-init\.disabled/, 'target cloud-init is disabled after target netplan is written');

# Regression: downloaded files are required and checked with test -s before use.
like($tmpl, qr/wget -T 30 -O \/tmp\/getinstdisk http:\/\/#XCATVAR:XCATMASTER#/, 'getinstdisk download is required');
like($tmpl, qr/test -s \/tmp\/getinstdisk/, 'getinstdisk checked with -s not -x');
like($tmpl, qr/wget -T 30 -O \/tmp\/pre\.sh http:\/\/#XCATVAR:XCATMASTER#/, 'pre.sh download is required');
like($tmpl, qr/test -s \/tmp\/pre\.sh/, 'pre.sh checked with -s not -x');
like($tmpl, qr/test -s \/tmp\/partitionfile/, 'partitionfile from pre-script is required');
unlike($tmpl, qr/wget .*?\|\| true/, 'xCAT control artifact downloads are not masked');
unlike($tmpl, qr/if \[ -x \/tmp\/getinstdisk \]/, 'getinstdisk not checked with -x');
unlike($tmpl, qr/if \[ -x \/tmp\/pre\.sh \]/, 'pre.sh not checked with -x');

# Regression: apt configuration is generated by Template.pm so release-specific
# Subiquity behavior can be handled without cloning this template per release.
unlike($tmpl, qr/noble-|jammy-|focal-/, 'template avoids release-specific apt suite names');
like($tmpl, qr/#UBUNTU_SUBIQUITY_APT_CONFIG#/, 'template keeps dynamic apt renderer marker');

done_testing();
