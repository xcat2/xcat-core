#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use File::Slurper qw(read_lines);
use Test::More;

# The spec files and the file context list are the artifacts: rpmbuild and
# semodule read them as written.
my $root = "$FindBin::Bin/../..";

# Returns the lines of a file, or an empty list when the file is not there.
sub lines_of {
    my ($path) = @_;
    return -f $path ? read_lines($path) : ();
}

# Splits a spec into its preamble and its %sections, keyed by section name.
sub spec_sections {
    my (@lines) = @_;

    my %sections = (preamble => []);
    my $current = 'preamble';
    foreach my $line (@lines) {
        if ($line =~ /^%(prep|build|install|check|clean|files|changelog|description|package|pre|post|preun|postun|pretrans|posttrans)\b/) {
            $current = $1;
            $sections{$current} ||= [];
            next;
        }
        push @{ $sections{$current} }, $line;
    }

    return \%sections;
}

# The %if line that encloses line $index, or undef at the top level.
sub enclosing_if {
    my ($lines, $index) = @_;

    my $depth = 0;
    for (my $i = $index - 1 ; $i >= 0 ; $i--) {
        my $line = $lines->[$i];
        if ($line =~ /^%endif\b/) {
            $depth++;
        } elsif ($line =~ /^%if(?:os|arch|narch|nos)?\b/) {
            return $line if $depth == 0;
            $depth--;
        }
    }

    return undef;
}

my $spec_path = "$root/xCAT-selinux/xCAT-selinux.spec";
ok(-f $spec_path, 'xCAT-selinux has a spec');
my $spec = spec_sections(lines_of($spec_path));
my $preamble = join("\n", @{ $spec->{preamble} });

like($preamble, qr/^Name:\s*xCAT-selinux\s*$/m, 'the package is named xCAT-selinux');
like($preamble, qr/^BuildArch:\s*noarch\s*$/m, '... and is noarch');
like($preamble, qr/^Source:\s*xCAT-selinux-%\{version\}\.tar\.gz\s*$/m,
    '... and builds from the tarball that buildrpms.pl makes of the package directory');
like($preamble, qr/^BuildRequires:.*\bselinux-policy-devel\b/m,
    '... and needs selinux-policy-devel to build the module');
like($preamble, qr/^Requires:.*\bselinux-policy-targeted\b/m,
    '... and needs the targeted policy');
like($preamble, qr/^Requires\(post\):.*\bpolicycoreutils\b/m,
    '... and needs semodule in %post');
unlike($preamble, qr/selinux_requires/,
    '... and does not pin selinux-policy to the version of the build host');

my $build = join("\n", @{ $spec->{build} || [] });
like($build, qr{make -f %\{_datadir\}/selinux/devel/Makefile\b.*\bxcat\.pp\b},
    '%build compiles xcat.pp with the selinux-policy-devel Makefile');
like($build, qr{checkmodule -M -c 19\b},
    '... at module version 19, which the EL8 policy tools read');

my $install = join("\n", @{ $spec->{install} || [] });
like($install, qr{%\{_datadir\}/selinux/packages/targeted\b},
    '%install puts the module in the targeted package directory');

my $files = join("\n", @{ $spec->{files} || [] });
like($files, qr{^%\{_datadir\}/selinux/packages/targeted/xcat\.pp\.bz2$}m,
    '%files ships xcat.pp.bz2');

like(join("\n", @{ $spec->{pre} || [] }), qr/^%selinux_relabel_pre -s targeted$/m,
    '%pre saves the file contexts before the module changes them');
like(join("\n", @{ $spec->{post} || [] }),
    qr{^%selinux_modules_install -s targeted %\{_datadir\}/selinux/packages/targeted/xcat\.pp\.bz2$}m,
    '%post installs the module');
like(join("\n", @{ $spec->{postun} || [] }), qr/^%selinux_modules_uninstall -s targeted xcat$/m,
    '%postun removes the module');
my $posttrans = join("\n", @{ $spec->{posttrans} || [] });
like($posttrans, qr/^%selinux_relabel_post -s targeted$/m,
    '%posttrans relabels the files whose context changed');
like($posttrans, qr{\brestorecon -R /install\b}, '... and relabels /install');
foreach my $section (qw(pre post postun posttrans)) {
    unlike(join("\n", @{ $spec->{$section} || [] }), qr/\bsetenforce\b|\/etc\/selinux\/config/,
        "%$section does not change the SELinux mode");
}

my @fc = grep { !/^\s*(?:#|$)/ } lines_of("$root/xCAT-selinux/xcat.fc");
my %fc = map { (split /\s+/, $_, 2) } @fc;
is($fc{'/install(/.*)?'}, 'gen_context(system_u:object_r:public_content_t,s0)',
    '/install is public_content_t');
is($fc{'/install/netboot/[^/]+/[^/]+/[^/]+/rootimg(/.*)?'}, '<<none>>',
    '... and restorecon leaves a rootimg alone');
is($fc{'/install/netboot/[^/]+/[^/]+/[^/]+/rootimg-statelite(/.*)?'}, '<<none>>',
    '... and a statelite rootimg too');
ok(!(grep { m{^/tftpboot} } keys %fc), '/tftpboot keeps the stock tftpdir_t');

# The type of an fc entry, dropping the file-type flag that executables carry.
sub fc_type {
    my ($path) = @_;
    my $spec = $fc{$path} // return undef;
    return $spec =~ /gen_context\(system_u:object_r:(\w+),s0\)/ ? $1 : $spec;
}

# restorecon labels the file that execve resolves to. /usr/sbin/xcatd is a
# symlink, and a symlink is never an entrypoint.
is(fc_type('/opt/xcat/sbin/xcatd'), 'xcatd_exec_t', 'xcatd is the entrypoint of the daemon');
ok(!exists $fc{'/usr/sbin/xcatd'}, '... and the symlink to it carries no context');
foreach my $client (qw(xcatclient xcatclientnnr)) {
    is(fc_type("/opt/xcat/bin/$client"), 'xcat_client_exec_t',
        "$client is the entrypoint of the client commands");
}

# The module source is the artifact: checkmodule compiles this text as written.
# Each rule here is justified by a measured denial; see
# docs/source/advanced/selinux/index.rst and the policy campaign REASONING.md.
my @te = grep { !/^\s*(?:#|$)/ } lines_of("$root/xCAT-selinux/xcat.te");
my $te = join("\n", @te);

like($te, qr/^policy_module\(xcat,/m, 'xcat.te declares the xcat policy module');

# Collects the permission set of each allow rule, keyed "source target:class".
my %allow;
foreach my $rule (split /;/, $te) {
    next unless $rule =~ /\ballow\s+(\S+)\s+(\S+?):(\S+)\s+(.+)/s;
    my ($source, $target, $class, $perms) = ($1, $2, $3, $4);
    $perms =~ s/[{}]/ /g;
    $allow{"$source $target:$class"}{$_} = 1 foreach split ' ', $perms;
}

# Taken before the lookups below, which autovivify the keys they miss.
my @rules = sort keys %allow;

# httpd mmaps the per-node xnba boot config it serves out of /tftpboot.
# read_file_perms does not hold map, so httpd is denied on the map.
ok($allow{'httpd_t tftpdir_t:file'}{mmap_read_file_perms}
        || $allow{'httpd_t tftpdir_t:file'}{map},
    'httpd may map a file it serves from /tftpboot');
ok($allow{'httpd_t tftpdir_t:dir'} && $allow{'httpd_t tftpdir_t:lnk_file'},
    '... and still reads the directory and the symlinks');

# xcatws.cgi connects to xcatd, whose port the stock policy labels ntop_port_t.
ok($allow{'httpd_sys_script_t ntop_port_t:tcp_socket'}{name_connect},
    'the REST API connects to the xcatd port');

# rsync copies /etc/shadow to the nodes and into a rootimg. The stock policy
# holds that read behind rsync_export_all_ro, and rsync_full_access does not
# grant it, because shadow_t is not in non_auth_file_type.
foreach my $perm (qw(getattr open read)) {
    ok($allow{'rsync_t shadow_t:file'}{$perm},
        "rsync may $perm /etc/shadow when it runs confined");
}

# rsync preserves the mode of /etc/shadow, so it writes a target it created at
# mode 0000. As root that needs CAP_DAC_OVERRIDE, which no boolean grants.
ok($allow{'rsync_t self:capability'}{dac_override},
    'rsync may write a target it created at mode 0000');

# useradd and groupadd run from the %pre of a package genimage installs into a
# rootimg, and look for their lock file through the rootimg /var/run symlink.
# It carries public_content_t because the rootimg is under /install, and no
# base rule reaches that type for lnk_file.
foreach my $domain (qw(useradd_t groupadd_t)) {
    ok($allow{"$domain public_content_t:lnk_file"}{read},
        "$domain reads the rootimg /var/run symlink");
}

# Granting execute on an unlabelled file buys a boot by standing in for a
# labelling step that has not run. See the EL10 note in the SELinux document.
ok(scalar(@rules) >= 4, 'xcat.te carries the allow rules this test reads');
is_deeply([ grep { /^kernel_t / } @rules ], [],
    'no rule grants kernel_t anything');


########################################
#
# The xcat_t domain
#

like($te, qr/^type xcat_t;$/m, 'xcat.te declares one domain for xcatd and the clients');
like($te, qr/^permissive xcat_t;$/m,
    '... which is permissive while the CI collects the accesses it needs');
unlike($te, qr/^permissive (?!xcat_t\b)/m, '... and no other domain is made permissive');

like($te, qr/^init_daemon_domain\(xcat_t, xcatd_exec_t\)$/m,
    'systemd starts xcatd in xcat_t');
like($te, qr/^application_domain\(xcat_t, xcat_client_exec_t\)$/m,
    'a client command entered through xcatclient runs in xcat_t');

# xcatd and xcatclient are Perl scripts. The kernel labels the new process from
# the script, then the domain runs the interpreter named in the shebang.
like($te, qr/^corecmd_exec_bin\(xcat_t\)$/m, 'xcat_t runs the interpreter of its own script');

# Collects the source domains that xcat.te gives an automatic transition.
my @domtrans = $te =~ /^\s*domtrans_pattern\((\w+), xcat_client_exec_t, xcat_t\)$/mg;
is_deeply(\@domtrans, ['unconfined_t'],
    'only the unconfined domain transitions into xcat_t');

# A confined user domain that entered a permissive xcat_t would leave its own
# confinement, so the module gives it no transition.
foreach my $domain (qw(user_t staff_t sysadm_t guest_t xguest_t)) {
    unlike($te, qr/\b\Q$domain\E\b/, "$domain gets no rule in xcat.te");
}

# A management node or a service node with the targeted policy installs the module.
foreach my $pkg (qw(xCAT-server xCATsn)) {
    my @lines = lines_of("$root/$pkg/$pkg.spec");
    my ($index) = grep {
        $lines[$_] =~ /^Requires:\s*\(xCAT-selinux = 4:%\{version\}-%\{release\} if selinux-policy-targeted\)\s*$/
    } 0 .. $#lines;
    ok(defined $index, "$pkg requires xCAT-selinux when selinux-policy-targeted is installed");
    my $if = defined $index ? enclosing_if(\@lines, $index) : undef;
    like($if // '', qr/\brhel\b/, "... only in a Red Hat family build");
    unlike($if // '', qr/suse/, "... and not in a SUSE build, which has no xCAT-selinux");
}

done_testing();
