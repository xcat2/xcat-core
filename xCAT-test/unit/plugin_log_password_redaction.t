#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use File::Spec;
use Test::More;

my $repo_root = File::Spec->catdir( $FindBin::Bin, '..', '..' );
my %plugin;
for my $name (qw(zvm bmcconfig energy)) {
    my $path = File::Spec->catfile( $repo_root, 'xCAT-server', 'lib', 'xcat', 'plugins', "$name.pm" );
    plan skip_all => "$name.pm not found" unless -r $path;
    open( my $fh, '<', $path ) or die "Unable to read $path: $!";
    $plugin{$name} = do { local $/; <$fh> };
    close($fh);
}
my %module;
for my $name (qw(PPCcfg CIMUtils zvmUtils)) {
    my $path = File::Spec->catfile( $repo_root, 'perl-xCAT', 'xCAT', "$name.pm" );
    plan skip_all => "$name.pm not found" unless -r $path;
    open( my $mfh, '<', $path ) or die "Unable to read $path: $!";
    $module{$name} = do { local $/; <$mfh> };
    close($mfh);
}
my $ppccfg = $module{PPCcfg};

# The z/VM plugin logs the smcli command lines it runs. The logged text must
# mask the disk, image and root passwords while the executed command keeps
# them.
my @leaks = grep { /printSyslog/ and /\$(?:readPw|writePw|multiPw|tgtPw|pw)\b|\$passwd\b/ }
  split /\n/, $plugin{zvm};
is_deeply( \@leaks, [], 'no zvm printSyslog line interpolates a password variable' );

like( $plugin{zvm}, qr/printSyslog\([^;]*-R xxxxxxxx -W xxxxxxxx -M xxxxxxxx/,
    'the zvm disk password log lines carry the mask' );
like( $plugin{zvm}, qr/Image_Password_Set_DM -T \$userId -p xxxxxxxx/,
    'the zvm image password log line carries the mask' );
like( $plugin{zvm}, qr/replace_root_password,xxxxxxxx/,
    'the SLES provision log line masks the root password' );
like( $plugin{zvm}, qr/replace_rootpw,xxxxxxxx/,
    'the RedHat provision log line masks the root password' );

# The executed commands must still carry the real passwords.
like( $plugin{zvm}, qr/Image_Disk_Create_DM[^\n]*-R \$readPw -W \$writePw -M \$multiPw/,
    'the executed disk create still uses the real passwords' );

# The page and spool volume log string is built by operand position, so a
# decoy value in another operand cannot divert the mask from the password.
unlike( $plugin{zvm}, qr/printSyslog\("smcli Page_or_Spool_Volume_Add[^"]*\$argStr/,
    'the page volume log line does not hold the joined options' );
like( $plugin{zvm}, qr/\( \$i == 8 \) \? " -k \\"\$options\[\$i\]xxxxxxxx\\""/,
    'the page volume log string masks the password operand by position' );
like( $plugin{zvm}, qr/Page_or_Spool_Volume_Add -T \$hcpUserId \$argStr"`/,
    'the executed page volume command keeps the real options' );

# A failed command echoes its command string to syslog and to the client, so
# the string handed to the checker must already be masked.
unlike( $plugin{zvm}, qr/checkSSH_Rc\([^;]*\$(?:readPw|writePw|multiPw|tgtPw|pw)\b/s,
    'no checkSSH_Rc call carries a password variable' );
my $masked_checks = () = $plugin{zvm} =~ /checkSSH_Rc\([^;]*-R xxxxxxxx -W xxxxxxxx -M xxxxxxxx/gs;
is( $masked_checks, 2, 'both disk create checkSSH_Rc strings carry the mask' );

# A z/VM directory entry carries the logon password in the USER statement and
# the disk passwords after the MDISK access mode. Drive the real redactor.
my ($redactsub) = $module{zvmUtils} =~ /(sub redact_directory_entry \{.*?\n\}\n)/s;
BAIL_OUT('could not extract redact_directory_entry from zvmUtils.pm') unless $redactsub;
eval "package DirRedact; $redactsub 1;" or BAIL_OUT("could not evaluate redact_directory_entry: $@");
sub dir { return DirRedact::redact_directory_entry( 'xCAT::zvmUtils', $_[0] ); }

unlike( dir("USER LNX1 SENTUSERPW 512M 1G G"), qr/SENTUSERPW/,
    'the USER statement logon password is masked' );
unlike( dir("IDENTITY LNX2 SENTIDPW 512M 1G G"), qr/SENTIDPW/,
    'the IDENTITY statement logon password is masked' );
unlike( dir("MDISK 0100 3390 0001 10016 EMC2C4 MR SENTRPW SENTWPW SENTMPW"), qr/SENTRPW|SENTWPW|SENTMPW/,
    'the MDISK disk passwords are masked' );
is( dir("MDISK 0100 3390 0001 10016 EMC2C4 MR"), "MDISK 0100 3390 0001 10016 EMC2C4 MR",
    'an MDISK statement without passwords is kept whole' );
unlike( dir("MDISK=VDEV=0100 DEVTYPE=3390 MODE=MR READPW=SENTKW"), qr/SENTKW/,
    'the keyword form read password is masked' );
unlike( dir("IDENT MAINT SENTABBR 512M 1G G"), qr/SENTABBR/,
    'the abbreviated IDENT logon password is masked' );
unlike( dir("MDISK 0199 3390 DEVNO 0201 MR SENTDEVR SENTDEVW"), qr/SENTDEVR|SENTDEVW/,
    'the DEVNO form disk passwords are masked' );
unlike( dir("READPASSWORD=SENTRP WRITEPASSWORD=SENTWP MULTIPASSWORD=SENTMP"), qr/SENTRP|SENTWP|SENTMP/,
    'the full keyword password names are masked' );
unlike( dir("APPCPASS LUA LUB USERX SENTAPPC"), qr/SENTAPPC/,
    'the APPCPASS statement is masked' );
is( dir("MDISK 0401 FB-512 V-DISK 8000 MW SENTREAD"),
    "MDISK 0401 FB-512 V-DISK 8000 MW xxxxxxxx",
    'the V-DISK form read password is masked' );
is( dir("MDISK 0401 FB-512 V-DISK 8000 MW SENTR SENTW SENTM"),
    "MDISK 0401 FB-512 V-DISK 8000 MW xxxxxxxx",
    'the V-DISK form masks all three passwords' );
is( dir("MDISK 0199 3390 DEVNO 0201 MR\nNICDEF 0600 TYPE QDIO LAN SYSTEM VSW1"),
    "MDISK 0199 3390 DEVNO 0201 MR\nNICDEF 0600 TYPE QDIO LAN SYSTEM VSW1",
    'a passwordless record never masks across the line into the next record' );

# A directory comment keeps its record shape, so a commented credential
# record still carries the passwords.
unlike( dir("* USER LNX1 SENTCOMU 512M 1G G"), qr/SENTCOMU/,
    'a commented USER record is masked' );
unlike( dir("* IDENT LNX2 SENTCOMI 512M 1G G"), qr/SENTCOMI/,
    'a commented IDENT record is masked' );
unlike( dir("* MDISK 0100 3390 0001 10016 EMC2C4 MR SENTCOMR SENTCOMW"), qr/SENTCOMR|SENTCOMW/,
    'a commented range MDISK record is masked' );
unlike( dir("* MDISK 0401 FB-512 V-DISK 8000 MW SENTCOMV"), qr/SENTCOMV/,
    'a commented V-DISK record is masked' );
unlike( dir("*APPCPASS LUA LUB USERX SENTCOMA"), qr/SENTCOMA/,
    'a commented APPCPASS record is masked' );
unlike( dir("** USER LNX1 SENTSTARS 512M 1G G"), qr/SENTSTARS/,
    'a doubly commented USER record is masked' );
unlike( dir("COMMAND XAUTOLOG VSEVM PW SENTAUTO"), qr/SENTAUTO/,
    'the COMMAND statement masks its whole text' );
unlike( dir("* COMMAND XAUTOLOG VSEVM PW SENTCAUTO"), qr/SENTCAUTO/,
    'a commented COMMAND statement masks its whole text' );
like( dir("USER LNX1 SENTUSERPW 512M 1G G\nNICDEF 0600 TYPE QDIO LAN SYSTEM VSW1"),
    qr/NICDEF 0600 TYPE QDIO LAN SYSTEM VSW1/,
    'the statements beside the passwords are kept' );

# Every directory query sink routes through the redactor. A bare output log
# is allowed only for command status text, never near a directory read.
my @zvm_lines = split /\n/, $plugin{zvm};
my @raw_directory_logs;
for my $index ( 0 .. $#zvm_lines ) {
    next unless $zvm_lines[$index] =~ /printSyslog\("\$out"\)/;
    my $start = $index - 6 < 0 ? 0 : $index - 6;
    my $window = join "\n", @zvm_lines[ $start .. $index ];
    push @raw_directory_logs, $index + 1
      if $window =~ /Image[_A-Za-z]*Query_DM|grep -a -i "MDISK"/;
}
is_deeply( \@raw_directory_logs, [], 'no directory query output is logged bare' );
like( $module{zvmUtils}, qr/printSyslog\("findUsablezHcpNetwork\(\) " \. xCAT::zvmUtils->redact_directory_entry\(\$userEntry\)\)/,
    'the network search logs the redacted user entry' );
like( $module{zvmUtils}, qr/printSyslog\("findUsablezHcpNetwork\(\) " \. xCAT::zvmUtils->redact_directory_entry\(\$userProfile\)\)/,
    'the profile fallback logs the redacted profile' );

# The clone loops keep the query output beyond the log line, so the text is
# redacted at the source, before the failure checker and the retained list.
my $at_source = () = $plugin{zvm} =~ /\$out = xCAT::zvmUtils->redact_directory_entry\(\$out\);\n\s*\(\$rc, \$outmsg\) = xCAT::zvmUtils->checkSSH_Rc\(/g;
is( $at_source, 2, 'both clone loops redact the query output at the source' );

# The directory helpers return the raw records for functional use, so the
# failure checker receives a redacted copy instead.
my $redacted_copies = () = $module{zvmUtils} =~ /checkSSH_Rc\([^;]*xCAT::zvmUtils->redact_directory_entry\(\$out\), \$node \);/gs;
is( $redacted_copies, 4, 'the four directory helpers hand a redacted copy to the failure checker' );

# A password that spells an error word makes checkOutput echo the directory.
like( $plugin{zvm}, qr/Did not get the \$sourceId directory\. Return output was: " \. xCAT::zvmUtils->redact_directory_entry\(\$out\)/,
    'the directory fetch error echoes the redacted text' );
like( $plugin{zvm}, qr/Did not get the \$sourceId mini disks\. Return output was: " \. xCAT::zvmUtils->redact_directory_entry\(\$out\)/,
    'the mini disk fetch error echoes the redacted text' );
my $raw_disk_echoes = () = $plugin{zvm} =~ /printLn\( \$callback, "\$(?:srcDisks|mdisks)\[0\]" \)/g;
is( $raw_disk_echoes, 0, 'no disk list error echoes a raw record' );
my $masked_disk_echoes = () = $plugin{zvm} =~ /printLn\( \$callback, xCAT::zvmUtils->redact_directory_entry\(\$(?:srcDisks|mdisks)\[0\]\) \)/g;
is( $masked_disk_echoes, 4, 'the four disk list errors echo the redacted record' );

# The verbose CIM dump holds a basic authorization header.
unlike( $module{CIMUtils}, qr/callback\}\(\{ data => \[[^;]*\$http_request->as_string\(\)/s,
    'the CIM verbose dump does not hold the raw request' );
like( $module{CIMUtils}, qr/\$request_text =~ s\/\^\(Authorization:\)\.\*\$\/\$1 xxxxxxxx\/mi;/,
    'the CIM verbose dump masks the authorization header' );

# The BMC attribute report names the state of the password, never its value.
unlike( $plugin{bmcconfig}, qr/Pass=\$password/,
    'the bmcconfig attribute report does not hold the password' );
like( $plugin{bmcconfig}, qr/Pass=\$passtate/,
    'the bmcconfig attribute report shows the password state' );

unlike( $plugin{energy}, qr/pass?owrd \[\$password\]|password \[\$password\]/,
    'the energy access message does not hold the password' );

# The hardware control point report names the user and masks the password.
unlike( $ppccfg, qr/user\/passwd for \$_ is [^"]*\{password\}/,
    'no PPCcfg credential report holds the password' );
my $masked_reports = () = $ppccfg =~ /user\/passwd for \$_ is \S+ xxxxxxxx/g;
is( $masked_reports, 3, 'the three PPCcfg credential reports carry the mask' );

done_testing();
