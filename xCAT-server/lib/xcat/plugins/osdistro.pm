# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------

=head1
  xCAT plugin package to handle osdistro management

   Supported command:
         rmosdistro->rmosdistro

=cut

#-------------------------------------------------------
package xCAT_plugin::osdistro;
use Sys::Hostname;
use xCAT::Table;

use xCAT::Utils;

use xCAT::MsgUtils;
use Getopt::Long;
use Data::Dumper;
use xCAT::Yum;

#-------------------------------------------------------

=head3  handled_commands

Return list of commands handled by this plugin

=cut

#-------------------------------------------------------

sub handled_commands
{
    return {
	 	rmosdistro => "osdistro",
	   };
}


#-------------------------------------------------------

=head3  process_request

  Process the command

=cut

#-------------------------------------------------------
sub process_request
{

    my $request  = shift;
    my $callback = shift;

    my $command  = $request->{command}->[0];
    my $args     = $request->{arg};
    my $envs     = $request->{env};
    my %rsp;
    # do your processing here
    # return info

    if($command eq "rmosdistro")
    {
      &rmosdistro($request,$callback);  
    }

    return;

}



#-------------------------------------------------------

=head3  getOSdistroref

  check whether the specified osdistro is referenced 
  by any osimage. if yes, return the string of 
  osimage names, return undef otherwise 

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
		$ret =~ s/,$//;
	}
	else
	{
		return undef;
	}
	
	return $ret;
}



#-------------------------------------------------------

=head3  rmosdistro

  remove osdistro,including remove osdistro directory 
  and entry in osdistro table

=cut

#-------------------------------------------------------

sub rmosdistro
{
    my $request  = shift;
    my $callback = shift;
        
    my $all=undef;
    my $force=undef;
    my $help=undef;
    
    my $osdistropath=undef;	
#an array of all the osdistronames to remove	
    my @OSdistroListToDel=();

    if ($request->{arg}) {
  	     	@ARGV = @{$request->{arg}};
    }


    GetOptions(
		'h|help'   => \$help,
    		'a|all'    => \$all,
		'f|force'  => \$force,  
     );


    if ($help) {
     		 $callback->({info=>"rmosdistro [{-a|--all}] [-f|--force] [osdistroname] ...",errorcode=>[0]});
     		 return;
    }

    unless($all)
    {
	unless(scalar @ARGV)
	{
     		$callback->({info=>"please specify osdistroname to remove, or specify \"-a|--all\" to remove all osdistros ",errorcode=>[1]});
     		return;
        }
        #if any osdistro has been specified,push it into array	
	push(@OSdistroListToDel,@ARGV);
    }

    my $osdistrotab = xCAT::Table->new('osdistro',-create=>1);
    unless($osdistrotab)
    {
       	$callback->({error=>"rmosdistro: failed to open table 'osdistro'!",errorcode=>[1]});
       	return;
    }


    #if -a or --all is specified,push all the osdistronames to the array to delete  
    if($all) 
    {
	my @result=$osdistrotab->getAllAttribs('osdistroname');
	if(@result and scalar @result >0)
	{
		foreach(@result)
		{
			push(@OSdistroListToDel,$_->{'osdistroname'});
		}
	}		
    }

    if(scalar @OSdistroListToDel)
    {
        #if -f|--force is not specified,need to open osimage table to check the reference of osdistro  
	my $osimagetab=undef;
	unless($force)
	{
		$osimagetab=xCAT::Table->new('osimage');
		unless($osimagetab)
		{
              	   $callback->({error=>"rmosdistro: failed to open table 'osimage'!",errorcode=>[1]});
		   $osdistrotab->close();	
        	   return;			
		}
	}

	foreach(@OSdistroListToDel)
	{

		#if -f|--force not specified,check the reference of osdistro,complain if the osdistro is referenced by some osimage
		unless($force)
		{
			my $result=&getOSdistroref($osimagetab,$_);
		        if($result)
			{
		            $callback->({error=>"rmosdistro: failed to remove $_, it is referenced by osimages:\n$result\nretry with -f option !",errorcode=>[1]});
                            next;   
			}	
		}
			
		#get "dirpaths" attribute of osdistro to remove the directory, complain if failed to lookup the osdistroname
                my %keyhash=('osdistroname' => $_,);
		my $result=$osdistrotab->getAttribs(\%keyhash,'dirpaths','basename','majorversion','minorversion','arch');
		unless($result)
		{
                         $callback->({error=>"rmosdistro: $keyhash{osdistroname}  not exist!",errorcode=>[1]});
                         next;				
		}
			
		#remove the osdistro directories
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

		
		#remove the repo template
                my @ents = xCAT::TableUtils->get_site_attribute("installdir");
                my $site_ent = $ents[0];
		my $installroot;
                if( defined($site_ent) )
                {
                    $installroot = $site_ent;
                }
		xCAT::Yum->remove_yumrepo($installroot,$result->{basename}.$result->{majorversion}.(defined($result->{minorversion})?'.'.$result->{minorversion}:$result->{minorversion}),$result->{arch});	
	
		#remove the osdistro entry			
                $osdistrotab->delEntries(\%keyhash);
   		$osdistrotab->commit;
                $callback->({info=>["rmosdistro: remove $_ success"],errorcode=>[0]})
				
	}

	if($osimagetab)
	{
		$osimagetab->close;
	}
   }	


        $osdistrotab->close; 

        return;
}


1;
