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
set_row('nodetype', {node => 'node'}, {os => 'rhels10', arch => 'x86_64', provmethod => 'install'});
write_binary("$database/image.pkglist", '');
render_template($database, repo_path('xCAT-server/share/xcat/install/scripts/pre.rhels10'),
    "$database/pre.sh", 'node', "$database/image.pkglist", '/install/rhels10/x86_64',
    'rh', undef, {xcatmaster => '192.0.2.1'}, osarch => 'x86_64');

my $root = sandbox_root();
make_path("$root/libexec");
write_binary("$root/partitions", "major minor  #blocks  name\n\n   8 0 524288000 sda\n   8 16 524288000 sdb\n");
write_binary("$root/bin/udevadm", <<'SH');
#!/bin/sh
case "$*" in
    'info --attribute-walk --name=sda') driver=megaraid_sas ;;
    'info --attribute-walk --name=sdb') driver=ahci ;;
    'info --query=property --name='*) printf 'DEVTYPE=disk\n'; exit 0 ;;
    *) exit 97 ;;
esac
printf '    ATTRS{size}=="1024000000"\n    DRIVERS=="%s"\n' "$driver"
SH
write_binary("$root/bin/find", "#!/bin/sh\nprintf '/usr/bin/awk\\n'\n");
write_binary("$root/libexec/platform-python", "#!/bin/sh\nexit 0\n");
chmod 0755, "$root/bin/udevadm", "$root/bin/find", "$root/libexec/platform-python" or die $!;
for my $name (qw(logger vgs vgchange vgremove chown)) {
    write_binary("$root/bin/$name", "#!/bin/sh\nexit 0\n");
    chmod 0755, "$root/bin/$name" or die $!;
}
write_binary("$root/bin/mknod", "#!/bin/sh\n: >\"\$1\"\n");
chmod 0755, "$root/bin/mknod" or die $!;
for my $pass (1 .. 2) {
    write_binary("$root/tmp/xcat.install_disk", "/dev/not-selected\n");
    my ($rc, $output) = sandbox_run($root, {
        read_only => {"$root/partitions" => '/proc/partitions',
            "$root/libexec" => '/usr/libexec', "$database/pre.sh" => '/pre.sh'},
        env => {MASTER_IP => '192.0.2.1', log_label => 'install'},
    }, '/bin/bash', '-c', '. /pre.sh');
    is($rc, 0, "pass $pass completes") or diag($output);
    unlike($output, qr/msgutil_r/, "pass $pass has the installer logging helper");
    is(-f "$root/tmp/xcat.install_disk" ? scalar read_binary("$root/tmp/xcat.install_disk") : '',
        "/dev/sdb\n", "pass $pass selects the direct disk before RAID");
    ok(!-e "$root/tmp/xcat.getinstalldisk", "pass $pass removes scan state");
    my @rules = grep { /^ignoredisk\b/ } split /\n/,
        (-f "$root/tmp/partitionfile" ? scalar read_binary("$root/tmp/partitionfile") : '');
    is($rules[-1], 'ignoredisk --only-use=/dev/sdb',
        "pass $pass uses the selected disk in the rendered installer partition plan");
}
done_testing();
