#!/usr/bin/env perl
# XCAT::GenesisPayload decides whether an extracted Genesis payload is complete.
# verify-genesis-payload calls it in the EL spec and in the Ubuntu builder. Each payload
# below leaves out one thing the image needs.
use strict;
use warnings;

use File::Basename qw(dirname);
use File::Path qw(make_path);
use File::Slurper qw(write_text);
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../xCAT-genesis-base/lib";
use Test::More;

use XCAT::GenesisPayload qw(module_commands missing_paths check_payload);

my $OPENSSH_99 = "OpenSSH_9.9p1\n/usr/libexec/openssh/sshd-session\n";
my $OPENSSH_80 = "OpenSSH_8.0p1\n";

# A complete payload: OpenSSH 9.9 sshd plus its session helper, tmux plus a UTF-8 locale.
my @COMPLETE = qw(
  usr/sbin/sshd usr/libexec/openssh/sshd-session usr/bin/tmux
  usr/lib/locale/C.utf8/LC_CTYPE usr/sbin/dhclient usr/bin/mktemp
  usr/bin/awk etc/services usr/bin/openssl usr/bin/wget usr/bin/tar
);

# The payload carries exactly the paths it is given.
sub carries {
    my %present = map { $_ => 1 } @_;
    return sub { $present{ $_[0] } };
}
sub all_but { my %gone = map { $_ => 1 } @_; return carries(grep { !$gone{$_} } @COMPLETE) }

is_deeply([ missing_paths(carries(@COMPLETE), sshd => $OPENSSH_99, required => ['usr/sbin/dhclient']) ],
    [], 'a complete payload passes');

# doxcat calls dhclient with ISC flags. dhclient.conf and dhclient-script are not enough.
is_deeply([ missing_paths(all_but('usr/sbin/dhclient'), sshd => $OPENSSH_99, required => ['usr/sbin/dhclient']) ],
    ['usr/sbin/dhclient (required by the build)'],
    'a payload without dhclient fails and names it');

# sshd 9.9 execs /usr/libexec/openssh/sshd-session for every connection.
is_deeply([ missing_paths(all_but('usr/libexec/openssh/sshd-session'), sshd => $OPENSSH_99) ],
    ['usr/libexec/openssh/sshd-session (this sshd execs it for every connection)'],
    'a payload whose sshd execs sshd-session but does not ship it fails');

# tmux without a UTF-8 locale is what stopped doxcat from ever running.
is_deeply([ missing_paths(all_but('usr/lib/locale/C.utf8/LC_CTYPE'), sshd => $OPENSSH_99) ],
    ['usr/lib/locale/C.utf8/LC_CTYPE (tmux refuses to start without a UTF-8 locale)'],
    'a payload with tmux and no UTF-8 locale fails');

# getdestiny makes its request file with mktemp.
is_deeply([ missing_paths(all_but('usr/bin/mktemp'), sshd => $OPENSSH_99) ],
    ['usr/bin/mktemp (getdestiny makes its request file with it)'],
    'a payload without mktemp fails');

# Genesis is reached over ssh.
is_deeply([ missing_paths(all_but('usr/sbin/sshd')) ],
    ['usr/sbin/sshd (Genesis is reached over ssh)'],
    'a payload without sshd fails');

is_deeply([ missing_paths(carries(grep({ $_ ne 'usr/libexec/openssh/sshd-session' } @COMPLETE),
                'usr/lib/openssh/sshd-session'), sshd => $OPENSSH_99) ],
    [], 'the Debian path of sshd-session counts');

# OpenSSH 8 does not use the helper, so el8 must still pass without it.
is_deeply([ missing_paths(all_but('usr/libexec/openssh/sshd-session'), sshd => $OPENSSH_80) ],
    [], 'an OpenSSH 8 payload passes without sshd-session');

is_deeply([ missing_paths(all_but('usr/lib/locale/C.utf8/LC_CTYPE', 'usr/bin/tmux'), sshd => $OPENSSH_99) ],
    [], 'a payload without tmux needs no locale');

# dracut_install reports a missing binary and returns, so every name the dracut module
# installs has to be checked against the payload. A name starting with "/" is installed at
# that same path; the rest are commands.
my $tmpdir = tempdir(CLEANUP => 1);
my $module = "$tmpdir/module-setup.sh";
write_text($module, <<'SH');
#!/bin/bash

install() {
    dracut_install -o openssl wget tar # a trailing comment
    dracut_install /usr/bin/awk /etc/services
    if command -v dhclient >/dev/null 2>&1; then
        dracut_install dhclient
    fi
}

installkernel() {
    dracut_install notacommand
}
SH
my @commands = module_commands($module);

# The DHCP client is release-dependent, so the module installs it inside a conditional. Those
# names are not the contract; the spec passes the one it wants as a required path.
is_deeply(\@commands, [qw(/etc/services /usr/bin/awk openssl tar wget)],
    'the top-level names of install() are read back, without options, comments, conditionals
     or other functions');

my %names = (commands => \@commands, source => $module, sshd => $OPENSSH_99);
is_deeply([ missing_paths(carries(@COMPLETE), %names) ], [],
    'a payload carrying every command the module names passes');
is_deeply([ missing_paths(carries(grep({ $_ ne 'usr/bin/wget' } @COMPLETE), 'sbin/wget'), %names) ],
    [], 'a command under sbin counts as present');

is_deeply([ missing_paths(all_but('usr/bin/openssl'), %names) ],
    ["openssl (installed by $module)"],
    'a payload without openssl fails and names it');

# doxcat, getdestiny and the firmware wrappers all run awk.
is_deeply([ missing_paths(all_but('usr/bin/awk'), %names) ],
    ["/usr/bin/awk (installed by $module)"],
    'a payload without the absolute path /usr/bin/awk fails');

# Genesis resolves service names with /etc/services.
is_deeply([ missing_paths(all_but('etc/services'), %names) ],
    ["/etc/services (installed by $module)"],
    'a payload without the absolute path /etc/services fails');

# A module the verifier cannot read names from covers nothing, so say so instead of passing.
my $unparsable = "$tmpdir/module-setup-unparsable.sh";
write_text($unparsable, "#!/bin/bash\nsetup() {\n    dracut_install wget\n}\n");
ok(!eval { module_commands($unparsable); 1 }, 'a module with no install() names is refused');
is($@, "verify-genesis-payload: no command name read from $unparsable\n",
    'the empty command list is named');

ok(!eval { module_commands("$tmpdir/no-such-module"); 1 }, 'an unreadable module is refused');
is($@, "verify-genesis-payload: cannot read $tmpdir/no-such-module\n",
    'the unreadable module is named');

# --- the command line reads a real payload tree ---------------------------------------------
my $good = payload_tree(@COMPLETE);
write_text("$good/usr/sbin/sshd", $OPENSSH_99);
my $nodhcp = payload_tree(grep { $_ ne 'usr/sbin/dhclient' } @COMPLETE);
my $nohelper = payload_tree(grep { $_ ne 'usr/libexec/openssh/sshd-session' } @COMPLETE);
write_text("$nohelper/usr/sbin/sshd", $OPENSSH_99);

is_deeply([ check_payload($good, 'usr/sbin/dhclient') ],
    [ 0, "verify-genesis-payload: $good is complete\n" ],
    'a complete payload exits 0 and says so');
is_deeply([ check_payload($nodhcp, 'usr/sbin/dhclient') ],
    [ 1, "verify-genesis-payload: $nodhcp is incomplete:\n"
          . "  usr/sbin/dhclient (required by the build)\n" ],
    'an incomplete payload exits 1 and lists what is missing');
is_deeply([ check_payload($nohelper) ],
    [ 1, "verify-genesis-payload: $nohelper is incomplete:\n"
          . "  usr/libexec/openssh/sshd-session (this sshd execs it for every connection)\n" ],
    'the command line reads usr/sbin/sshd to decide on sshd-session');
is_deeply([ check_payload('--commands-from', $module, $nodhcp) ],
    [ 0, "verify-genesis-payload: $nodhcp is complete\n" ],
    '--commands-from does not require a name installed under a condition');
my $noopenssl = payload_tree(grep { $_ ne 'usr/bin/openssl' } @COMPLETE);
is_deeply([ check_payload("--commands-from=$module", $noopenssl) ],
    [ 1, "verify-genesis-payload: $noopenssl is incomplete:\n"
          . "  openssl (installed by $module)\n" ],
    '--commands-from=<file> checks the names of the module');
is_deeply([ check_payload('--commands-from', $unparsable, $good) ],
    [ 2, "verify-genesis-payload: no command name read from $unparsable\n" ],
    'a module with no command names is a usage error');
is_deeply([ check_payload('--commands-from', "$tmpdir/no-such-module", $good) ],
    [ 2, "verify-genesis-payload: cannot read $tmpdir/no-such-module\n" ],
    'a module file that cannot be read is a usage error');
is_deeply([ check_payload("$tmpdir/does-not-exist") ],
    [ 2, "verify-genesis-payload: not a payload directory: $tmpdir/does-not-exist\n" ],
    'a missing payload directory is a usage error');
is_deeply([ check_payload() ],
    [ 2, "verify-genesis-payload: not a payload directory: <empty>\n" ],
    'no payload directory at all is a usage error');

done_testing();

#---
# payload_tree: a payload directory that carries the given paths as empty files.
#---
sub payload_tree {
    my $root = tempdir(DIR => $tmpdir, CLEANUP => 1);
    for my $path (@_) {
        make_path(dirname("$root/$path"));
        write_text("$root/$path", '');
    }
    return $root;
}
