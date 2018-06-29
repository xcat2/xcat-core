# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
# The last module to deal with hardware discovery request, write information that which module can deal with this request or no module can deal with it at all
package xCAT_plugin::makearpfile;

BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";
use xCAT::NetworkUtils;


sub handled_commands {
    return {
        makearpfile => 'makearpfile',
    };
}

sub process_request {
    my $req   = shift;
    my $cb    = shift;
    my $doreq = shift;
    my $file_rootdir = "/install/";
    my @arpentries = ();
    my @entries = xCAT::TableUtils->get_site_attribute("arpfileroot");
    if (defined($entries[0])) {
        $file_rootdir = $entries[0];
    }
    if (! -d $file_rootdir . "/arpinfo/") {
        mkdir($file_rootdir . "/arpinfo");
    }
    my $arpfilename = $file_rootdir ."/arpinfo/ibinfo.txt";
    my $nodelisttab = xCAT::Table->new('nodelist');
    if (!$nodelisttab) {
        my $rsp = {};
        $rsp->{error}->[0] = "The discovery request can not be processed".$error_msg;
        $cb->($rsp);
        return;
    }
    my @entries = $nodelisttab->getAllNodeAttribs(['node', 'appstatus']);
    foreach (@entries) {
        my $node = $_->{node};
        my $appstatus = $_->{appstatus};
        if (!defined($appstatus) or ($appstatus !~ /ib\d+=/)) {
            my $rsp = {};
            $rsp->{data} = ["$node: No \"appstatus\" attributes available"];
            xCAT::MsgUtils->message("W", $rsp, $cb);
            next;
        }
        my @ibinfo = split(/,/, $appstatus);
        foreach my $ib (@ibinfo) {
            if ($ib =~ /(ib\d+)=([^;]+);([\d\.]+)/) {
                my $arpentry = "? ($3) at $2 [infiniband] on $1";
                push @arpentries, $arpentry;
            }
        }
    }
    print("write file===\n");
    my $fd;
    open($fd, ">", $arpfilename);
    foreach (@arpentries) {
        print $fd "$_\n";
    }
    close($fd);
}
1;
