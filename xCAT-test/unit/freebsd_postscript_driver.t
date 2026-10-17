#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use Carp qw(croak);
use Cwd qw(abs_path);
use File::Basename qw(dirname);
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use Test::More;
use xCAT::FreeBSDPkg;
use xCAT::FreeBSDPostscript;

plan(skip_all => 'Driver execution requires a Linux or FreeBSD lab root')
  unless ($^O eq 'linux' || $^O eq 'freebsd') && $> == 0;
my $root = abs_path(tempdir(CLEANUP => 1, DIR => '/tmp'));
my $chroot = -x '/usr/sbin/chroot' ? '/usr/sbin/chroot' : '/usr/bin/chroot';
sub read_file {
    open(my $file, '<', $_[0]) or croak $!;
    local $/ = undef;
    my $bytes = <$file>;
    close($file) or croak $!;
    return defined($bytes) ? $bytes : '';
}
sub write_file {
    my ($path, $bytes, $mode) = @_;
    open(my $file, '>', $path) or croak $!;
    binmode($file) or croak $!;
    print {$file} $bytes or croak $!;
    close($file) or croak $!;
    chmod(defined($mode) ? $mode : oct('0600'), $path) == 1 or croak $!;
    return;
}
make_path("$root/bin", "$root/usr/local/libexec", "$root/tree");
copy('/bin/sh', "$root/bin/sh") or croak $!;
chmod(oct('0555'), "$root/bin/sh") == 1 or croak $!;
my $loader = xCAT::FreeBSDPkg::run_command(['/usr/bin/ldd', '/bin/sh'], cwd => $root,
    environment => { PATH => '/usr/bin:/bin', LC_ALL => 'C' }, timeout => 10);
BAIL_OUT('Cannot inspect shell dependencies') if $loader->{exitcode} || $loader->{signal};
for my $path ($loader->{stdout} =~ m{(/[^\s()]+)}gx) {
    next unless -f $path;
    make_path(dirname("$root$path"));
    copy($path, "$root$path") or croak $!;
    chmod((stat($path))[2] & oct('0777'), "$root$path") == 1 or croak $!;
}
if ($^O eq 'freebsd') {
    make_path("$root/libexec");
    copy('/libexec/ld-elf.so.1', "$root/libexec/ld-elf.so.1") or croak $!;
}
write_file("$root/usr/local/libexec/xcat-postscript", <<'WORKER', oct('0555'));
#!/bin/sh
verb=$1
shift
printf '%s' "$verb" >> /events
for argument do printf '<%s>' "$argument" >> /events; done
printf '\n' >> /events
if [ "$verb" = execute ]; then
    shift 2
    script=$1
    shift
    "/tree/$script" "$@"
    printf 'child-status<%s>\n' "$?" >> /events
fi
exit 0
WORKER
for my $name (qw(def img node bootdef bootimg bootnode extra)) {
    write_file("$root/tree/$name", <<'SCRIPT', oct('0555'));
#!/bin/sh
printf '%s<%s>' "$0" "$UPDATENODE" >> /effects
for argument do printf '<%s>' "$argument" >> /effects; done
printf '\n' >> /effects
SCRIPT
}
my $rendered = <<'RENDERED';
UPDATENODE=0
export UPDATENODE
ARG='expanded words'
printf 'before\n' >> /custom
# postscripts-start-here
# defaults-postscripts-start-here
def "two words" '$ARG' "$ARG" "" ';' "|"
# defaults-postscripts-end-here
# osimage-postscripts-start-here
img
# osimage-postscripts-end-here
# node-postscripts-start-here
node
# node-postscripts-end-here
extra
# postscripts-end-here
# postbootscripts-start-here
# defaults-postbootscripts-start-here
bootdef
# defaults-postbootscripts-end-here
# osimage-postbootscripts-start-here
bootimg
# osimage-postbootscripts-end-here
# node-postbootscripts-start-here
bootnode
# node-postbootscripts-end-here
# postbootscripts-end-here
printf 'after\n' >> /custom
RENDERED

sub exercise {
    my ($selection, $repeat, $expected, $enabled, $label) = @_;
    my $compiled = xCAT::FreeBSDPostscript::_driver($rendered, $selection, $repeat);
    is($compiled->{enabled}, $enabled, "$label execution policy");
    is_deeply([map { pack('H*', $_->{name}) } @{$compiled->{entries}}], $expected, "$label selected entries");
    write_file("$root/driver", $compiled->{driver});
    write_file("$root/$_", '') for qw(events effects custom);
    my $outcome = xCAT::FreeBSDPkg::run_command([$chroot, $root, '/bin/sh', '/driver', 'run'],
        cwd => $root, environment => { PATH => '/bin', LC_ALL => 'C' }, timeout => 10);
    is($outcome->{exitcode}, 0, "$label driver exits normally");
    is($outcome->{signal}, 0, "$label driver is not terminated");
    is($outcome->{stderr}, '', "$label has no shell errors");
    my @effects = read_file("$root/effects") =~ m{^/tree/([^<]+)}mgx;
    is_deeply(\@effects, $expected, "$label executes the selected scripts in order");
    my @events = split(/\n/x, read_file("$root/events"));
    my $ordinal = 0;
    while (@events > 1) {
        ++$ordinal;
        is(shift(@events), "begin<run><$ordinal>", "$label records entry $ordinal before execution");
        like(shift(@events), qr/\Aexecute<run><$ordinal></x, "$label dispatches entry $ordinal");
        is(shift(@events), 'child-status<0>', "$label child $ordinal succeeds");
    }
    is_deeply(\@events, ['driver-complete<run><' . @$expected . '>'], "$label completes only after the final entry");
    is(read_file("$root/custom"), $enabled ? "before\nafter\n" : '', "$label respects administrator template code");
    return read_file("$root/effects");
}

subtest 'phase selection and shell argument expansion' => sub {
    my $effects = exercise({ kind => 'firstboot' }, undef,
        [qw(def img node extra bootdef bootimg bootnode)], 1, 'first boot');
    is((split(/\n/x, $effects))[0], q{/tree/def<0><two words><$ARG><expanded words><><;><|>},
        'quotes, empty arguments and variable expansion reach the actual script');
    exercise({ kind => 'repeat' }, 'YeS', [qw(bootdef bootimg bootnode)], 1, 'enabled repeat');
    exercise({ kind => 'repeat' }, 'no', [], 0, 'disabled repeat');
    exercise({ kind => 'repeat' }, undef, [], 0, 'unset repeat');
    $effects = exercise({ kind => 'update', raw => '' }, undef,
        [qw(def img node extra bootdef bootimg bootnode)], 1, 'full update');
    like($effects, qr{\A/tree/def<1>}x, 'update scripts receive UPDATENODE=1');
    $effects = exercise({ kind => 'update', raw => 'extra "first argument",extra second' }, undef,
        [qw(extra extra)], 1, 'explicit update');
    is($effects, "/tree/extra<1><first argument>\n/tree/extra<1><second>\n", 'explicit entries preserve arguments and duplicates');
};

subtest 'existing section selectors' => sub {
    for my $case (
        ['postscripts', [qw(def img node extra)]],
        ['postbootscripts', [qw(bootdef bootimg bootnode)]],
        ['defaults-postscripts', [qw(def extra)]],
        ['osimage-postscripts', [qw(img extra)]],
        ['node-postscripts', [qw(node extra)]],
        ['defaults-postbootscripts', ['bootdef']],
        ['osimage-postbootscripts', ['bootimg']],
        ['node-postbootscripts', ['bootnode']]) {
        exercise({ kind => 'update', raw => "$case->[0]-start-here" }, undef, $case->[1], 1, $case->[0]);
    }
};

subtest 'reject unusable requests before producing a driver' => sub {
    for my $raw ('extra;', 'extra | node', 'extra > file', 'extra $(id)', 'extra `id`',
        'extra "unterminated', "extra\\", 'extra,,node', 'unknown-start-here',
        "extra\nnode", "extra\0", '../extra', '/extra', '$SCRIPT argument') {
        my $compiled = eval { xCAT::FreeBSDPostscript::_driver($rendered, { kind => 'update', raw => $raw }, undef); };
        ok(!$compiled && $@, 'unsupported shell selection returns no driver');
    }
    my $broken = $rendered;
    $broken =~ s/[\#][ ]postscripts-end-here//x;
    my $compiled = eval { xCAT::FreeBSDPostscript::_driver($broken, { kind => 'firstboot' }, undef); };
    ok(!$compiled && $@, 'unbalanced template phases return no driver');
};
done_testing();
