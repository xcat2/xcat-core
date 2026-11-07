#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT", "$FindBin::Bin/../../xCAT-server/lib/perl";
use File::Path qw(make_path);
use File::Slurper qw(read_binary write_binary);
use Test::More;
use XCAT::Test::File qw(repo_path);
use XCAT::Test::Sandbox qw(sandbox_root sandbox_run);
use XCAT::Test::Template qw(template_database set_row render_template);

plan skip_all => 'installer execution requires Linux namespaces' unless $^O eq 'linux';
my $database = template_database();
set_row('site', {key => 'nodestatus'}, {value => 0});
write_binary("$database/image.pkglist", '');

# Credentials in the forms that kickstart's shell-style parser accepts.
my $custom = join("\n",
    'part /data --fstype=xfs --size=1024 --encrypted --passphrase=s3cret-one --ondisk=sdb',
    'logvol /home --vgname=vg --name=home --size=1 --encrypted --passphrase "s3cret two"',
    "raid /srv --level=1 --device=md0 --encrypted --passphrase='s3cret three' raid.01 raid.02",
    'part /esc --size=1 --encrypted --passphrase=prefix\\ s3cret\\ four --ondisk=sdb',
    'part /quote --size=1 --encrypted --pass"phrase"="s3cret \\"five\\"" --ondisk=sdb',
    'bootloader --iscrypted --password=s3cret-six',
    'rootpw --plaintext s3cret-seven');
write_binary("$database/partitionfile", "$custom\n");
write_binary("$database/partscript", "#!/bin/sh\ncat >/tmp/partitionfile <<'EOF'\n$custom\nEOF\n");

# Commands that the pre-installation scripts call in the installer.
sub installer_root {
    my $root = sandbox_root();
    make_path("$root/libexec");
    write_binary("$root/partitions", "major minor  #blocks  name\n\n   8 16 524288000 sdb\n");
    write_binary("$root/bin/udevadm", <<'SH');
#!/bin/sh
case "$*" in
    'info --attribute-walk --name=sdb') printf '    ATTRS{size}=="1024000000"\n    DRIVERS=="ahci"\n' ;;
    'info --query=property --name='*) printf 'DEVTYPE=disk\n' ;;
    *) exit 97 ;;
esac
SH
    write_binary("$root/bin/find", "#!/bin/sh\nprintf '/usr/bin/awk\\n'\n");
    write_binary("$root/libexec/platform-python", "#!/bin/sh\nexit 0\n");
    write_binary("$root/bin/mknod", "#!/bin/sh\n: >\"\$1\"\n");
    for my $name (qw(logger vgs vgchange vgremove chown)) {
        write_binary("$root/bin/$name", "#!/bin/sh\nexit 0\n");
    }
    chmod oct('755'), glob("$root/bin/*"), "$root/libexec/platform-python" or die $!;
    return $root;
}

for my $case (['rh/compute.rhels9.tmpl', 'alma9.6'], ['rh/compute.rhels10.tmpl', 'rhels10']) {
    my ($template, $os) = @$case;
    for my $input (['generated', undef], ['custom file', "$database/partitionfile"],
                   ['custom script', "s:$database/partscript"]) {
        my ($kind, $partitionfile) = @$input;
        for my $mode (0, 1, 2) {
            subtest "$template, $kind, xcatdebugmode $mode" => sub {
                set_row('site', {key => 'xcatdebugmode'}, {value => $mode});
                set_row('nodetype', {node => 'node'}, {os => $os, arch => 'x86_64', provmethod => 'install'});
                render_template($database, repo_path("xCAT-server/share/xcat/install/$template"), "$database/ks",
                    'node', "$database/image.pkglist", "/install/$os/x86_64", 'rh', $partitionfile,
                    {xcatmaster => '192.0.2.1'}, osarch => 'x86_64');
                my ($pre) = read_binary("$database/ks") =~ /^%pre\b[^\n]*\n(.*?)^%end$/ms;
                write_binary("$database/pre.sh", $pre // '');
                my $root = installer_root();
                my ($rc, $output) = sandbox_run($root, {
                    read_only => {"$root/partitions" => '/proc/partitions', "$root/libexec" => '/usr/libexec',
                        "$database/pre.sh" => '/pre.sh'},
                    env => {MASTER_IP => '192.0.2.1', log_label => 'install'},
                }, '/bin/bash', '-c', '. /pre.sh');
                is($rc, 0, 'the %pre block completes') or diag($output);
                my $log = -f "$root/tmp/pre-install.log" ? read_binary("$root/tmp/pre-install.log") : '';
                my ($scheme) = $log =~ /^=+ The Partition Scheme =+\n(.*?)^=+$/ms;
                if ($mode) {
                    like($log, qr/^\++ /m, 'traces the %pre block into the pre-install log');
                }
                if (!defined $partitionfile) {
                    like($scheme // '', qr/^volgroup xcatvg /m, 'logs the partition scheme that xCAT generated');
                    return;
                }
                like($scheme // '', qr/^The custom partition file is not logged\.$/m,
                    'logs a notice in place of the custom partition file');
                unlike($scheme // '', qr/^(?:part|logvol|raid|bootloader|rootpw) /m,
                    'logs no line of the custom partition file');
                unlike($log . $output, qr/s3cret/, 'leaves no credential in the log or the trace');
                # The decoder prints three bytes at a time, so a traced decode spells them out in hex.
                my $traced = join('', map { pack('H*', join('', /\\x([0-9A-Fa-f]{2})/g)) }
                    $log =~ /^\++ printf '([^']*)'$/mg);
                unlike($traced, qr/s3cret/, 'traces no decoded byte of the custom input');
                like(read_binary("$root/tmp/partitionfile"), qr/\A\Q$custom\E\n?\z/,
                    'hands anaconda the custom partition definitions');
            };
        }
    }
}
set_row('site', {key => 'xcatdebugmode'}, {value => 0});

done_testing();
