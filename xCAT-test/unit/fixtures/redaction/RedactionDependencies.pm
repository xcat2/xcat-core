package RedactionDependencies;

use strict;
use warnings;

BEGIN {
    for my $module (qw(xCAT::Table xCAT::TableUtils xCAT::MsgUtils
        xCAT::NodeRange xCAT::Utils xCAT::ExtTab)) {
        (my $file = "$module.pm") =~ s{::}{/}g;
        $INC{$file} = __FILE__;
    }
}

package xCAT::Table;

our $rule = 'allow';

sub new {
    my ($class, $name) = @_;
    die "Unexpected table: $name" unless $name eq 'policy';
    return bless {}, $class;
}

sub getAllEntries {
    return [{priority => 1, rule => $rule}];
}

sub close { return; }
sub shut_dbworker { die 'Unexpected database worker shutdown'; }
sub init_dbworker { die 'Unexpected database worker startup'; }

1;
