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
