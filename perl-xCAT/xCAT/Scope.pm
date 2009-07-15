package xCAT::Scope;
use xCAT::Utils;
use xCAT::Table;
sub get_broadcast_scope {
   my $req = shift;
   if ($req =~ /xCAT::Scope/) {
      $req = shift;
   }
   $callback = shift;
   if ($req->{_xcatpreprocessed}->[0] == 1) { return [$req]; }
    #Exit if the packet has been preprocessed in its history
   my @requests = ({%$req}); #Start with a straight copy to reflect local instance
   foreach (xCAT::Utils->getSNList()) {
         if (xCAT::Utils->thishostisnot($_)) {
            my $reqcopy = {%$req};
            $reqcopy->{'_xcatdest'} = $_;
            $reqcopy->{_xcatpreprocessed}->[0] = 1; 
            push @requests,$reqcopy;
         }
   }
   return \@requests;
   #my $sitetab = xCAT::Table->new('site');
   #(my $ent) = $sitetab->getAttribs({key=>'xcatservers'},'value');
   #$sitetab->close;
   #if ($ent and $ent->{value}) {
   #   foreach (split /,/,$ent->{value}) {
   #      if (xCAT::Utils->thishostisnot($_)) {
   #         my $reqcopy = {%$req};
   #         $reqcopy->{'_xcatdest'} = $_;
   #         push @requests,$reqcopy;
   #      }
   #   }
   #}
   #return \@requests;
}

1;
