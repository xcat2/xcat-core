#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib grep { defined($_) } $ENV{XCAT_FREEBSD_CONFIG_MODULE_DIR};
use Test::More;
use xCAT::FreeBSDConfig;

sub rejected {
    my ($code, $pattern, $label) = @_;
    my $ok = eval { $code->(); 1 };
    my $error = $@;
    ok(!$ok, "$label fails");
    like($error, $pattern, "$label reports its cause");
    return;
}

for my $empty_text (undef, '', '   ') {
    is_deeply(xCAT::FreeBSDConfig::parse_boot_options($empty_text),
        { volatile => {}, persistent => {} }, 'absent options leave both phases empty');
}
is(xCAT::FreeBSDConfig::render_boot_options({}), '', 'an empty phase emits no loader settings');

my $options = xCAT::FreeBSDConfig::parse_boot_options(
    '  hint.ahci.0.disabled=1 if_igb_load=yes boot_verbose=no hw.pci.mcfg=0 ' .
    'R::hw.pci.mcfg=1 R::if_igb_load=No R::hint.site.custom=-1 R::site.empty=  ');
is_deeply($options, {
    volatile => { 'hint.ahci.0.disabled' => '1', if_igb_load => 'YES', boot_verbose => 'NO', 'hw.pci.mcfg' => '0' },
    persistent => { 'hw.pci.mcfg' => '1', if_igb_load => 'NO', 'hint.site.custom' => '-1', 'site.empty' => '' },
}, 'native tunables and module switches retain separate installation and installed values');
is(xCAT::FreeBSDConfig::render_boot_options($options->{volatile}),
    "boot_verbose=\"NO\"\nhint.ahci.0.disabled=\"1\"\nhw.pci.mcfg=\"0\"\nif_igb_load=\"YES\"\n",
    'installer settings render in deterministic native loader syntax');
is(xCAT::FreeBSDConfig::render_boot_options($options->{persistent}),
    "hint.site.custom=\"-1\"\nhw.pci.mcfg=\"1\"\nif_igb_load=\"NO\"\nsite.empty=\"\"\n",
    'installed settings contain only persistent intent and preserve explicit empty values');

my %native = ('hint.device.0.setting' => 'a_b.c,d:+/@%=x-1', if_igb_flags => '-v', boot_single => 'yes');
is(xCAT::FreeBSDConfig::render_boot_options(\%native),
    "boot_single=\"YES\"\nhint.device.0.setting=\"a_b.c,d:+/\@%=x-1\"\nif_igb_flags=\"-v\"\n",
    'bounded native values are data, including module flags and an embedded equals sign');
is($native{boot_single}, 'yes', 'rendering does not rewrite caller-owned values');
is_deeply(xCAT::FreeBSDConfig::parse_boot_options('hint.Site.Custom=0')->{volatile},
    { 'hint.Site.Custom' => '0' }, 'ordinary native names retain case');

for my $duplicate_text ('hint.a=1 hint.a=2', 'hint.a=1 hint.a=1', 'R::hint.a=1 R::hint.a=2') {
    rejected(sub { xCAT::FreeBSDConfig::parse_boot_options($duplicate_text); },
        qr/Duplicate/, 'duplicate option within one phase');
}
for my $malformed_text ('R::', 'R::R::hint.a=1', 'quiet', '-v', 'hint.a', '=1', 'r::hint.a=1',
    'hint.a="two words"', "hint.a=1\thint.b=2", "hint.a=1\n", "hint.a=1\r", "hint.a=\x00", "hint.a=\x{100}") {
    rejected(sub { xCAT::FreeBSDConfig::parse_boot_options($malformed_text); },
        qr/Expected[ ]a[ ]native|Invalid[ ]boot[ ]option/x, 'malformed option stream');
}
for my $nonscalar_input ([], {}, \1) {
    rejected(sub { xCAT::FreeBSDConfig::parse_boot_options($nonscalar_input); },
        qr/Invalid boot options/, 'non-scalar option stream');
}

my @reserved = qw(
    exec loader_conf_files loader_conf_dirs local_loader_conf_files product_vars
    nextboot_conf nextboot_enable kernel kernels kernels_autodetect kernel_options
    kernel_path kernelname kernel_load kernel_flags xen_kernel bootfile module_path module_blacklist
    lua_path loader_path efi-version currdev loaddev root rootdev rootpath root_path
    rootflags rootfstype root_disk_unit num_ide_disks init initrd rdinit console boot_serial boot_multicons boot_multiple
    boot_mute boot_mutemsgs boot_askname boot_cdrom boot_dfltroot autoboot_delay beastie_disable
    hostname hostid hostuuid ip bootif netmask gateway nameserver nameservers
    kern.hostname kern.hostid kern.hostuuid kern.domainname kern.bootfile kern.maxphys
    xcat_config_url xcat_config_sha256 xcat.node mfs_load mfs_type mfs_name
    mfsbsd.autodhcp mfsroot_load mfsroot mdroot.retries boot.netif.hwaddr boot.netif.ip
    dhcp.host-name init_path hostuuid_load bootenv zfs_be_active vfs.root.mountfrom
    vfs.root.mountfrom.options vfs.zfs.boot.primary_pool vfs.zfs.root comconsole_speed
    comconsole_port hw.uart.console hint.uart.0.flags hint.sio.0.flags
    if_igb_before if_igb_after if_igb_error if_igb_name if_igb_type MFSROOT_load KERNEL_load
    XCAT_CONFIG_URL VFS.ROOT.MOUNTFROM
);
for my $reserved_key (@reserved) {
    for my $phase ('', 'R::') {
        rejected(sub { xCAT::FreeBSDConfig::parse_boot_options("$phase$reserved_key=YES"); },
            qr/Reserved boot option/, "$phase$reserved_key cannot override owned boot behavior");
    }
    rejected(sub { xCAT::FreeBSDConfig::render_boot_options({ $reserved_key => 'YES' }); },
        qr/Reserved boot option/, "$reserved_key cannot bypass validation through rendering");
}

for my $switch_key (qw(if_igb_load boot_ddb boot_gdb boot_pause boot_single boot_verbose boot_safe)) {
    is(xCAT::FreeBSDConfig::render_boot_options({ $switch_key => 'yEs' }), "$switch_key=\"YES\"\n",
        "$switch_key normalizes a native switch");
    for my $invalid_switch ('', '1', 'true', 'maybe') {
        rejected(sub { xCAT::FreeBSDConfig::parse_boot_options("$switch_key=$invalid_switch"); },
            qr/Expected YES or NO/, "$switch_key rejects a non-native switch value");
        rejected(sub { xCAT::FreeBSDConfig::render_boot_options({ $switch_key => $invalid_switch }); },
            qr/Expected YES or NO/, "$switch_key renderer rejects a non-native switch value");
    }
}

for my $invalid_key ('', '-bad', '1bad', 'a/b', 'a:b', 'a=b', 'a b', "a\nb", "a\x{100}", 'a' x 129) {
    rejected(sub { xCAT::FreeBSDConfig::render_boot_options({ $invalid_key => '1' }); },
        qr/Invalid boot option name/, 'invalid native name');
}
for my $invalid_value (undef, [], {}, \1, 'a b', 'a;b', 'a#b', 'a"b', "a'b", 'a\\b',
    '$(id)', '`id`', 'a|b', 'a&b', 'a<b', 'a>b', "a\nb", "a\rb", "a\tb", "a\x00b", "a\x{100}", 'a' x 129) {
    rejected(sub { xCAT::FreeBSDConfig::render_boot_options({ 'hint.test' => $invalid_value }); },
        qr/Invalid boot option value/, 'invalid native value');
}
for my $invalid_map (undef, '', [], \1) {
    rejected(sub { xCAT::FreeBSDConfig::render_boot_options($invalid_map); },
        qr/Invalid boot options map/, 'invalid phase map');
}

my $long_key = 'a' x 128;
my $long_value = 'b' x 128;
is(xCAT::FreeBSDConfig::render_boot_options({ $long_key => $long_value }),
    "$long_key=\"$long_value\"\n", 'maximum native name and value lengths are accepted');
is_deeply(xCAT::FreeBSDConfig::parse_boot_options("$long_key=$long_value")->{volatile},
    { $long_key => $long_value }, 'parser accepts maximum native name and value lengths');
for my $oversized_input (('a' x 129) . '=1', 'hint.test=' . ('b' x 129), ' ' x 16385) {
    rejected(sub { xCAT::FreeBSDConfig::parse_boot_options($oversized_input); },
        qr/Invalid boot option/, 'oversized input');
}
my %maximum = map { ("hint.test.$_", '1') } 1 .. 128;
my $maximum_text = join(' ', map { "$_=$maximum{$_}" } sort keys %maximum);
is_deeply(xCAT::FreeBSDConfig::parse_boot_options($maximum_text)->{volatile},
    \%maximum, 'one phase accepts 128 distinct options');
is_deeply(xCAT::FreeBSDConfig::parse_boot_options("$maximum_text " .
    join(' ', map { "R::$_=$maximum{$_}" } sort keys %maximum)),
    { volatile => \%maximum, persistent => \%maximum }, 'the option-count limit applies independently to each phase');
is(scalar(split(/\n/x, xCAT::FreeBSDConfig::render_boot_options(\%maximum))), 128,
    'renderer accepts 128 distinct options');
rejected(sub { xCAT::FreeBSDConfig::parse_boot_options("$maximum_text hint.extra=1"); },
    qr/Too many boot options/, '129 installation options');
rejected(sub { xCAT::FreeBSDConfig::parse_boot_options(join(' ',
    map { "R::hint.test.$_=1" } 1 .. 129)); }, qr/Too many boot options/, '129 persistent options');
rejected(sub { xCAT::FreeBSDConfig::render_boot_options({ %maximum, 'hint.extra' => '1' }); },
    qr/Too many boot options/, '129 rendered options');

my %exact_size = map { ('h' . ('a' x 120) . sprintf('%03d', $_), $long_value) } 1 .. 64;
my $exact_text = join(' ', map { "$_=$exact_size{$_}" } sort keys %exact_size);
is(length(xCAT::FreeBSDConfig::render_boot_options(\%exact_size)), 16384,
    'renderer accepts exactly 16 KiB');
is_deeply(xCAT::FreeBSDConfig::parse_boot_options($exact_text)->{volatile}, \%exact_size,
    'parser accepts options whose rendered phase is exactly 16 KiB');
my %too_large = map { ('h' . ('a' x 121) . sprintf('%03d', $_), $long_value) } 1 .. 64;
my $oversized_text = join(' ', map { "$_=$too_large{$_}" } sort keys %too_large);
cmp_ok(length($oversized_text), '<=', 16384, 'render-size negative control stays inside the input limit');
rejected(sub { xCAT::FreeBSDConfig::parse_boot_options($oversized_text); },
    qr/Rendered boot options are too large/, 'parser rejects an oversized rendered phase');
rejected(sub { xCAT::FreeBSDConfig::render_boot_options(\%too_large); },
    qr/Rendered boot options are too large/, 'renderer rejects an oversized phase');

done_testing();
