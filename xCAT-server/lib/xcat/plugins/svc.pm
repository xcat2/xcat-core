# IBM(c) 2013 EPL license http://www.eclipse.org/legal/epl-v10.html
#----------------------------------------------------------------------

# Plugin to interface with IBM SVC managed storage
#
use strict;

package xCAT_plugin::svc;

use xCAT::SvrUtils qw/sendmsg/;
use xCAT::SSHInteract;
use Getopt::Long;
Getopt::Long::Configure("bundling");
Getopt::Long::Configure("pass_through");

my $callback;
my $dorequest;
my %controllersessions;

sub handled_commands {
    return {
        mkstorage => "storage:type",
        rmstorage => "storage:type",
    }
}

sub mkstorage {
    my $request = shift;
    my $ctx = shift;
    my @nodes = @{$request->{node}};
    my $shared = 0;
    my $controller;
    my $pool;
    my $size;
    my $boot = 0;
    unless (ref $request->{arg}) {
        die "TODO: usage";
    }
    @ARGV = @{$request->{arg}};
    unless (GetOptions(
        'shared' => \$shared,
        'controller=s' => \$controller,
        'boot' => \$boot,
        'size=f' => \$size,
        'pool=s' => \$pool,
        )) {
        foreach (@nodes) {
            sendmsg([1,"Error parsing arguments"],$callback,$_);
        }
    }
    if ($shared and $boot) {
        foreach (@nodes) {
            sendmsg([1,"Storage can not be both shared and boot"],$callback,$_);
        }
    }
    my $storagetab = xCAT::Table->new('storage');
    my $storents = $storagetab->getNodesAttribs(\@nodes,
        [qw/controller storagepool size/]);
    if ($shared) {
        unless ($size) {
            foreach (@nodes) {
                sendmsg([1,
                     "Size for shared volumes must be specified as an argument"
                    ], $callback,$_);
            }
        }
        unless ($pool) {
            $pool = assure_identical_table_values(\@nodes, $storents, 'storagepool');
        }
        unless ($controller) {
            $controller = assure_identical_table_values(\@nodes, $storents, 'controller');
        }
        unless (defined $pool and defined $controller) {
            return;
        }
        my $lun = create_lun(controller=>$controller, size=>$size, pool=>$pool);
        my $wwns = get_wwns(@nodes);
    } else {
        foreach my $node (@nodes) {
            mkstorage_single(node=>$node, size=>$size, pool=>$pool,
                             boot=>$boot, controller=>$controller,
                             cfg=>$storents->{$node});
        }
    }
}

sub got_wwns {
    use Data::Dumper;
    print Dumper(@_);
}

sub get_wwns {
    my @nodes = @_;
    my %request = (
        node => \@nodes,
        command => [ 'rinv' ],
        arg => [ 'wwn' ]
    );
    use Data::Dumper;
    print Dumper(\%request);
    $dorequest->(\%request, \&got_wwns);
}

my $globaluser;
my $globalpass;
sub get_svc_creds {
    my $controller = shift;
    if ($globaluser and $globalpass) {
        return { 'user' => $globaluser, 'pass' => $globalpass }
    }
    my $passtab = xCAT::Table->new('passwd',-create=>0);
    my $passent = $passtab->getAttribs({key=>'svc'}, qw/username password/);
    $globaluser = $passent->{username};
    $globalpass = $passent->{password};
   return { 'user' => $globaluser, 'pass' => $globalpass }
}

sub establish_session {
    my %args = @_;
    my $controller = $args{controller};
    if ($controllersessions{$controller}) {
        return $controllersessions{$controller};
    }
    #need to establish a new session
    my $cred = get_svc_creds($controller);
    my $sess = new xCAT::SSHInteract(-username=>$cred->{user},
                                     -password=>$cred->{pass},
                                     -host=>$controller,
                                     -output_record_separator=>"\r",
                                     #Errmode=>"return",
                                     #Input_Log=>"/tmp/svcdbgl",
                                     Prompt=>'/>$/');
    unless ($sess and $sess->atprompt) { die "TODO: cleanly handle bad login" }
    $controllersessions{$controller} = $sess;
    return $sess;
}

sub create_lun {
    my %args = @_;
    my $session = establish_session(%args);
    my $pool = $args{pool};
    my $size = $args{size};
    my @result = $session->cmd("mkvdisk -iogrp io_grp0 -mdiskgrp $pool -size $size -unit gb");
    if ($result[0] =~ m/Virtual Disk, id \[(\d*)\], successfully created/) {
        my $diskid = $1;
        my $name;
        my $wwn;
        @result = $session->cmd("lsvdisk $diskid");
        foreach (@result) {
            chomp;
            if (/^name (.*)\z/) {
                $name = $1;
            } elsif (/^vdisk_UID (.*)\z/) {
                $wwn = $1;
            }
        }
        return { name => $name, id => $diskid, wwn => $wwn };
    }
}

sub assure_identical_table_values {
    my $nodes = shift;
    my $storents = shift;
    my $attribute = shift;
    my $lastval;
    foreach my $node (@$nodes) {
        my $sent = $storents->{$node}->[0];
        unless ($sent) {
            sendmsg([1, "No $attribute in arguments or table"],
                $callback, $node);
            return undef;
        }
        my $currval = $storents->{$node}->{$attribute};
        unless ($currval) {
            sendmsg([1, "No $attribute in arguments or table"],
                $callback, $node);
            return undef;
        }
        if ($lastval and $currval ne $lastval) {
            sendmsg([1,
                "$attribute mismatch in table config, try specifying as argument"],
                $callback, $node);
            return undef;
        }
    }
    return $lastval;
}

sub mkstorage_single {
    my %args = @_;
}

sub process_request {
    my $request = shift;
    $callback = shift;
    $dorequest = shift;
    if ($request->{command}->[0] eq 'mkstorage') {
        mkstorage($request);
    }
    foreach (values %controllersessions) {
        $_->close();
    }
}

1;
