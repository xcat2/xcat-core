# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------

=head1
  xCAT plugin package to handle xCATWorld

   Supported command:
         xCATWorld->xCATWorld

=cut

#-------------------------------------------------------
package xCAT_plugin::osdistro;
use Sys::Hostname;
use xCAT::Table;

use xCAT::Utils;

use xCAT::MsgUtils;
use Getopt::Long;
my $SUB_REQ_L;
1;



#-------------------------------------------------------

=head3  handled_commands

Return list of commands handled by this plugin

=cut

#-------------------------------------------------------

sub handled_commands
{
    return {
	 	mkosdistro => "osdistro",
	 	lsosdistro => "osdistro",
	 	rmosdistro => "osdistro",
	   };
}

#-------------------------------------------------------

=head3  preprocess_request

  Check and setup for hierarchy 


sub preprocess_request
{
    my $req = shift;
    my $callback  = shift;
    my %sn;
    #if already preprocessed, go straight to request
    if (($req->{_xcatpreprocessed}) and ($req->{_xcatpreprocessed}->[0] == 1) ) { return [$req]; }
    my $nodes    = $req->{node};
    my $service  = "xcat";

    # find service nodes for requested nodes
    # build an individual request for each service node
    if ($nodes) {
     $sn = xCAT::Utils->get_ServiceNode($nodes, $service, "MN");

      # build each request for each service node

      foreach my $snkey (keys %$sn)
      {
	my $n=$sn->{$snkey};
	print "snkey=$snkey, nodes=@$n\n";
            my $reqcopy = {%$req};
            $reqcopy->{node} = $sn->{$snkey};
            $reqcopy->{'_xcatdest'} = $snkey;
            $reqcopy->{_xcatpreprocessed}->[0] = 1;
            push @requests, $reqcopy;

      }
      return \@requests;
    } else { # input error
       my %rsp;
       $rsp->{data}->[0] = "Input noderange missing. Useage: xCATWorld <noderange> \n";
      xCAT::MsgUtils->message("I", $rsp, $callback, 0);
      return 1;
    }
}
=cut

#-------------------------------------------------------

#-------------------------------------------------------

=head3  process_request

  Process the command

=cut

#-------------------------------------------------------
sub process_request
{

    my $request  = shift;
    my $callback = shift;

    $SUB_REQ_L = shift;    
    my $command  = $request->{command}->[0];
    my $args     = $request->{arg};
    my $envs     = $request->{env};
    my %rsp;
    # do your processing here
    # return info

    if($command eq "mkosdistro")
    {
      &mkosdistro($request,$callback);  
    }elsif($command eq "lsosdistro")
    {
      &lsosdistro($request,$callback);  
    }elsif($command eq "rmosdistro")
    {
      &rmosdistro($request,$callback);  
    }

    return;

}

sub parseosver
{
  my $osver=shift;

  if($osver =~ (/(\D+)(\d*)\.*(\d*)/))
  {
        return ($1,$2,$3);
  }
  
  return ();
}


#-------------------------------------------------------

=head3  mkosdistro

  add/set osdistro entry

=cut

#-------------------------------------------------------
sub mkosdistro
{

    my $request  = shift;
    my $callback = shift;
    
    my %keyhash=();
    my %updates=();
    my $distname=undef;
    my $osver=undef;
    my $arch=undef;
    my $help=undef;
    my $force=undef;
    my $path=undef;

    if ($request->{arg}) {
  	     	@ARGV = @{$request->{arg}};
    }
  
    GetOptions(
    		'n|name=s' => \$distname,
                'o|osver=s' =>\$osver,
    		'a|arch=s' => \$arch,
    		'h|help' => \$help,
		'f|force' => \$force,
	    	'p|path=s' => \$path
 	);

        if ($help) {
     		 $callback->({info=>"mkosdistro [{-n|--name}=osdistroname] [{-o|--osver}=osver] [{-a|--arch}=architecture] [{-p|--path}=ospkgpath]  [-f|--force]",errorcode=>[0]});
     		 return;
  	}


  	unless ($distname) {
     		$callback->({error=>"mkosdistro: osdistroname must be specified!",errorcode=>[1]});
     		return;
  	}

   	$keyhash{osdistroname}    = $distname;

   	if($arch){
		$updates{arch}    = $arch;
	}

	if($osver){
   		($updates{basename},$updates{majorversion},$updates{minorversion}) = &parseosver($osver);
   		$updates{type}    ="linux";
	}

	
   	my $tab = xCAT::Table->new('osdistro',-create=>1);

   	unless($tab)
	{
        	$callback->({error=>"mkosdistro: failed to open table 'osdistro'!",errorcode=>[1]});
        	return;
	}
	
	if($path)
	{
		$path =~ s/\/+$//;
        	(my $ref) = $tab->getAttribs(\%keyhash, 'dirpaths');
        	if ($ref and $ref->{dirpaths} )
        	{

	    		unless($ref->{dirpaths} =~ /^($path)\/*,|,($path)\/*,|,($path)\/*$|^($path)\/*$/)
			{
				$updates{dirpaths}=$ref->{dirpaths}.','.$path;	
			}			   
				
        	}else
		{
			$updates{dirpaths}   = $path;
		}
	}


	if(%updates)
   	{
		$tab->setAttribs( \%keyhash,\%updates );
   		$tab->commit;
	}
        $tab->close; 

        $callback->({info=>"mkosdistro: $distname  success",errorcode=>[0]});
        return;
}


#-------------------------------------------------------

=head3  rmosdistro

  remove osdistro entry

=cut

#-------------------------------------------------------

sub getOSdistroref
{	
	my $osimagetab=shift;
	my $osdistroname=shift;

	my $ret=();
	

   	unless($osimagetab)
	{
		return undef;
	}

	my @clause=();
	
	push(@clause,"osdistroname==".$osdistroname);
	
	my @result=$osimagetab->getAllAttribsWhere(\@clause,'imagename');
	
	if(scalar @result)
	{
		foreach(@result)
		{
			$ret=$ret.$_->{'imagename'}.",";
		}
	}
	else
	{
		return undef;
	}
	
	return $ret;
}



#-------------------------------------------------------

=head3  rmosdistro

  remove osdistro entry

=cut

#-------------------------------------------------------

sub rmosdistro
{
    my $request  = shift;
    my $callback = shift;
        
    my %keyhash=();
    my $distname=undef;
    my $force=undef;
    my $help=undef;
    
    my $osdistropath=undef;	
	

    my @OSdistroListToDel=();

    if ($request->{arg}) {
  	     	@ARGV = @{$request->{arg}};
    }
  
    GetOptions(
		'h|help'   => \$help,
    		'n|name=s' => \$distname,
		'f|force'  => \$force
 	);

        if ($help) {
     		 $callback->({info=>"rmosdistro [{-n|--name}=osdistroname] [-f|--force]",errorcode=>[0]});
     		 return;
  	}



   	my $osdistrotab = xCAT::Table->new('osdistro',-create=>1);
   	
   	unless($osdistrotab)
	{
        	$callback->({error=>"rmosdistro: failed to open table 'osdistro'!",errorcode=>[1]});
        	return;
	}

	if($distname)
	{
		push(@OSdistroListToDel,$distname);
	}
	else
	{
			my @result=$osdistrotab->getAllAttribs('osdistroname');
			if(defined(@result) and scalar @result >0)
			{
				foreach(@result)
				{
					push(@OSdistroListToDel,$_->{'osdistroname'});
				}
			}		
	}

	if(scalar @OSdistroListToDel)
	{
		my $osimagetab=undef;
		unless($force)
		{
			$osimagetab=xCAT::Table->new('osimage');
			unless($osimagetab)
			{
                	   $callback->({error=>"rmosdistro: failed to open table 'osimage'!",errorcode=>[1]});
               		   return;			
			}
		}

		foreach(@OSdistroListToDel)
		{
			unless($force)
			{
				my $result=&getOSdistroref($osimagetab,$_);
			        if($result)
				{
			            $callback->({error=>"rmosdistro: failed to remove $_, it is referenced by osimages:$result, retry with -f option !",errorcode=>[1]});
                                    next;   
				}	
			}
			

	                $keyhash{osdistroname}    = $_;
			my $result=$osdistrotab->getAttribs(\%keyhash,'dirpaths');
			unless($result)
			{
                            $callback->({error=>"rmosdistro: $keyhash{osdistroname}  not exist!",errorcode=>[1]});
                            next;				
			}
			

			if($result->{'dirpaths'})
			{
			   $result->{'dirpaths'} =~ s/,/\ /g;
			   #$callback->({error=>"rmosdistro: remove $result->{'dirpaths'}  directory!",errorcode=>[0]});
			   system("rm -rf $result->{'dirpaths'}");
			   if($? != 0)
				{
			           $callback->({error=>"rmosdistro: failed to remove $keyhash{osdistroname}  directory!",errorcode=>[1]});
                                   next;
				}
			}
			
                        $osdistrotab->delEntries(\%keyhash);
   			$osdistrotab->commit;
        		$callback->({info=>"rmosdistro: remove $_ success",errorcode=>[0]});
				
		}

		if($osimagetab)
		{
			$osimagetab->close;
		}
	}	


        $osdistrotab->close; 

        return;
}



#-------------------------------------------------------

=head3  lsosdistro

  list osdistro entry

=cut

#-------------------------------------------------------
sub lsosdistro_bak
{

    my $request  = shift;
    my $callback = shift;
    
    my @clause=();
    my @result=();
    my $distname=undef;
    my $basename=undef;
    my $majorversion=undef;
    my $minorversion=undef; 
    my $osver=undef;
    my $arch=undef;
    my $type=undef;
    my $help=undef;
    my $stanza=undef;

    if ($request->{arg}) {
  	     	@ARGV = @{$request->{arg}};
    }
  
    GetOptions(
    		'n|name=s' => \$distname,
                'o|osver=s' =>\$osver,
    		'a|arch=s' => \$arch,
    		't|type=s' => \$type,
    		'h|help' => \$help,
		'z|stanza' => \$stanza,
 	);

        if ($help) {
     		 $callback->({info=>"lsosdistro [{-n|--name}=osdistroname] [{-o|--osver}=osver] [{-t|--type}=ostype]  [{-a|--arch}=architecture][-z|--stanza]",errorcode=>[0]});
     		 return;
  	}
        

        if($distname)
	{
	    push(@clause,"osdistroname==".$distname);
	}

        if($arch)
	{
	    push(@clause,"arch==".$arch);
	}

        if($type)
	{
	    push(@clause,"type==".$type);
	}

        if($osver)
	{
		($basename,$majorversion,$minorversion) = &parseosver($osver);

        	if($basename)
		{
	    		push(@clause,"basename==".$basename);
		}

        	if($majorversion)
		{
	    		push(@clause,"majorversion==".$majorversion);
		}

        	if($minorversion)
		{
	    		push(@clause,"minorversion==".$minorversion);
		}
	}
       
  	my $tab = xCAT::Table->new('osdistro',-create=>1);

        unless(scalar @clause)
	{
			
   		@result=$tab->getTable;
	}else
      	{
   		@result=$tab->getAllAttribsWhere(\@clause,'ALL');
     	}
        $tab->close; 
        #$callback->({info=>"mkosdistro: $distname  success",errorcode=>[0]});
        return;
}



sub lsosdistro
{

    my $request  = shift;
    my $callback = shift;
    
    my @clause=();
    my @result=();
    my $result;

    my $distname=undef;
    my $basename=undef;
    my $majorversion=undef;
    my $minorversion=undef; 
    my $osver=undef;
    my $arch=undef;
    my $type=undef;
    my $help=undef;
    my $stanza=undef;

    if ($request->{arg}) {
  	     	@ARGV = @{$request->{arg}};
    }
  
    GetOptions(
    		'n|name=s' => \$distname,
                'o|osver=s' =>\$osver,
    		'a|arch=s' => \$arch,
    		't|type=s' => \$type,
    		'h|help' => \$help,
		'z|stanza' => \$stanza,
 	);

        if ($help) {
     		 $callback->({info=>"lsosdistro [{-n|--name}=osdistroname] [{-o|--osver}=osver] [{-t|--type}=ostype]  [{-a|--arch}=architecture][-z|--stanza]",errorcode=>[0]});
     		 return;
  	}
        

        if($distname)
	{
	    push(@clause, '-w');
	    push(@clause,"osdistroname==".$distname);
	}

        if($arch)
	{
	    push(@clause, '-w');
	    push(@clause,"arch==".$arch);
	}

        if($type)
	{
	    push(@clause, '-w');
	    push(@clause,"type==".$type);
	}

        if($osver)
	{
		($basename,$majorversion,$minorversion) = &parseosver($osver);

        	if($basename)
		{  
	    		push(@clause, '-w');
	    		push(@clause,"basename==".$basename);
		}

        	if($majorversion)
		{
	    		push(@clause, '-w');
	    		push(@clause,"majorversion==".$majorversion);
		}

        	if($minorversion)
		{
	    		push(@clause, '-w');
	    		push(@clause,"minorversion==".$minorversion);
		}
	}
      
	push(@clause,"osdistro"); 

	my $ret = xCAT::Utils->runxcmd({ command => ['tabdump'], arg => \@clause}, $SUB_REQ_L, 0, 1);


	#print "xxxxx $$ret[1]";
	foreach my $line(@$ret[1..$#$ret])
	{
		$result=$result.$line."\n";	
	}
       $callback->({info=>"$result",errorcode=>[0]});
        return;
}
