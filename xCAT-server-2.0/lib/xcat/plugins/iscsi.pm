package xCAT_plugin::iscsi;
use xCAT::Table;
use Socket;
use File::Path;
use Getopt::Long;
Getopt::Long::Configure("bundling");
Getopt::Long::Configure("pass_through");


sub handled_commands {
   return {
      "setupiscsidev" => "iscsi",
   };
}
sub get_tid {
#generate a unique tid given a node for tgtadm to use
   my $node = shift;
   my $tid = unpack("N",inet_aton($node));
   $tid = $tid & ((2**31)-1);
   return $tid;
}

sub preprocess_request {
   my $request = shift;
   my $callback = shift;
   my @requests = ();
   my %iscsiserverhash;
   if ($req->{_xcatdest}) { return [$req]; }
   my $iscsitab = xCAT::Table->new('iscsi');
   foreach my $node (@{$request->{node}}) {
      my $tent = $iscsitab->getNodeAttribs($node,['server']);
      if ($tent and $tent->{server}) {
         $iscsiserverhash{$tent->{server}}->{$node} = 1;
      } else {
         $callback->({error=>["No iscsi.server for $node, aborting request"]});
         return [];
      }
   }
   foreach my $iscsis (keys %iscsiserverhash) {
      my $reqcopy = {%$request};
      $reqcopy->{'_xcatdest'} = $iscsis;
      $reqcopy->{node} = [ keys %{$iscsiserverhash{$iscsis}} ];
      push @requests,$reqcopy;
   }
   return \@requests;
}

sub process_request {
   my $request = shift;
   my $callback = shift;
   unless (-x "/usr/sbin/tgtadm") {
      $callback->({error=>"/usr/sbin/tgtadm does not exist, iSCSI plugin currently requires it, please install scsi-target-utils package under CentOS, RHEL, or Fedora.  SLES support is not yet implemented",errorcode=>[1]});
      return;
   }
   @ARGV=@{$request->{arg}};
   my $lunsize = 2048;
   GetOptions(
      "size|s=i" => \$lunsize,
   );
   my $iscsitab = xCAT::Table->new('iscsi'); 
   my @nodes = @{$request->{node}};
   my $sitetab = xCAT::Table->new('site');
   unless ($sitetab) {
      $callback->({error=>"Fatal error opening site table",errorcode=>[1]});
      return;
   }
   my $domain;
   (my $ipent) = $sitetab->getAttribs({key=>'domain'},'value');
   if ($ipent and $ipent->{value}) { $domain = $ipent->{value}; }
   ($ipent) = $sitetab->getAttribs({key=>'iscsidir'},'value');
   my $iscsiprefix;
   if ($ipent and $ipent->{value}) {
      $iscsiprefix = $ipent->{value};
   }
   foreach my $node (@nodes) {
      my $fileloc;
      my $iscsient = $iscsitab->getNodeAttribs($node,['file']);
      if ($iscsient and $iscsient->{file}) {
         $fileloc = $iscsient->{file};
      } else {
         unless ($iscsiprefix) {
            $callback->({error=>["$node: Unable to identify file to back iSCSI LUN, no iscsidir in site table nor iscsi.file entry for node"],errorcode=>[1]});
            next;
         }
         unless (-d $iscsiprefix) {
            mkpath $iscsiprefix;
         }
         $fileloc = "$iscsiprefix/$node";
         $iscsitab->setNodeAttribs($node,{file=>$fileloc});
      }
      unless (-f $fileloc) {
         $callback->({data=>["Creating $fileloc ($lunsize MB)"]});
         my $rc = system("dd if=/dev/zero of=$fileloc bs=1M count=$lunsize");
         if ($rc) {
            $callback->({error=>["$node: dd process exited with return code $rc"],errorcode=>[1]});
            next;
         }
      }
      my $targname;
      $iscsient = $iscsitab->getNodeAttribs($node,['target']);
      if ($iscsient and $iscsient->{target}) {
         $targname = $iscsient->{target};
      }
      unless ($targname) {
         my @date = localtime;
         my $year = 1900+$date[5];
         my $month = $date[4];
         $targname = "iqn.$year-$month.$domain:$node";
         $iscsitab->setNodeAttribs($node,{target=>$targname});
      }
      system("tgtadm --mode target --op delete --tid ".get_tid($node)." -T $targname");
      my $rc = system("tgtadm --mode target --op new --tid ".get_tid($node)." -T $targname");
      if ($rc) {
         $callback->({error=>["$node: tgtadm --mode target --op new --tid ".get_tid($node)." -T $targname returned $rc"],errorcode=>[$rc]});
         next;
      }
      $rc = system("tgtadm --mode logicalunit --op new --tid ".get_tid($node)." --lun 1 --backing-store $fileloc --device-type disk");
      if ($rc) {
         $callback->({error=>["$node: tgtadm returned $rc"],errorcode=>[$rc]});
         next;
      }
      $rc = system("tgtadm --mode target --op bind --tid ".get_tid($node)." -I ".inet_ntoa(inet_aton($node)));
      if ($rc) {
         $callback->({data=>"tgtadm --mode target --op bind --tid ".get_tid($node)."-I ".inet_ntoa(inet_aton($node))});
         $callback->({error=>["$node: Error binding $node to iSCSI target"],errorcode=>[$rc]});
      }
   }
}

1;
