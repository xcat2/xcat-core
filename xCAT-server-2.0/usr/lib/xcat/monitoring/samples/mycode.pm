# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_monitoring::mycode;
1;

# This subroutine get called when new nodes are added into the cluster
# or nodes are removed from the cluster.
#
sub processTableChanges {
  my $action=shift;
  if ($action =~ /xCAT_monitoring::mycode/){
    $action=shift;
  }
  my $tablename=shift;
  my $old_data=shift;
  my $new_data=shift;

  my @nodenames=();
  if ($action eq "a") { #nodes added in the cluster
    if ($new_data) {
      push(@nodenames, $new_data->{node});
      $noderange=join(',', @nodenames);
      open(FILE, ">>/var/log/mycode.log") or dir ("cannot open the file\n");
      print (FILE "new nodes in the cluster are: $noderange\n"); 
      close(FILE);
    }
  }
  elsif ($action eq "d") { #nodes removed from the cluster
    #find out the index of "node" column
    if ($old_data->[0]) {
      $colnames=$old_data->[0];
      my $i;
      for ($i=0; $i<@$colnames; ++$i) {
        if ($colnames->[$i] eq "node") {last;}
      }

      for (my $j=1; $j<@$old_data; ++$j) {
        push(@nodenames, $old_data->[$j]->[$i]);
      }

      if (@nodenames > 0) {
         $noderange=join(',', @nodenames);
         open(FILE, ">>/var/log/mycode.log") or dir ("cannot open the file\n");
         print (FILE "nodes leaving the cluster are: $noderange\n");
         close(FILE);
      }
    }
  }
  return 0;
}
