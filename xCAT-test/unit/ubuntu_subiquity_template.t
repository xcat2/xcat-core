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
# Regression (issue #47): an UNSET noderes.installnic must not fatally break Subiquity xnba
# generation. EL/SLES statefull templates never reference installnic, so they default gracefully;
# but this template resolved #TABLE:noderes:$NODE:installnic#, and Template.pm's tabdb raises
# "Unable to find requested field <installnic> from table <noderes>" -> "Failed to generate xnba
# configurations" when the node has no installnic value, so the Ubuntu diskful install never starts.
# The template must use the non-fatal #TABLEBLANKOKAY# token (renders blank when unset) and treat an
# empty installnic the same as "mac" (match by MAC, no NIC rename) -- the EL-equivalent default.
unlike($tmpl, qr/installnic="#TABLE:noderes:\$NODE:installnic#"/,
    'installnic does NOT use the fatal #TABLE# token (it errors when installnic is unset)');
like($tmpl, qr/installnic="#TABLEBLANKOKAY:noderes:\$NODE:installnic#"/,
    'installnic uses the non-fatal #TABLEBLANKOKAY# token so an unset installnic renders blank');
like($tmpl, qr/if \[ "\$\{installnic\}" = "mac" \] \|\| \[ -z "\$\{installnic\}" \]; then/,
    'an empty installnic is handled like "mac" (match by MAC, no set-name rename)');
like($tmpl, qr/installmac="#TABLE:mac:\$NODE:mac#"/, 'target netplan uses node MAC');
like($tmpl, qr/installmac="\$\(printf ''%s'' "\$\{installmac\}".*\| tr ''A-F'' ''a-f''\)"/, 'target netplan normalizes MAC case');
like($tmpl, qr/installmac="\$\(printf ''%s'' "\$\{installmac\}" \| cut -d''\|'' -f1 \| cut -d''!'' -f1/, 'target netplan strips mac table suffixes before matching');
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

# Regression: after the install the node MUST be flipped to local-disk boot, or it
# PXE-loops back into the installer and the installed OS (with sshd) never boots -->
# the diskful test only ever sees "ssh: connect ... port 22: Connection refused".
# xCAT flips the netboot state when the node reports "next" to xcatd:3002. The
# in-target post-script does this via gawk's updateflag.awk, but Ubuntu's /usr/bin/awk
# is often mawk (no |& / /inet coprocess) so the flip silently fails. The template
# must therefore trigger the flip itself from the live installer, dependency-free.
like($tmpl, qr{/dev/tcp/\$xm/3002},
    'template flips the node to local boot by contacting xcatd:3002 from the installer');
like($tmpl, qr{printf 'next\\\\n' >&3},
    'template sends the "next" destiny token that makes xcatd run "nodeset <node> next"');
like($tmpl, qr{^\s*-\s*\["bash",\s*"-c",}m,
    'flip runs under bash (dash has no /dev/tcp) via an argv list command');
like($tmpl, qr{xm=#XCATVAR:XCATMASTER#},
    'flip targets the node\'s xcatmaster');

# Regression: apt configuration is generated by Template.pm so release-specific
# Subiquity behavior can be handled without cloning this template per release.
unlike($tmpl, qr/noble-|jammy-|focal-/, 'template avoids release-specific apt suite names');
like($tmpl, qr/#UBUNTU_SUBIQUITY_APT_CONFIG#/, 'template keeps dynamic apt renderer marker');

done_testing();
