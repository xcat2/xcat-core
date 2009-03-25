# IBM(c) 2009 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_monitoring::bootttmon;
1;

#--------------------------------------------------------------------------------
=head3   processTableChanges
  This subroutine gets called when changes are made to the boottarget or nodetype tables
    Arguments:
      action - table action. It can be d for rows deleted, a for rows added
                    or u for rows updated.
      tablename - string. The name of the DB table whose data has been changed.
      old_data - an array reference of the old row data that has been changed.
           The first element is an array reference that contains the column names.
           The rest of the elelments are also array references each contains
           attribute values of a row.
           It is set when the action is u or d.
      new_data - a hash refernce of new row data; only changed values are present
           in the hash.  It is keyed by column names.
           It is set when the action is u or a.
    Returns:
      0
    Comment:
       To use, 
        1. run regnotif bootttmon.pm boottarget,nodetype -o u
        2. Then change the boottarget or nodetype tables (add node, remove node, or change status column).
        3. Watch /var/log/bootttmon for output and updates to pxelinux.cfg files.
=cut
#-------------------------------------------------------------------------------
sub processTableChanges {
  my $action=shift;
  if ($action =~ /xCAT_monitoring::bootttmon/){
    $action=shift;
  }

  my $tablename=shift;
  my $old_data=shift;
  my $new_data=shift;

  my @profiles=();
  my $newprofile;
  open(FILE, ">>/var/log/bootttmon") or dir ("cannot open the file\n");
  ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
  printf FILE "\n-----------%2d-%02d-%04d %02d:%02d:%02d-----------\n", $mon+1,$mday,$year+1900,$hour,$min,$sec;  
  if ($new_data) {
    push(@profiles, $tablename);
    push(@profiles, $action);
    if ($tablename eq "boottarget") {
      $newprofile=$new_data->{bprofile};
      push(@profiles, $new_data->{bprofile});
      push(@profiles, $new_data->{kernel});
      push(@profiles, $new_data->{initrd});
      push(@profiles, $new_data->{kcmdline});
    }
    else {
      $newprofile=$new_data->{profile};
      push(@profiles, $new_data->{node});
      push(@profiles, $new_data->{os});
      push(@profiles, $new_data->{arch});
      push(@profiles, $new_data->{profile});
      push(@profiles, $new_data->{nodetype});
    }
    push(@profiles, $new_data->{comments});
    push(@profiles, $new_data->{disable});
    $news=join(',', @profiles);
    print (FILE "Input is: $news\n"); 
  }
  if (($action eq "u") and ($newprofile ne '')) {
    my @nodes = ();
    if ($tablename eq "boottarget") { #have to look at all nodes
      @nodes = `nodels '/.*' nodetype.profile==$newprofile`;
    }
    else { #only look at those nodes directly effected
      @nodes = `nodels $new_data->{node}`;
    }
    chomp(@nodes);
    for (my $j=0; $j<@nodes; $j++) {
      my $node=@nodes[$j];
      my $state=`nodeset $node stat`;
      my @states=split(/:/,$state);
      $state=@states[1];
      my $out = `nodeset $node $state`;
      print (FILE "pxelinux.cfg file update for $out");
    }
  }
  close(FILE);
  return 0;
}
