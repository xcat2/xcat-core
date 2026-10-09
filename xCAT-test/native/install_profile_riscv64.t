#!/usr/bin/env perl
use strict;
use warnings;

use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Slurper qw(read_text write_text);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT", "$FindBin::Bin/../../xCAT-server/lib/perl";
use Test::More;
use Text::ParseWords qw(shellwords);

use XCAT::Test::File qw(repo_path);
use XCAT::Test::Sandbox qw(sandbox_root sandbox_run);
use XCAT::Test::Template qw(template_database set_row render_template);

plan skip_all => 'profile execution requires Linux' unless $^O eq 'linux';
my $database = template_database();
require xCAT::SvrUtils;
my $password = '$6$fixture$encrypted';
set_row('passwd', {key => 'system', username => 'root'}, {password => $password});
set_row('site', {key => 'secureroot'}, {value => 0});

my $install = File::Spec->catdir( 'xCAT-server', 'share', 'xcat', 'install' );
my @rendered_profiles;

sub installer_settings {
    my ($text) = @_;
    $text =~ s/^%(?:packages|pre|post|addon)\b.*?^%end[^\n]*\n?//msg;
    return [map { [shellwords($_)] } grep { /\S/ && !/^\s*#/ } split /\n/, $text];
}

sub package_set {
    my ($text) = @_;
    my ($packages) = $text =~ /^%packages[^\n]*\n(.*?)^%end/ms;
    return {map { $_ => 1 } grep { length && !/^#/ } split /\n/, $packages // ''};
}

for my $family ( [ 'rocky', 'rocky10' ], [ 'rh', 'rhels10' ] ) {
    my ( $dir, $osbase ) = @$family;
    for my $profile (qw(compute service)) {
        subtest "$osbase $profile" => sub {
            my $base = repo_path("$install/$dir");
            my $tmpl = xCAT::SvrUtils->get_tmpl_file_name($base, $profile, "$osbase.2", 'riscv64');
            is($tmpl, "$base/$profile.$osbase.riscv64.tmpl", 'selects the architecture-specific template');
            my $pkglist = xCAT::SvrUtils->get_pkglist_file_name($base, $profile, "$osbase.2", 'riscv64');
            is($pkglist, "$base/$profile.$osbase.riscv64.pkglist", 'selects the architecture-specific package list');
            set_row('nodetype', {node => 'node'}, {os => "$osbase.2", arch => 'riscv64', provmethod => 'install'});
            my $output = "$database/$osbase-$profile.ks";
            render_template($database, $tmpl, $output, 'node',
                $pkglist, '/install/media', $dir, undef,
                {xcatmaster => '192.0.2.1'});
            my $rendered = read_text($output);
            my $shared_output = "$database/$osbase-$profile-shared.ks";
            render_template($database, "$base/$profile.$osbase.tmpl", $shared_output, 'node',
                "$base/$profile.$osbase.pkglist", '/install/media', $dir, undef,
                {xcatmaster => '192.0.2.1'});
            my $shared = read_text($shared_output);
            is_deeply(installer_settings($rendered), installer_settings($shared),
                'preserves the shared installer settings');
            my $expected_packages = package_set($shared);
            $expected_packages->{$_} = 1 for qw(grub2-efi-riscv64 efibootmgr);
            is_deeply(package_set($rendered), $expected_packages,
                'adds the RISC-V boot packages to the complete shared package set');
            my @pre = $rendered =~ /^%pre[^\n]*\n(.*?)^%end/msg;
            my @shared_pre = $shared =~ /^%pre[^\n]*\n(.*?)^%end/msg;
            is_deeply(\@pre, \@shared_pre, 'delivers the shared pre-install artifact unchanged');
            unlike($rendered, qr/#(?:INCLUDE|TABLE|CRYPT|ENV|XCATVAR)[^\n]*#/, 'resolves template inputs');
            like($rendered, qr/^rootpw --iscrypted \Q$password\E$/m, 'renders the configured password');
            like($rendered, qr/^timezone UTC --utc$/m, 'renders the site timezone');
            my ($options, $packages) = $rendered =~ /^%packages([^\n]*)\n(.*?)^%end/ms;
            like($options // '', qr/(?:^|\s)--ignoremissing(?:\s|$)/, 'tolerates unavailable installer packages');
            my %packages = map { $_ => 1 } grep { length && !/^#/ } split /\n/, $packages // '';
            ok($packages{'grub2-efi-riscv64'} && $packages{efibootmgr}, 'includes RISC-V boot packages');
            ok(!$packages{'grub2-efi-x64'} && !$packages{'shim-x64'} && !$packages{'grub2-efi-aa64'}, 'excludes foreign boot packages');
            like($rendered, qr/^%addon com_redhat_kdump --disable\n%end$/m, 'disables the unsupported default crash reservation');
            my @posts;
            my @all_posts;
            while ($rendered =~ /^%post([^\n]*)\n(.*?)^%end/msg) {
                my ($flags, $body) = ($1, $2);
                push @all_posts, [$flags, $body];
                push @posts, [$flags, $body] if $flags =~ /(?:^|\s)--erroronfail(?:\s|$)/;
            }
            push @rendered_profiles, ["$osbase $profile", \@all_posts];
            is(scalar @posts, 1, 'has one fatal boot-loader check');
            return unless @posts == 1;
            my ($interpreter) = $posts[0][0] =~ /--interpreter=(\S+)/;
            is($interpreter, '/bin/bash', 'runs the check with the requested interpreter');
            for my $loader ('BOOT/BOOTRISCV64.EFI', 'rocky/grubriscv64.efi', 'rocky/grubx64.efi', '') {
                my $root = sandbox_root();
                make_path("$root/boot/efi/EFI/BOOT", "$root/boot/efi/EFI/rocky", "$root/log/xcat");
                write_text("$root/boot/efi/EFI/$loader", "loader\n") if $loader;
                write_text("$root/check.sh", $posts[0][1]);
                my ($rc, $log) = sandbox_run($root, $interpreter, '/fixture/check.sh');
                my $valid = $loader && $loader ne 'rocky/grubx64.efi';
                is($rc, $valid ? 0 : 1, $valid ? "accepts $loader" : "rejects an ESP without a RISC-V loader ($loader)") or diag($log);
                if (!$valid) {
                    like(read_text("$root/log/xcat/xcat.log"), qr/no grub2 UEFI boot loader/, 'explains the missing loader');
                }
            }
        };
    }
}

my $post = File::Spec->catfile( $install, 'scripts', 'post.rhels10.riscv64' );
my $post_path = repo_path($post);
ok( -r $post_path, 'post.rhels10.riscv64 exists' );

is(system('sh', '-n', $post_path), 0, 'post.rhels10.riscv64 parses as POSIX shell');

my $tools = tempdir(CLEANUP => 1);
my $efi_log = File::Spec->catfile($tools, 'efibootmgr.log');

sub fake_command {
    my ($name, $body) = @_;
    my $path = File::Spec->catfile($tools, $name);
    write_text($path, "#!/bin/sh\n$body");
    chmod 0755, $path or die "Unable to make $path executable: $!";
    return $path;
}

my $uname = fake_command('uname', <<'SH');
printf '%s\n' "${XCAT_TEST_ARCH:-riscv64}"
SH
my $findmnt = fake_command('findmnt', <<'SH');
printf '/dev/vda1\n'
SH
my $lsblk = fake_command('lsblk', <<'SH');
case "$*" in
    *PKNAME*) printf "vda\n" ;;
    *PARTN*) printf "1\n" ;;
esac
SH
my $efibootmgr = fake_command('efibootmgr', <<'SH');
printf '%s\n' "$*" >> "$XCAT_EFI_LOG"
case "$*" in
    '') exit 0 ;;
    '-v')
        printf 'Boot0001* Rocky HD(1,GPT,...)/File(\\EFI\\rocky\\shimx64.efi)\n'
        printf 'Boot0002* OldRiscv HD(1,GPT,...)/File(\\EFI\\rocky\\grubriscv64.efi)\n'
        printf 'Boot0003* Network PXE\n'
        exit 0
        ;;
    *'-c'*) exit "${XCAT_EFI_CREATE_RC:-0}" ;;
esac
exit 0
SH

sub installed_root {
    my ($with_loader, $root) = @_;
    $root //= tempdir(CLEANUP => 1);
    make_path(File::Spec->catdir($root, 'boot', 'efi', 'EFI', 'rocky'));
    make_path(File::Spec->catdir($root, 'etc'));
    write_text(File::Spec->catfile($root, 'etc', 'os-release'), "NAME=\"Rocky Linux\"\n");
    if ($with_loader) {
        write_text(
            File::Spec->catfile($root, 'boot', 'efi', 'EFI', 'rocky', 'grubriscv64.efi'),
            "riscv loader\n",
        );
    }
    return $root;
}

for my $rendered (@rendered_profiles) {
    my ($label, $posts) = @$rendered;
    subtest "$label post-install sequence" => sub {
        my $root = installed_root(1, sandbox_root());
        make_path("$root/etc/systemd/system/multi-user.target.wants", "$root/etc/yum.repos.d");
        write_text("$root/etc/yum.repos.d/rocky.repo", "[baseos]\nname=BaseOS\nenabled=1\n");
        write_text("$root/tmp/pre-install.log", "pre-install fixture diagnostic\n");
        copy(repo_path('xCAT/postscripts/xcatlib.sh'), "$root/xcatlib.sh") or die $!;
        write_text("$root/mypostscript.node", "#!/bin/bash\nMASTER=192.0.2.1\ntouch /fixture/postscript-ran\n");
        for my $name (qw(uname findmnt lsblk efibootmgr)) {
            copy("$tools/$name", "$root/bin/$name") or die $!;
            chmod 0755, "$root/bin/$name" or die $!;
        }
        for my $name (qw(curl logger sleep updateflag.awk nmcli openssl)) {
            copy(repo_path('xCAT-test/fixtures/install-profile/command'), "$root/bin/$name") or die $!;
            chmod 0755, "$root/bin/$name" or die $!;
        }
        my $index = 0;
        for my $post (@$posts) {
            my ($interpreter) = $post->[0] =~ /--interpreter=(\S+)/;
            $interpreter //= '/bin/sh';
            write_text("$root/post.sh", $post->[1]);
            my ($rc, $log) = sandbox_run($root, {
                env => {XCAT_EFI_LOG => '/fixture/efi.log'},
            }, 'timeout', '30', $interpreter, '/fixture/post.sh');
            is($rc, 0, 'post block ' . ++$index . ' completes')
                or diag($log, read_text("$root/log/xcat/xcat.log"));
        }
        my $fallback = "$root/boot/efi/EFI/BOOT/BOOTRISCV64.EFI";
        is(-f $fallback ? read_text($fallback) : '', "riscv loader\n",
            'the rendered profile installs the fallback EFI loader');
        my $calls = -f "$root/efi.log" ? read_text("$root/efi.log") : '';
        like($calls, qr/^-q -c -d \/dev\/vda -p 1 -L Rocky Linux -l \\EFI\\rocky\\grubriscv64\.efi$/m,
            'the rendered profile registers the vendor EFI loader');
        ok(!-e "$root/unexpected-command", 'external fixtures accept the requested operations');
        ok(-e "$root/postscript-ran", 'runs the downloaded postscript from the rendered profile');
        is(read_text("$root/etc/yum.repos.d/rocky.repo"), "[baseos]\nname=BaseOS\nenabled=0\n",
            'disables the installed vendor repository');
        like(read_text("$root/log/xcat/xcat.log"), qr/^pre-install fixture diagnostic$/m,
            'preserves the pre-install diagnostics in the deployment log');
    };
}

sub run_post {
    my ($root, %extra) = @_;
    local %ENV = (
        %ENV,
        XCAT_INSTALL_ROOT => $root,
        XCAT_UNAME         => $uname,
        XCAT_EFIBOOTMGR    => $efibootmgr,
        XCAT_FINDMNT       => $findmnt,
        XCAT_LSBLK         => $lsblk,
        XCAT_EFI_LOG       => $efi_log,
        XCAT_TEST_ARCH     => 'riscv64',
        %extra,
    );
    open(my $fh, '-|', 'sh', $post_path) or die "Unable to run $post_path: $!";
    my $output = do { local $/; <$fh> };
    close($fh);
    return ($? >> 8, $output);
}

my $root = installed_root(1);
my ($status, $output) = run_post($root);
is($status, 0, 'the RISC-V fix-up completes successfully');
is(
    read_text(File::Spec->catfile($root, 'boot', 'efi', 'EFI', 'BOOT', 'BOOTRISCV64.EFI')),
    "riscv loader\n",
    'the distro loader is copied to the removable-media fallback path',
);
like($output, qr/UEFI boot entry "Rocky Linux"/, 'the created UEFI entry is reported');
my $efi_calls = read_text($efi_log);
like($efi_calls, qr/^-q -b 0001 -B$/m, 'the invalid x86 boot entry is removed');
like($efi_calls, qr/^-q -b 0002 -B$/m, 'the prior RISC-V boot entry is removed');
unlike($efi_calls, qr/0003/, 'unrelated firmware entries are retained');
like(
    $efi_calls,
    qr/^-q -c -d \/dev\/vda -p 1 -L Rocky Linux -l \\EFI\\rocky\\grubriscv64\.efi$/m,
    'the new entry points at the distro RISC-V loader on the ESP disk',
);

unlink($efi_log);
my $x86_root = installed_root(1);
($status, $output) = run_post($x86_root, XCAT_TEST_ARCH => 'x86_64');
is($status, 0, 'the post-install script is a no-op on x86_64');
is($output, '', 'the x86_64 no-op reports nothing');
ok(!-e $efi_log, 'the x86_64 no-op never invokes efibootmgr');

my $bare_root = installed_root(0);
($status, $output) = run_post($bare_root);
is($status, 0, 'a missing distro loader remains nonfatal');
like($output, qr/no \\EFI\\\*\\grubriscv64\.efi/, 'a missing distro loader is diagnosed');

unlink($efi_log);
($status, $output) = run_post($root, XCAT_EFI_CREATE_RC => 1);
is($status, 0, 'an efibootmgr create failure remains nonfatal');
like($output, qr/firmware will use \\EFI\\BOOT\\BOOTRISCV64\.EFI/, 'the fallback path is reported after an efibootmgr failure');

done_testing();
