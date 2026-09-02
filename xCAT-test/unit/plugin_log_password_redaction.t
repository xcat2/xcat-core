#!/usr/bin/env perl
use strict;
use warnings;
no warnings 'once';

our @executed_commands;
BEGIN {
    no warnings 'redefine';
    *CORE::GLOBAL::readpipe = sub {
        my ($command) = @_;
        push @executed_commands, $command;
        return "$command: off\n" if $command =~ m{/opt/xcat/bin/rpower};
        return '';
    };
}

use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use HTTP::Request;
use POSIX qw(_exit);
use Test::More;

use XCAT::Test::File qw(repo_path);
use xCAT::CIMUtils;
use xCAT::PPCcfg;
use xCAT::zvmUtils;

{
    package xCAT::IMMUtils;
    sub setupIMM { return; }
}
$INC{'xCAT/IMMUtils.pm'} = __FILE__;

foreach my $relative (
    qw(
      xCAT-server/lib/xcat/plugins/bmcconfig.pm
      xCAT-server/lib/xcat/plugins/energy.pm
      xCAT-server/lib/xcat/plugins/zvm.pm
      )
  ) {
    my $plugin_path = repo_path($relative);
    require $plugin_path;
}

{
    package XCAT::Test::BmcTable;

    sub getNodesAttribs {
        return { node1 => [ { bmc => 'bmc1' } ] };
    }
}

{
    package XCAT::Test::EnergyTable;

    sub getNodesAttribs {
        my ($self) = @_;
        return { node1 => [ { bmc => 'hcp1' } ] } if $self->{name} eq 'ipmi';
        return { node1 => [ {} ] } if $self->{name} eq 'ppc';
        return { node1 => [ { mgt => 'ipmi' } ] } if $self->{name} eq 'nodehm';
        return {};
    }

    sub getAttribs {
        my ($self) = @_;
        return { username => 'energy-user', password => 'SENTENERGYPASS' }
          if $self->{name} eq 'passwd';
        return undef;
    }
}

sub directory_entry {
    return xCAT::zvmUtils->redact_directory_entry( $_[0] );
}

subtest 'z/VM directory entries are redacted as data' => sub {
    unlike( directory_entry('USER LNX1 SENTUSERPW 512M 1G G'), qr/SENTUSERPW/,
        'USER logon password is masked' );
    unlike( directory_entry('IDENTITY LNX2 SENTIDPW 512M 1G G'), qr/SENTIDPW/,
        'IDENTITY logon password is masked' );
    unlike( directory_entry('MDISK 0100 3390 0001 10016 EMC2C4 MR SENTRPW SENTWPW SENTMPW'),
        qr/SENTRPW|SENTWPW|SENTMPW/, 'MDISK passwords are masked' );
    is( directory_entry('MDISK 0100 3390 0001 10016 EMC2C4 MR'),
        'MDISK 0100 3390 0001 10016 EMC2C4 MR',
        'a passwordless MDISK statement is unchanged' );
    unlike( directory_entry('MDISK=VDEV=0100 DEVTYPE=3390 MODE=MR READPW=SENTKW'), qr/SENTKW/,
        'keyword passwords are masked' );
    unlike( directory_entry('IDENT MAINT SENTABBR 512M 1G G'), qr/SENTABBR/,
        'abbreviated IDENT logon password is masked' );
    unlike( directory_entry('MDISK 0199 3390 DEVNO 0201 MR SENTDEVR SENTDEVW'),
        qr/SENTDEVR|SENTDEVW/, 'DEVNO disk passwords are masked' );
    unlike( directory_entry('READPASSWORD=SENTRP WRITEPASSWORD=SENTWP MULTIPASSWORD=SENTMP'),
        qr/SENTRP|SENTWP|SENTMP/, 'full keyword password names are masked' );
    unlike( directory_entry('APPCPASS LUA LUB USERX SENTAPPC'), qr/SENTAPPC/,
        'APPCPASS statement is masked' );
    is( directory_entry('MDISK 0401 FB-512 V-DISK 8000 MW SENTREAD'),
        'MDISK 0401 FB-512 V-DISK 8000 MW xxxxxxxx',
        'V-DISK read password is masked' );
    is( directory_entry('MDISK 0401 FB-512 V-DISK 8000 MW SENTR SENTW SENTM'),
        'MDISK 0401 FB-512 V-DISK 8000 MW xxxxxxxx',
        'all V-DISK passwords are masked' );
    is( directory_entry("MDISK 0199 3390 DEVNO 0201 MR\nNICDEF 0600 TYPE QDIO LAN SYSTEM VSW1"),
        "MDISK 0199 3390 DEVNO 0201 MR\nNICDEF 0600 TYPE QDIO LAN SYSTEM VSW1",
        'a passwordless record does not consume the next record' );
    unlike( directory_entry('* USER LNX1 SENTCOMU 512M 1G G'), qr/SENTCOMU/,
        'commented USER record is masked' );
    unlike( directory_entry('* IDENT LNX2 SENTCOMI 512M 1G G'), qr/SENTCOMI/,
        'commented IDENT record is masked' );
    unlike( directory_entry('* MDISK 0100 3390 0001 10016 EMC2C4 MR SENTCOMR SENTCOMW'),
        qr/SENTCOMR|SENTCOMW/, 'commented range MDISK record is masked' );
    unlike( directory_entry('* MDISK 0401 FB-512 V-DISK 8000 MW SENTCOMV'), qr/SENTCOMV/,
        'commented V-DISK record is masked' );
    unlike( directory_entry('*APPCPASS LUA LUB USERX SENTCOMA'), qr/SENTCOMA/,
        'commented APPCPASS record is masked' );
    unlike( directory_entry('** USER LNX1 SENTSTARS 512M 1G G'), qr/SENTSTARS/,
        'doubly commented USER record is masked' );
    unlike( directory_entry('COMMAND XAUTOLOG VSEVM PW SENTAUTO'), qr/SENTAUTO/,
        'COMMAND record is masked' );
    unlike( directory_entry('* COMMAND XAUTOLOG VSEVM PW SENTCAUTO'), qr/SENTCAUTO/,
        'commented COMMAND record is masked' );
    is( directory_entry("COMMAND XAUTOLOG VSEVM PW ,\nSENTCONT"),
        "COMMAND xxxxxxxx\nxxxxxxxx",
        'a continued COMMAND record is masked through its last record' );
    unlike( directory_entry("COMMAND DEFINE MDISK 0100 3390 1 100 EMC2C4 MR ,\nSENTCRPW SENTCWPW"),
        qr/SENTCRPW|SENTCWPW/, 'continued COMMAND operands are masked' );
    unlike( directory_entry("* COMMAND XAUTOLOG VSEVM PW ,\n* SENTCCONT"), qr/SENTCCONT/,
        'a commented continuation record is masked' );
    like( directory_entry("* COMMAND XAUTOLOG VSEVM PW ,\nNICDEF 0600 TYPE QDIO LAN SYSTEM VSW1"),
        qr/NICDEF 0600 TYPE QDIO LAN SYSTEM VSW1/,
        'a commented COMMAND record does not consume the record below it' );
    unlike( directory_entry("COMMAND XAUTOLOG VSEVM PW ,\n* a note\nSENTAFTERNOTE"),
        qr/SENTAFTERNOTE/, 'a comment record does not end the continuation' );
    unlike( directory_entry("COMMAND XAUTOLOG VSEVM PW ,\n* one\n* two\n\nSENTDEEP"),
        qr/SENTDEEP/, 'comment and blank records do not end the continuation' );
    unlike( directory_entry("COMMAND XAUTOLOG VSEVM PW ,\n* COMMAND note\nSENTCOMNOTE"),
        qr/SENTCOMNOTE/, 'a commented COMMAND record does not end the continuation' );
    my $sequenced = 'COMMAND XAUTOLOG VSEVM PW' . ( ' ' x 45 ) . ',' . '00000010';
    unlike( directory_entry("$sequenced\nSENTSEQPASS"), qr/SENTSEQPASS/,
        'a sequence numbered record continues the statement' );
    unlike( directory_entry('CMD XAUTOLOG VSEVM PW SENTCMD'), qr/SENTCMD/,
        'CMD record is masked' );
    unlike( directory_entry("CMD XAUTOLOG VSEVM PW ,\nSENTCMDCONT"), qr/SENTCMDCONT/,
        'a continued CMD record is masked through its last record' );
    unlike( directory_entry("COMMAND DEFINE ,\nMDISK 0100 3390 1 100 EMC2C4 MR ,\nSENTMIDMDISK"),
        qr/SENTMIDMDISK/,
        'a continuation record that reads as MDISK does not end the statement' );
    unlike( directory_entry("COMMAND DEFINE ,\nAPPCPASS LUA LUB USERX PW ,\nSENTMIDAPPC"),
        qr/SENTMIDAPPC/,
        'a continuation record that reads as APPCPASS does not end the statement' );
    unlike( directory_entry("COMMAND DEFINE ,\nUSER LNX1 SENTMIDLOGON 512M 1G G ,\nSENTMIDUSER"),
        qr/SENTMIDLOGON|SENTMIDUSER/,
        'a continuation record that reads as USER does not end the statement' );
    my $spaced = ( ' ' x 71 ) . '00000020';
    unlike( directory_entry("COMMAND XAUTOLOG VSEVM PW ,\n$spaced\nSENTSEQBLANK"),
        qr/SENTSEQBLANK/,
        'a sequence numbered blank record does not end the continuation' );
    my $trailing = 'COMMAND SET RUN ON' . ( ' ' x 53 ) . '0000001,';
    like( directory_entry("$trailing\nMDISK 0100 3390 0001 10016 EMC2C4 MR"),
        qr/^MDISK 0100 3390 0001 10016 EMC2C4 MR$/m,
        'a comma in the sequence number does not continue the statement' );
    like( directory_entry("COMMAND XAUTOLOG VSEVM PW ,\nSENTCONT\nNICDEF 0600 TYPE QDIO LAN SYSTEM VSW1"),
        qr/NICDEF 0600 TYPE QDIO LAN SYSTEM VSW1/,
        'the record after a continuation is preserved' );
    like( directory_entry("USER LNX1 SENTUSERPW 512M 1G G\nNICDEF 0600 TYPE QDIO LAN SYSTEM VSW1"),
        qr/NICDEF 0600 TYPE QDIO LAN SYSTEM VSW1/,
        'records beside credentials are preserved' );
};

subtest 'z/VM commands keep secrets out of logging boundaries' => sub {
    my (@syslog, @checked_commands, @callbacks);
    no warnings 'redefine';
    local *xCAT::zvmUtils::getNodeProps = sub {
        return { status => '', hcp => 'zhcp1', userid => 'linux1' };
    };
    local *xCAT::zvmCPUtils::getUserId = sub { return 'maint'; };
    local *xCAT::zvmUtils::printSyslog = sub { push @syslog, $_[1]; };
    local *xCAT::zvmUtils::printLn = sub { push @callbacks, $_[2]; };
    local *xCAT::zvmUtils::checkSSH_Rc = sub {
        push @checked_commands, $_[2];
        return ( 0, '' );
    };
    local *xCAT::zvmUtils::appendHostname = sub { return $_[2]; };
    local $::SUDOER = 'root';
    local $::SUDO   = 'sudo';
    local $::DIR    = '/opt/zhcp';

    @executed_commands = ();
    xCAT_plugin::zvm::changeVM(
        sub { }, 'node1',
        [ '--add3390', 'pool1', '0100', '100', 'MR', 'SENTREAD', 'SENTWRITE', 'SENTMULTI' ]
    );
    my $executed = join "\n", @executed_commands;
    my $observed = join "\n", @syslog, @checked_commands, @callbacks;
    like( $executed, qr/SENTREAD.*SENTWRITE.*SENTMULTI/,
        'disk creation receives the real passwords' );
    unlike( $observed, qr/SENTREAD|SENTWRITE|SENTMULTI/,
        'disk creation logs and errors omit the real passwords' );
    like( $observed, qr/-R xxxxxxxx -W xxxxxxxx -M xxxxxxxx/,
        'disk creation logging retains masked options' );

    @executed_commands = ();
    @syslog = ();
    xCAT_plugin::zvm::changeVM(
        sub { }, 'node1',
        [ '--addpagespool', '0101', 'PAGE01', 'PAGE', 'SYSTEM', 'TYPE', 'OWNER', 'NUMBER', 'SENTPAGEPASS' ]
    );
    $executed = join "\n", @executed_commands;
    $observed = join "\n", @syslog;
    like( $executed, qr/parm_disk_password=SENTPAGEPASS/,
        'page volume creation receives the real password' );
    unlike( $observed, qr/SENTPAGEPASS/,
        'page volume logging omits the real password' );
    like( $observed, qr/parm_disk_password=xxxxxxxx/,
        'page volume logging retains the masked operand' );

    @executed_commands = ();
    @syslog = ();
    xCAT_plugin::zvm::changeVM( sub { }, 'node1', [ '--setpassword', 'SENTIMAGEPASS' ] );
    $executed = join "\n", @executed_commands;
    $observed = join "\n", @syslog;
    like( $executed, qr/Image_Password_Set_DM.*SENTIMAGEPASS/,
        'password update receives the real password' );
    unlike( $observed, qr/SENTIMAGEPASS/,
        'password update logging omits the real password' );
    like( $observed, qr/Image_Password_Set_DM.*xxxxxxxx/,
        'password update logging retains the mask' );
};

subtest 'CIM verbose request masks authorization' => sub {
    my $request = HTTP::Request->new( GET => 'http://example.invalid/' );
    $request->header( Authorization => 'Basic SENTCIMSECRET' );
    my @callbacks;
    no warnings 'redefine';
    local *LWP::UserAgent::request = sub {
        return { _rc => 200, _msg => 'OK', _content => 'response' };
    };
    my $result = xCAT::CIMUtils::send_http_request(
        {
            protocol => 'http',
            verbose  => 1,
            callback => sub { push @callbacks, $_[0] },
        },
        $request
    );
    is( $result->{rc}, 0, 'stubbed CIM request succeeds' );
    my $dump = join "\n", map { @{ $_->{data} } } @callbacks;
    unlike( $dump, qr/SENTCIMSECRET/, 'verbose callback omits the authorization value' );
    like( $dump, qr/^Authorization: xxxxxxxx$/m,
        'verbose callback retains a masked authorization header' );
};

subtest 'BMC missing-attribute reports expose only password state' => sub {
    foreach my $case (
        [ 'SENTBMCPASS', 'set' ],
        [ '0',           'set' ],
        [ '',            'missing' ],
      ) {
        my ( $password, $state ) = @{$case};
        my (@logs, @callbacks);
        no warnings 'redefine';
        local *xCAT_plugin::bmcconfig::ok_with_node = sub { return 1; };
        local *xCAT_plugin::bmcconfig::net_parms = sub { return ( undef, '255.255.255.0', '192.0.2.1' ); };
        local *xCAT::Table::new = sub { return bless {}, 'XCAT::Test::BmcTable'; };
        local *xCAT::PasswordUtils::getIPMIAuth = sub {
            return { node1 => { username => 'ADMIN', password => $password } };
        };
        local *xCAT::MsgUtils::message = sub { push @logs, $_[2]; };
        local %::XCATSITEVALS = ( genpasswords => '0' );

        xCAT_plugin::bmcconfig::process_request(
            {
                _xcat_clienthost => ['node1'],
                command          => ['getbmcconfig'],
                isopenbmc        => [0],
            },
            sub { push @callbacks, $_[0] }
        );

        my $observed = join "\n", @logs,
          map { ref $_->{error} ? @{ $_->{error} } : () } @callbacks;
        unlike( $observed, qr/SENTBMCPASS/, "$state password report omits the value" );
        like( $observed, qr/Pass=\Q$state\E/, "$state password report names its state" );
    }
};

subtest 'PPC verbose messages preserve credentials but mask passwords' => sub {
    my @logs;
    my %targets = (
        hmc => { hmc1 => { name => 'hmc1', type => 'hmc' } },
        fsp => { fsp1 => { name => 'fsp1', type => 'fsp' } },
        bpa => { bpa1 => { name => 'bpa1', type => 'bpa' } },
    );
    no warnings 'redefine';
    local *xCAT::PPCdb::credentials = sub { return ( 'ppc-user', 'SENTPPCPASS' ); };
    local *xCAT::MsgUtils::verbose_message = sub { push @logs, $_[2]; };

    xCAT::PPCcfg::get_rsp_dev( {}, \%targets );

    is( $targets{hmc}{hmc1}{password}, 'SENTPPCPASS', 'HMC keeps the real password' );
    is( $targets{fsp}{fsp1}{password}, 'SENTPPCPASS', 'FSP keeps the real password' );
    is( $targets{bpa}{bpa1}{password}, 'SENTPPCPASS', 'BPA keeps the real password' );
    my $observed = join "\n", @logs;
    unlike( $observed, qr/SENTPPCPASS/, 'verbose messages omit the real password' );
    is( scalar grep( /ppc-user xxxxxxxx/, @logs ), 3,
        'each credential report retains the user and password mask' );
};

subtest 'energy verbose message masks only the transport log' => sub {
    pipe( my $reader, my $writer ) or die "pipe: $!";
    my $pid = fork();
    die "fork: $!" unless defined $pid;
    if ( $pid == 0 ) {
        close $reader;
        no warnings 'redefine';
        local *xCAT::Table::new = sub {
            return bless { name => $_[1] }, 'XCAT::Test::EnergyTable';
        };
        local *xCAT::Utils::xfork = sub { return 0; };
        local *xCAT::NetworkUtils::getipaddr = sub { return '192.0.2.10'; };
        local *xCAT::MsgUtils::message = sub {
            my $payload = $_[2];
            print {$writer} "log=" . join( '', @{ $payload->{data} } ) . "\n";
        };
        local *xCAT_plugin::energy::run_cim = sub {
            my $args = $_[2];
            print {$writer} "transport=$args->{password}\n";
            return 0;
        };
        xCAT_plugin::energy::process_request(
            { node => ['node1'], arg => [], verbose => 1 },
            sub { },
            undef
        );
        _exit(1);
    }
    close $writer;
    my $observed = do { local $/; <$reader> };
    close $reader;
    waitpid( $pid, 0 );

    is( $? >> 8, 0, 'energy request child exits cleanly' );
    like( $observed, qr/^transport=SENTENERGYPASS$/m,
        'CIM transport receives the real password' );
    unlike( $observed, qr/^log=.*SENTENERGYPASS/m,
        'verbose energy message omits the real password' );
    like( $observed, qr/^log=.*password \[xxxxxxxx\]$/m,
        'verbose energy message retains a masked password field' );
};

done_testing();
