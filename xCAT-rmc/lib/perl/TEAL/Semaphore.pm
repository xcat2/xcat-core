package TEAL::Semaphore;

use strict;
use warnings;
require IPC::SysV;

sub new {
    my $class = shift;
    my $self = {};
    my $key = IPC::SysV::ftok("/var/log/teal",0x646c6100);
    $self->{ID} = semget($key,1,0);
    bless $self,$class;
    return $self;
}

sub post {
    my $self = shift;
    my $op = pack("s!3",0,1,0);
    semop $self->{ID},$op || die "failed to post"
}

1;
