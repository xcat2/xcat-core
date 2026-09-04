#!/usr/bin/env perl
use strict;
use warnings;

use File::Path qw(make_path);
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

my $script = "$FindBin::Bin/../../xCAT/postscripts/sudoer";
plan skip_all => 'sudoer postscript not found' unless -r $script;
plan skip_all => 'postscript targets Linux nodes' unless $^O eq 'linux';

my $source = read_file($script);

sub field_reply {
    my ($field) = @_;
    return <<"XML";
<xcatresponse>
  <data>
    <content>$field</content>
    <desc>xcat_secure_pw</desc>
  </data>
</xcatresponse>
<xcatresponse>
  <serverdone></serverdone>
</xcatresponse>
XML
}

my $hash_reply   = field_reply('$6$saltsalt$hashhashhash');
my $locked_reply = field_reply('!');

my $error_reply = <<'XML';
<xcatresponse>
  <error>Unable to get the password hash for xcat_secure_pw: xcat is not a configured sudoer</error>
  <errorcode>1</errorcode>
</xcatresponse>
<xcatresponse>
  <serverdone></serverdone>
</xcatresponse>
XML

my $managed     = '/etc/sudoers.d/xcat-sudoer';
my $legacy_rule = "xcat ALL=(ALL) NOPASSWD: ALL\n";
my $legacy_tty  = "Defaults:xcat !requiretty\n";

sub managed_for {
    my ($name) = @_;
    return "# xCAT sudoer: $name\n$name ALL=(ALL) NOPASSWD: ALL\nDefaults:$name !requiretty\n";
}

# Build a scratch tree. Existing accounts are passwd lines "name:uid:shell";
# the useradd stub appends the account it creates, so getent sees it.
sub scratch_tree {
    my (%opt) = @_;
    my $root = tempdir(CLEANUP => 1);
    make_path("$root/bin", "$root/etc", "$root/xcatpost/hostkeys");

    my $passwd = '';
    foreach my $account (@{ $opt{accounts} || [] }) {
        my ($name, $uid, $shell) = split /:/, $account;
        make_path("$root/home/$name");
        $passwd .= "$name:x:$uid:100::$root/home/$name:$shell\n";
    }
    write_file("$root/etc/passwd", $passwd);
    write_stub("$root/bin/useradd",
        "echo \"useradd \$*\" >> '$root/calls'\n"
      . ($opt{useradd_fails} ? "exit 1\n"
          : "name=\$2; mkdir -p '$root/home/'\$name\n"
          . "echo \"\$name:x:1001:100::$root/home/\$name:/bin/bash\" >> '$root/etc/passwd'\n"));
    write_stub("$root/bin/usermod",
        "echo \"usermod \$*\" >> '$root/calls'\n" . ($opt{usermod_fails} ? "exit 1\n" : ''));
    write_stub("$root/bin/getent",
        "awk -F: -v n=\"\$2\" '\$1 == n' '$root/etc/passwd'\n");
    write_stub("$root/bin/visudo",
        "echo \"visudo \$*\" >> '$root/calls'\n" . ($opt{visudo_rejects} ? "exit 1\n" : ''));
    write_stub("$root/bin/getcredentials.awk",
        "echo \"getcredentials \$*\" >> '$root/calls'\ncat '$root/reply.xml'\n");
    write_stub("$root/bin/allowcred.awk", "sleep 30\n");
    write_stub("$root/bin/logger", "echo \"\$*\" >> '$root/log'\n");
    write_stub("$root/bin/chown", "exit 0\n");
    write_file("$root/xcatlib.sh", "restartservice(){ :; }\n");
    write_file("$root/etc/redhat-release", "stub\n");
    write_file("$root/etc/login.defs", "UID_MIN 1000\nUID_MAX 60000\n");
    # ssh-keygen leaves a trailing space after an empty comment
    write_file("$root/xcatpost/hostkeys/ssh_host_rsa_key.pub", "ssh-rsa RSAKEY \n");
    write_file("$root/xcatpost/hostkeys/ssh_host_dsa_key.pub", "ssh-dss DSAKEY \n");
    # The includedir line names the scratch directory because the path
    # rewrite below also rewrites the pattern the postscript greps for.
    my $sudoers = "root ALL=(ALL) ALL\n";
    $sudoers .= "#includedir $root/etc/sudoers.d\n" unless $opt{no_sudoers_d};
    $sudoers .= $opt{legacy} x 1 if $opt{legacy};
    make_path("$root/etc/sudoers.d") unless $opt{no_sudoers_d};
    write_file("$root/etc/sudoers", $sudoers);

    my $src = $source;
    $src =~ s{/usr/sbin/(useradd|usermod)}{$root/bin/$1}g;
    $src =~ s{/etc/sudoers\.d}{$root/etc/sudoers.d}g;
    $src =~ s{ /etc/sudoers\b}{ $root/etc/sudoers}g;
    $src =~ s{/etc/redhat-release}{$root/etc/redhat-release}g;
    $src =~ s{/etc/login\.defs}{$root/etc/login.defs}g;
    $src =~ s{/xcatpost/hostkeys}{$root/xcatpost/hostkeys}g;
    write_file("$root/sudoer", $src);
    chmod 0755, "$root/sudoer";
    return $root;
}

# Run the postscript in a scratch tree and collect what it changed.
sub run_sudoer {
    my (%opt) = @_;
    my $root = $opt{root} || scratch_tree(%opt);
    my $user = $opt{user} || 'xcat';
    my $args = defined $opt{args} ? $opt{args} : '';

    write_file("$root/reply.xml", defined $opt{reply} ? $opt{reply} : '');
    unlink "$root/calls", "$root/log";

    system(qq{cd '$root' && MASTER='10.0.0.1' XCATSERVER='10.0.0.1:3001' }
         . qq{PATH="$root/bin:\$PATH" ./sudoer $args >/dev/null 2>&1});
    my $rc = $? >> 8;

    return {
        root            => $root,
        rc              => $rc,
        calls           => read_file("$root/calls"),
        log             => read_file("$root/log"),
        sudoers         => read_file("$root/etc/sudoers"),
        managed         => read_file("$root$managed"),
        authorized_keys => read_file("$root/home/$user/.ssh/authorized_keys"),
    };
}

sub read_file {
    my ($p) = @_;
    return '' unless -e $p;
    open my $fh, '<', $p or die "open $p: $!";
    local $/;
    my $content = <$fh>;
    close $fh;
    return defined $content ? $content : '';
}

sub write_file {
    my ($p, $c) = @_;
    open my $fh, '>', $p or die "open $p: $!";
    print {$fh} $c;
    close $fh;
    return;
}

sub write_stub {
    my ($p, $body) = @_;
    write_file($p, "#!/bin/sh\n$body");
    chmod 0755, $p;
    return;
}

sub leftovers {
    my ($root) = @_;
    return join ',', grep { /xcat-sudoer\.|sudoers\.xcat\./ } glob("$root/etc/sudoers.d/* $root/etc/*");
}

# --- default user, no passwd row: the reply is the locked field --------------
{
    my $r = run_sudoer(reply => $locked_reply);

    is($r->{rc}, 0, 'the postscript completes without a password');
    like($r->{calls}, qr{^useradd -m xcat$}m, 'the xcat account is created');
    unlike($r->{calls}, qr{^useradd .*-p}m, 'no password is passed to useradd');
    like($r->{calls}, qr{^usermod -p ! xcat$}m, 'the locked field from the reply is applied');
    is(scalar(() = $r->{calls} =~ /^getcredentials/mg), 1, 'a locked reply is not retried');
    like($r->{calls}, qr{^getcredentials xcat_secure_pw:xcat$}m,
        'the password field is requested for the xcat user');
    is($r->{managed}, managed_for('xcat'),
        'the managed sudoers.d file records the account, the rule and the requiretty default');
    is((stat "$r->{root}$managed")[2] & 07777, 0440, 'the managed file is mode 0440');
    like($r->{calls}, qr{^visudo -cf }m, 'the managed file is checked with visudo before it is installed');
    is(leftovers($r->{root}), '', 'no temporary sudoers file is left behind');
    unlike($r->{sudoers}, qr{xcat}, '/etc/sudoers itself is not touched');
    like($r->{authorized_keys}, qr{^ssh-rsa RSAKEY$}m, 'the RSA host key is installed');
    like($r->{authorized_keys}, qr{^ssh-dss DSAKEY$}m, 'the DSA host key is installed');
    like($r->{log}, qr{xcat has no password in the passwd table}, 'the locked account is logged');
}

# --- default user, passwd row present ---------------------------------------
{
    my $r = run_sudoer(reply => $hash_reply);

    is($r->{rc}, 0, 'the postscript completes with a password');
    like($r->{calls}, qr{^useradd -m xcat$}m, 'the account is created before the password is set');
    like($r->{calls}, qr{^usermod -p \$6\$saltsalt\$hashhashhash xcat$}m,
        'the hash from the passwd table is applied to the account');
    like($r->{log}, qr{set the password of xcat}, 'the applied password is logged');
}

# --- another user name, then a rename revokes the previous account -----------
{
    my $r = run_sudoer(user => 'ops', args => '-u ops', reply => $hash_reply);

    is($r->{rc}, 0, 'the postscript completes for a named user');
    like($r->{calls}, qr{^useradd -m ops$}m, 'the named account is created');
    like($r->{calls}, qr{^getcredentials xcat_secure_pw:ops$}m,
        'the password field is requested for the named user');
    like($r->{calls}, qr{^usermod -p \$6\$saltsalt\$hashhashhash ops$}m,
        'the hash is applied to the named user');
    is($r->{managed}, managed_for('ops'), 'the managed file names the user');

    my $opskeys = "$r->{root}/home/ops/.ssh/authorized_keys";
    make_path("$r->{root}/home/ops/.ssh");
    write_file($opskeys, read_file($opskeys) . "ssh-ed25519 OPSKEY ops\@laptop\n");
    my $again = run_sudoer(root => $r->{root}, user => 'admin', args => '-u admin', reply => $hash_reply);
    is($again->{rc}, 0, 'a rerun with another name completes');
    is($again->{managed}, managed_for('admin'), 'the managed file names the new sudoer only');
    like($again->{calls}, qr{^usermod -p ! ops$}m, 'the previous sudoer is locked');
    unlike(read_file($opskeys), qr{RSAKEY|DSAKEY}, 'the cluster keys are removed from the previous sudoer');
    like(read_file($opskeys), qr{^ssh-ed25519 OPSKEY ops\@laptop$}m, 'the other key of the previous sudoer stays');
    like($again->{log}, qr{revoked the previous sudoer ops}, 'the revocation is logged');
    is(leftovers($r->{root}), '', 'no temporary file is left behind by the rename');

    my $same = run_sudoer(root => $r->{root}, user => 'admin', args => '-u admin', reply => $hash_reply);
    unlike($same->{calls}, qr{^usermod -p ! }m, 'a rerun with the same name revokes nothing');
}

# --- the lines of the previous postscript are moved out of /etc/sudoers ------
{
    my $legacy = $legacy_rule . $legacy_tty . $legacy_rule . $legacy_tty;
    my $root = scratch_tree(legacy => $legacy, accounts => ['xcat:1001:/bin/bash']);
    make_path("$root/home/xcat/.ssh");
    write_file("$root/home/xcat/.ssh/authorized_keys", "ssh-rsa RSAKEY\nssh-dss DSAKEY\n");
    my $r = run_sudoer(root => $root, reply => $hash_reply);

    is($r->{rc}, 0, 'the postscript completes on a node set up by the previous version');
    unlike($r->{sudoers}, qr{xcat}, 'the legacy lines are gone from /etc/sudoers');
    like($r->{sudoers}, qr{^root ALL=\(ALL\) ALL$}m, 'the other lines of /etc/sudoers stay');
    like($r->{sudoers}, qr{^#includedir }m, 'the includedir line stays');
    is((stat "$r->{root}/etc/sudoers")[2] & 07777, 0440, '/etc/sudoers is mode 0440 after the migration');
    is($r->{managed}, managed_for('xcat'), 'the rule now lives in the managed file');
    is(scalar(() = $r->{authorized_keys} =~ /RSAKEY/g), 1,
        'the key written by the previous version is recognized and not duplicated');
    unlike($r->{calls}, qr{^usermod -p ! xcat$}m, 'the legacy account is not locked when it stays the sudoer');
    is(scalar(() = $r->{calls} =~ /^visudo -cf /mg), 2, 'both the migrated /etc/sudoers and the managed file are checked');
}
{
    my $root = scratch_tree(reply => $hash_reply, legacy => $legacy_rule . $legacy_tty,
        accounts => ['xcat:1001:/bin/bash']);
    make_path("$root/home/xcat/.ssh");
    write_file("$root/home/xcat/.ssh/authorized_keys", "ssh-rsa RSAKEY\nssh-dss DSAKEY\n");
    my $r = run_sudoer(root => $root, user => 'ops', args => '-u ops', reply => $hash_reply);

    is($r->{rc}, 0, 'a rename on a node set up by the previous version completes');
    unlike($r->{sudoers}, qr{xcat}, 'the legacy lines are gone after the rename');
    like($r->{calls}, qr{^usermod -p ! xcat$}m, 'the legacy xcat account is locked when the sudoer is renamed');
    is(read_file("$root/home/xcat/.ssh/authorized_keys"), '', 'the cluster keys are removed from the legacy account');
    is($r->{managed}, managed_for('ops'), 'the managed file names the new sudoer');
}
{
    my $r = run_sudoer(reply => $hash_reply, legacy => $legacy_rule, accounts => ['xcat:1001:/bin/bash'],
        visudo_rejects => 1);

    isnt($r->{rc}, 0, 'a migration that visudo rejects fails the postscript');
    like($r->{sudoers}, qr{^xcat ALL=}m, '/etc/sudoers is left as it was');
    is($r->{managed}, '', 'no managed file is written when the migration fails');
    is(leftovers($r->{root}), '', 'no temporary file is left behind by the failed migration');
    like($r->{log}, qr{unable to take the legacy rule out of \S*/etc/sudoers}, 'the failed migration is logged');
}

# --- an existing login account is kept, with its other keys -------------------
{
    my $root = scratch_tree(accounts => ['xcat:1001:/bin/bash']);
    make_path("$root/home/xcat/.ssh");
    write_file("$root/home/xcat/.ssh/authorized_keys", "ssh-ed25519 ADMINKEY admin\@mgmt\n");
    my $r = run_sudoer(root => $root, reply => $hash_reply);

    is($r->{rc}, 0, 'the postscript completes for an existing account');
    unlike($r->{calls}, qr{^useradd}m, 'an existing login account is not recreated');
    like($r->{calls}, qr{^usermod -p \$6\$saltsalt\$hashhashhash xcat$}m,
        'the password of the existing account is refreshed');
    like($r->{authorized_keys}, qr{^ssh-ed25519 ADMINKEY admin\@mgmt$}m,
        'the keys already in authorized_keys survive');
    like($r->{authorized_keys}, qr{^ssh-rsa RSAKEY$}m, 'the cluster key is added without the trailing space');

    my $again = run_sudoer(root => $root, reply => $hash_reply);
    is(scalar(() = $again->{authorized_keys} =~ /RSAKEY/g), 1, 'a rerun does not duplicate the cluster key');
    is(scalar(() = $again->{authorized_keys} =~ /ADMINKEY/g), 1, 'a rerun does not duplicate the other key');
}

# --- without sudoers.d the rule is appended once to /etc/sudoers -------------
{
    my $r = run_sudoer(reply => $hash_reply, no_sudoers_d => 1);

    is($r->{rc}, 0, 'the postscript completes without sudoers.d');
    like($r->{sudoers}, qr{^xcat ALL=\(ALL\) NOPASSWD: ALL$}m, 'the rule is appended to /etc/sudoers');
    like($r->{sudoers}, qr{^Defaults:xcat !requiretty$}m, 'requiretty is disabled on Red Hat');
    is($r->{managed}, '', 'no managed file is written without sudoers.d');

    my $again = run_sudoer(root => $r->{root}, reply => $hash_reply);
    is(scalar(() = $again->{sudoers} =~ /^xcat ALL=/mg), 1, 'a rerun does not duplicate the rule');
    is(scalar(() = $again->{sudoers} =~ /^Defaults:xcat/mg), 1, 'a rerun does not duplicate the default');
}

# --- a dotted name only touches its own home ----------------------------------
{
    my $root = scratch_tree(accounts => ['opsXadmin:1002:/bin/bash', 'ops.admin:1003:/bin/bash']);
    make_path("$root/home/opsXadmin/.ssh");
    write_file("$root/home/opsXadmin/.ssh/authorized_keys", "KEEP\n");
    write_file("$root/home/opsXadmin/keep.txt", "KEEP\n");
    my $r = run_sudoer(root => $root, user => 'ops.admin', args => '-u ops.admin', reply => $hash_reply);

    is($r->{rc}, 0, 'the postscript completes for a dotted name');
    like($r->{authorized_keys}, qr{RSAKEY}, 'the keys land in the home of the dotted name');
    is(read_file("$root/home/opsXadmin/.ssh/authorized_keys"), "KEEP\n",
        'the authorized_keys of the similarly named account are untouched');
    is(read_file("$root/home/opsXadmin/keep.txt"), "KEEP\n",
        'the home of the similarly named account is untouched');
}

# --- failures leave the account unprivileged and drop the earlier grant -------
{
    my $r = run_sudoer(reply => '', accounts => ['xcat:1001:/bin/bash']);

    isnt($r->{rc}, 0, 'a missing reply fails the postscript');
    is(scalar(() = $r->{calls} =~ /^getcredentials/mg), 3, 'the request is retried three times');
    unlike($r->{calls}, qr{^usermod}m, 'the password is left unchanged without a reply');
    is($r->{managed}, '', 'no sudo rule is granted without a reply');
    is($r->{authorized_keys}, '', 'no key is installed without a reply');
    like($r->{log}, qr{no password for xcat, leaving the account unprivileged: no reply from 10\.0\.0\.1},
        'the missing reply is logged');
}
{
    my $first = run_sudoer(reply => $hash_reply);
    is($first->{managed}, managed_for('xcat'), 'a successful run grants the rule');

    my $r = run_sudoer(root => $first->{root}, reply => $error_reply);
    isnt($r->{rc}, 0, 'a server error fails the postscript');
    is(scalar(() = $r->{calls} =~ /^getcredentials/mg), 1, 'a server error is not retried');
    unlike($r->{calls}, qr{^usermod}m, 'the password is left unchanged on a server error');
    is($r->{managed}, '', 'the rule of the earlier run is removed on a server error');
    like($r->{log}, qr{leaving the account unprivileged: .*not a configured sudoer}, 'the server error is logged');
}
{
    my $r = run_sudoer(reply => $hash_reply, usermod_fails => 1);

    isnt($r->{rc}, 0, 'a failed usermod fails the postscript');
    is($r->{managed}, '', 'no sudo rule is granted when the password cannot be set');
    is($r->{authorized_keys}, '', 'no key is installed when the password cannot be set');
    like($r->{log}, qr{unable to set the password of xcat}, 'the failed password update is logged');
}
{
    my $r = run_sudoer(reply => $hash_reply, useradd_fails => 1);

    isnt($r->{rc}, 0, 'a failed useradd fails the postscript');
    unlike($r->{calls}, qr{^getcredentials}m, 'no credential is requested for a missing account');
    is($r->{managed}, '', 'no sudo rule is granted for a missing account');
    is($r->{authorized_keys}, '', 'no key is installed for a missing account');
}
{
    my $r = run_sudoer(reply => $hash_reply, visudo_rejects => 1);

    isnt($r->{rc}, 0, 'a managed file that visudo rejects fails the postscript');
    is($r->{managed}, '', 'the rejected managed file is not installed');
    is(leftovers($r->{root}), '', 'the rejected temporary file is removed');
    is($r->{authorized_keys}, '', 'no key is installed when the rule cannot be written');
    like($r->{log}, qr{unable to write .*xcat-sudoer}, 'the rejected rule is logged');
}

# --- root, service accounts, and non-login accounts are refused ---------------
foreach my $case (
    [ 'root',   'root:0:/bin/bash',          qr{root is a system account \(uid 0\)} ],
    [ 'sshd',   'sshd:74:/sbin/nologin',     qr{sshd is a system account \(uid 74\)} ],
    [ 'nobody', 'nobody:65534:/bin/bash',    qr{nobody is a system account \(uid 65534\)} ],
    [ 'batch',  'batch:1005:/sbin/nologin',  qr{batch has no login shell} ],
    [ 'noshell', 'noshell:1006:',            qr{noshell has no login shell} ],
) {
    my ($name, $account, $message) = @$case;
    my $r = run_sudoer(user => $name, args => "-u $name", reply => $hash_reply, accounts => [$account]);

    isnt($r->{rc}, 0, "$name is refused");
    unlike($r->{calls}, qr{^(useradd|usermod|getcredentials)}m, "nothing is changed for $name");
    is($r->{managed}, '', "no sudo rule is written for $name");
    is($r->{authorized_keys}, '', "the authorized_keys of $name are not touched");
    like($r->{log}, $message, "the refusal of $name is logged");
}

# --- bad arguments ------------------------------------------------------------
{
    my $r = run_sudoer(args => '-u xcat -p secret', reply => $hash_reply);

    isnt($r->{rc}, 0, 'a command-line password is rejected');
    unlike($r->{calls}, qr{^useradd}m, 'no account is created for a rejected call');
}
{
    my $r = run_sudoer(args => q{-u 'bad name'}, reply => $hash_reply);

    isnt($r->{rc}, 0, 'a user name with a space is rejected');
    unlike($r->{calls}, qr{^useradd}m, 'no account is created for a bad name');
}

done_testing();
