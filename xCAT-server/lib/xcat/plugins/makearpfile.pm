# IBM(c) 2018 EPL license http://www.eclipse.org/legal/epl-v10.html
# The file to genarate file for arp records which can be applied by arp directly 
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
    my $installdir = "/install";
    my $arp_file_dir = "/arpinfo";
    my $arp_file_name = "arpdata.csv";
    my @arpentries = ();
    my @entries = xCAT::TableUtils->get_site_attribute("installdir");
    if (defined($entries[0])) {
        $installdir = $entries[0];
    }
    @entries = xCAT::TableUtils->get_site_attribute("arp_file_dir"); 
    if (defined($entries[0])) {
        $arp_file_dir = $entries[0];
    }
    @entries = xCAT::TableUtils->get_site_attribute("arp_file_name"); 
    if (defined($entries[0])) {
        $arp_file_name = $entries[0];
    }
    if (! -d  "$installdir/$arp_file_dir") {
        mkdir("$installdir/$arp_file_dir");
    }
    my $arpfilename = "$installdir/$arp_file_dir/$arp_file_name";
    my $nodelisttab = xCAT::Table->new('nodelist');
    if (!$nodelisttab) {
        my $rsp = {};
        $rsp->{error}->[0] = "Can not open 'nodelist' table";
        $cb->($rsp);
        return;
    }
    my @entries = $nodelisttab->getAllNodeAttribs(['node', 'appstatus']);
    foreach (@entries) {
        my $node = $_->{node};
        my $appstatus = $_->{appstatus};
        if (!defined($appstatus) or ($appstatus !~ /ib\d+=/)) {
            xCAT::MsgUtils->message("S", "xcat.makearpfile: $node: No \"appstatus\" attributes available");
            next;
        }
        my @ibinfo = split(/,/, $appstatus);
        foreach my $ib (@ibinfo) {
            if ($ib =~ m#(ib\d+)=([^/]+)/([\d\.]+)/([\d\.]+)#) {
                my $arpentry = "$2,$3,$4,$node";
                push @arpentries, $arpentry;
            }
        }
    }
    xCAT::MsgUtils->message("I", { data => ["Update arp information in file $arpfilename"] }, $cb);
    my $fd;
    open($fd, ">", $arpfilename);
    foreach (@arpentries) {
        print $fd "$_\n";
    }
    close($fd);
}
1;
