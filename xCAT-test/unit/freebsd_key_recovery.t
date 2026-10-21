#!/usr/bin/env perl
use strict;
use warnings;
use Carp qw(croak);
use File::Temp qw(tempdir);
use FindBin;
use IPC::Open3;
use Symbol qw(gensym);
use Test::More;
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use xCAT::FreeBSDKey;

plan skip_all => 'Requires root and installed xCAT database backup commands on the lab host'
    unless $> == 0 && -x '/opt/xcat/sbin/dumpxCATdb' && -x '/opt/xcat/sbin/restorexCATdb';
my $directory = tempdir('xcat-freebsd-keys-XXXXXXXX', DIR => '/root', CLEANUP => 1);
my $command = "$FindBin::Bin/../../xCAT-server/sbin/xcat-zfs-key";
for my $name (qw(original restored keys recovered backup)) {
    mkdir("$directory/$name", 0700) or croak $!;
}
local $ENV{XCATCFG} = "SQLite:$directory/original";
local $ENV{XCATBYPASS} = 'Y';
local $ENV{XCAT_SKIPTABLES} = '';
local $ENV{XCATROOT} = '/opt/xcat';
local $ENV{PATH} = '/opt/xcat/bin:/opt/xcat/sbin:/usr/sbin:/usr/bin:/sbin:/bin';

ok(eval { xCAT::FreeBSDKey::identity('n' x 64, 'p' x 63); 1 }, 'node and pool fit the passwd primary key');
ok(!eval { xCAT::FreeBSDKey::identity('n' x 65, 'p' x 63); 1 }, 'oversized identities fail before a database can truncate them');

# Public synthetic key bytes, including NULs. Never use a real pool key here.
my $key = pack('C*', 0 .. 31);
sub write_key {
    my ($path, $bytes) = @_;
    open(my $out, '>', $path) or croak $!;
    binmode($out);
    print {$out} $bytes;
    close($out) or croak $!;
    chmod(0600, $path) or croak $!;
}
sub run {
    my (@argv) = @_;
    my $error = gensym();
    my $pid = open3(my $in, my $out, $error, @argv);
    close($in) or croak $!;
    my $stdout = do { local $/ = undef; <$out> } // '';
    my $stderr = do { local $/ = undef; <$error> } // '';
    close($out) or croak $!;
    close($error) or croak $!;
    waitpid($pid, 0) == $pid or croak $!;
    my $exit = $?;
    unlike($stdout . $stderr, qr/\Q@{[unpack('H*', $key)]}\E/x, 'command output does not contain the key');
    return ($exit, $stdout, $stderr);
}
my $source = "$directory/keys/tank.key";
my $destination = "$directory/recovered/tank.key";
write_key($source, $key);
is((run($^X, $command, 'save', 'node01', 'tank', $source))[0], 0, 'save uses the real xCAT passwd table');
is((run($^X, $command, 'save', 'node01', 'tank', $source))[0], 0, 'saving the same key is idempotent');
write_key($source, 'x' x 32);
isnt((run($^X, $command, 'save', 'node01', 'tank', $source))[0], 0, 'an existing saved key cannot be replaced');
unlink($source) or croak $!;
is((run('/opt/xcat/sbin/dumpxCATdb', '-p', "$directory/backup"))[0], 0, 'ordinary table backup succeeds without a key-specific format');
ok(-f "$directory/backup/passwd.csv", 'the backup contains passwd');
$ENV{XCATCFG} = "SQLite:$directory/restored";
isnt((run($^X, $command, 'restore', 'node01', 'tank', $destination))[0], 0, 'an empty database cannot invent a replacement key');
ok(!-e $destination, 'failed recovery creates no key');
is((run('/opt/xcat/sbin/restorexCATdb', '-p', "$directory/backup"))[0], 0, 'standard restore populates a fresh database');
is((run($^X, $command, 'restore', 'node01', 'tank', $destination))[0], 0, 'recover the key after the original file is gone');
is(xCAT::FreeBSDKey::read_file($destination), $key, 'all 32 bytes survive database backup and restore');
is((stat($destination))[2] & oct('07777'), oct('0600'), 'recovered key is private');
{
    local $) = '12345';
    is((run($^X, $command, 'restore', 'node01', 'tank', "$directory/recovered/group.key"))[0],
        0, 'root can recover a key while using a different effective group');
    is((stat("$directory/recovered/group.key"))[5], 0, 'recovery explicitly retains the required root group');
}
is((run($^X, $command, 'restore', 'node01', 'tank', $destination))[0], 0, 'recovery is idempotent');
write_key($destination, 'y' x 32);
isnt((run($^X, $command, 'restore', 'node01', 'tank', $destination))[0], 0, 'recovery cannot replace another local key');
is(xCAT::FreeBSDKey::read_file($destination), 'y' x 32, 'a different destination remains intact');
isnt((run($^X, $command, 'restore', 'node02', 'tank', "$directory/recovered/other.key"))[0], 0, 'keys are scoped to the node');
isnt((run($^X, $command, 'restore', 'node01', 'other', "$directory/recovered/other.key"))[0], 0, 'keys are scoped to the pool');
for my $mode (oct('0644'), oct('0660')) {
    chmod($mode, $destination) or croak $!;
    isnt((run($^X, $command, 'save', 'node02', 'tank', $destination))[0], 0, 'nonprivate key files are rejected');
}
chmod(0600, $destination) or croak $!;
symlink($destination, "$directory/recovered/link.key") or croak $!;
isnt((run($^X, $command, 'save', 'node02', 'tank', "$directory/recovered/link.key"))[0], 0, 'key symlinks are rejected');
write_key($source, 'z' x 31);
isnt((run($^X, $command, 'save', 'node02', 'tank', $source))[0], 0, 'wrong key sizes are rejected');
done_testing();
