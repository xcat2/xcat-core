# IBM(c) 2010 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_plugin::activedirectory;
BEGIN
{
      $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
my $callback;
use lib "$::XCATROOT/lib/perl";
use Getopt::Long;
sub handled_commands { 
    return {
        addclusteruser => 'site:directoryprovider',
        addclouduser => 'site:directoryprovider',
    };
}
sub process_request {
    my $request = shift;
    my $command = $request->{command}->[0];
    $callback = shift;
    my $doreq = shift;
    use Data::Dumper;
    if ($command =~ /add.*user/) { #user management command, adding
        my $homedir;
        my $fullname;
        my $gid;
        my $uid;
        @ARGV=@{$request->{arg}};
        Getopt::Long::Configure("bundling");
        Getopt::Long::Configure("pass_through");

         if (!GetOptions(
            'd=s' => \$homedir,
            'c=s' => \$fullname,
            'g=s' => \$gid,
            'u=s' => \$uid)) {
             die "Not possible";
         }
         my $username = shift @ARGV;
         my %args ( username => $username );
         if ($fullname) { $args{fullname} = $fullname };
         sendmsg("Full name: ".$fullname);
         sendmsg(join(" ",@ARGV));
    }



        

}

sub sendmsg {
    my $text = shift;
    my $node = shift;
    my $descr;
    my $rc;
    if (ref $text eq 'HASH') {
        die "not right now";
    } elsif (ref $text eq 'ARRAY') {
        $rc = $text->[0];
        $text = $text->[1];
    }
    if ($text =~ /:/) {
        ($descr,$text) = split /:/,$text,2;
    }
    $text =~ s/^ *//;
    $text =~ s/ *$//;
    my $msg;
    my $curptr;
    if ($node) {
        $msg->{node}=[{name => [$node]}];
        $curptr=$msg->{node}->[0];
    } else {
        $msg = {};
        $curptr = $msg;
    }
    if ($rc) {
        $curptr->{errorcode}=[$rc];
        $curptr->{error}=[$text];
        $curptr=$curptr->{error}->[0];
    } else {
        $curptr->{data}=[{contents=>[$text]}];
        $curptr=$curptr->{data}->[0];
        if ($descr) { $curptr->{desc}=[$descr]; }
    }
#        print $outfd freeze([$msg]);
#        print $outfd "\nENDOFFREEZE6sK4ci\n";
#        yield;
#        waitforack($outfd);
    $callback->($msg);
}
1;
