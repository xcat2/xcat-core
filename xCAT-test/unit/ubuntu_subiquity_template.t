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
like($tmpl, qr/^    - #INCLUDE_DEFAULT_PKGLIST_AUTOINSTALL#\n/m, 'the packages list carries the osimage pkglist through the autoinstall token');
like($tmpl, qr/^    - openssh-server\n/m, '... and keeps openssh-server, which xCAT needs on the node');
like($tmpl, qr/^    - wget\n/m, '... and wget, which the early and late commands use');
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
like($tmpl, qr{2>&1'\n(?:\s*#[^\n]*\n)*\s*- rm -f (?:/target/etc/apt/sources\.list\.d/xcat-(?:otherpkgs|pkgdir)-\*\.(?:list|sources)\s+){4}/target/etc/apt/apt\.conf\.d/94curtin-config$}m,
    'the installer sources for the otherpkgs repository and the pkgdir mirrors, and the apt configuration curtin wrote, are removed from the target by a late-command of their own, after the post script block');

# the post script block: its status is the post script's, so a failed post script stops the install
{
    my ($block) = $tmpl =~ /\n    - '(\{\n.*?\n    \} >>\/target\/var\/log\/xcat\/xcat\.log 2>&1)'\n/s;
    ok( defined $block, 'the post script block is found' ) or last;
    $block =~ s/''/'/g;
    require File::Temp;
    my $root = File::Temp->newdir();
    mkdir "$root/bin" or die;
    for my $tool ( 'curtin', 'wget' ) {
        open( my $fh, '>', "$root/bin/$tool" ) or die;
        print {$fh} $tool eq 'curtin' ? "#!/bin/sh\ncase \"\$*\" in *post.script*) exit 42;; esac\nexit 0\n" : "#!/bin/sh\nfor a; do case \"\$a\" in http*) touch \"\${a##*/}\";; esac; done\nexit 0\n";
        close $fh; chmod 0755, "$root/bin/$tool";
    }
    ( my $script = $block ) =~ s{/target}{$root/target}g;
    $script =~ s{/tmp/pre-install\.log}{$root/pre-install.log}g;
    for my $token ( [ '#SUBIQUITYINSTALLNIC#', '' ], [ '#SUBIQUITYINSTALLMAC#', '52:54:00:00:00:01' ], [ '#HOSTNAME#', 'cn1' ], [ '#XCATVAR:XCATMASTER#', '192.0.2.10' ],
        [ '#COLONHTTPPORT#', '' ], [ '#TABLEBLANKOKAY:bootparams:$NODE:kcmdline#', '' ] ) {
        $script =~ s/\Q$token->[0]\E/$token->[1]/g;
    }
    require File::Path;
    File::Path::make_path( map { "$root/target/$_" } qw(etc/default root var/log/xcat) );
    open( my $hosts, '>', "$root/target/etc/hosts" ) or die; print {$hosts} "127.0.0.1 localhost\n"; close $hosts;
    open( my $pre, '>', "$root/pre-install.log" ) or die; close $pre;
    my $cwd = File::Spec->rel2abs('.');
    chdir $root or die;
    local $ENV{PATH} = "$root/bin:$ENV{PATH}";
    system( 'sh', '-c', $script );
    my $status = $? >> 8;
    chdir $cwd or die;
    is( $status, 42, 'a failing post script fails the late-command block, so Subiquity stops the install instead of switching the node to disk boot' );
}

done_testing();
