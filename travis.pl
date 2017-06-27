use LWP::UserAgent;
use HTTP::Request;
use Encode;  
use Encode::CN; 
use JSON;  
use URI::Escape;  
use LWP::Simple;
#use strict;
use File::Find; 


$ower_repo = $ENV{'TRAVIS_REPO_SLUG'};
print "ower_repo : $ower_repo\n";
$branch = $ENV{'TRAVIS_BRANCH'};
print "branch : $branch\n";
$event_type = $ENV{'TRAVIS_EVENT_TYPE'};
print "event_type : $event_type\n";
$token = $ENV{'GITHUB_TOKEN'};
print "token : $token\n";
$username = $ENV{'USERNAME'};
print "username : $username\n";
$password = $ENV{'PASSWORD'};
print "password : $password\n";
$currentPath = $ENV{'PWD'};
print "currentPath : $currentPath\n";
##########################     pull_request format check   ####################
if($event_type eq "pull_request"){
   $pull_number = $ENV{TRAVIS_PULL_REQUEST};
   print "pull_number : $pull_number\n";
   $uri = "https://api.github.com/repos/$ower_repo/pulls/$pull_number";
   print "pull_request_url : $uri\n";
   $resp = get($uri);
   $jresp = decode_json($resp);
   $title = $jresp->{title};
   print "pull_request title : $title\n";
   $body = $jresp->{body};
   print "pull_request body : $body\n";
   $post_url = "https://api.github.com/repos/$ower_repo/issues/$pull_number/comments";
   print "post_url : $post_url\n";	
   $content_type = "Content-Type: application/json";
	
   $issyntax = 0;
   $isbuild = 0;
   $isinstall =0;
   $syntaxId = "";
   $buildId = "";
   $installId = "";
   $syntaxUrl = "";
   $buildUrl = "";
   $installUrl = "";
   
   $json = new JSON;
   $postresp = get($post_url);
   #$postJsonArr = decode_json($postresp);
   $postJsonArr = $json->decode($postresp);
   print "postJsonArr : @{$postJsonArr}\n";
   #$length = @postJsonArr;
   #print "postJsonArr length = $length\n";
   $fisrt = $postJsonArr->[0];
   print "postJsonArr first: $first\n";
   $hashorarray = ref($first);
   print "hash or array : $hashorarray\n";
   $hashbody = $first->{'body'};
   print "hashbody : $hashbody\n";
   $length = @{$postJsonArr};
   print "postJsonArr length = $length\n";
   
   if($length >1){
      foreach $postJson (@{$postJsonArr}){
	     $commentBody = $postJson->{'body'};
	     print "body : $commentBody";
		 if($commentBody =~ /SYNTAX/){
		        $issyntax = 1;
			$syntaxId = $postJson->{'id'};
			$syntaxUrl = "https://api.github.com/repos/$ower_repo/issues/comments/$syntaxId";
		 }
		 if($commentBody =~ /BUILD/){
		        $isbuild = 1;
			$buildId = $postJson->{'id'};
			$buildUrl = "https://api.github.com/repos/$ower_repo/issues/comments/$buildId";
		 }
		 if($commentBody =~ /INSTALL/){
		    $isinstall = 1;
			$installId = $postJson->{'id'};
			$installUrl = "https://api.github.com/repos/$ower_repo/issues/comments/$installId";
		 }
	  }#foreach
   }#length if
   
   
   
   #############################        build         #########################
   
   print "gpg --list-keys\n";
   system("gpg --list-keys");
   
   print "sudo ./build-ubunturepo -c UP=0 BUILDALL=1 >/tmp/build-log 2>&1\n";
   $buildresult = system("sudo ./build-ubunturepo -c UP=0 BUILDALL=1 >/tmp/build-log 2>&1");
   print "buildresult : $buildresult\n";
   system("cat /tmp/build-log");
   if($buildresult != 0){
         $file = "/tmp/build-log";
	 @bLogLines = ();
         open (FILE, $file)||die "Can not open $file";
	 while($read_line=<FILE>){
	   #chomp($read_line);
           push(@bLogLines,$read_line);
	  }
         close(FILE);
         #@bLogLines = split(/\n/,$buildresult);
         $bLastLine = @bLogLines[-1];
	 print "buildresult lastLine : $bLastLine\n";
	 $bLastLine =~ s/[\n\r]*//g;
	 $bLastLine =~ s/\'//g;
	 $bLastLine =~ s/\"//g;
	 $bLastLine =~ s/\t//g;
	 $bLastLine =~ s/\\//g;
	 print "buildresult lastLine : $bLastLine\n";
	 print "isbuild if : $isbuild\n";
	 print "post_url if: $post_url\n";
	 if($isbuild){
	    `curl -u "$username:$password" -X PATCH -d '{"body":"> **BUILD_ERROR**  :  $bLastLine"}'  $buildUrl`;
	 }else{
	    `curl -u "$username:$password" -X POST -d '{"body":"> **BUILD_ERROR**  :  $bLastLine"}'  $post_url`;
	 }
   }else{
     print "isbuild else: $isbuild\n";
     print "post_url else : $post_url\n";
     if($isbuild){
	    `curl -u "$username:$password" -d '{"body":"> **BUILD SUCCESSFUL-patch!**"}' -X PATCH $buildUrl`;
	 }else{
	   print "run here \n";
	   #$post = qq|'{"body": "> **BUILD SUCCESSFUL!**"}' -H "$content_type" $post_url|;
	   $postresult = system("curl -u \"$username:$password\" $post_url -X POST -d '{\"body\":\"> **BUILD SUCCESSFUL!**\"}' ");
	   #&process("curl -u \"$username:$password\" -X POST -d $post"); 
	   print "$postresult\n";
	 }
   
   }
   
   
   
   ############################       install        ###########################

   print "ls -a\n";
   system("ls -a");
   
   print "sudo ./../../xcat-core/mklocalrepo.sh\n";
   $result1 = system("sudo ./../../xcat-core/mklocalrepo.sh");
   print "result:$result1\n";
   
   print "sudo chmod 777 /etc/apt/sources.list\n";
   $result2 = system("sudo chmod 777 /etc/apt/sources.list");
   print "result:$result2\n";
   
   print "sudo echo \"deb [arch=amd64] http://xcat.org/files/xcat/repos/apt/xcat-dep trusty main\" >> /etc/apt/sources.list\n";
   $result3 = system("sudo echo \"deb [arch=amd64] http://xcat.org/files/xcat/repos/apt/xcat-dep trusty main\" >> /etc/apt/sources.list");
   print "result:$result3\n";
   
   print "sudo echo \"deb [arch=ppc64el] http://xcat.org/files/xcat/repos/apt/xcat-dep trusty main\" >> /etc/apt/sources.list\n";
   $result4 = system("sudo echo \"deb [arch=ppc64el] http://xcat.org/files/xcat/repos/apt/xcat-dep trusty main\" >> /etc/apt/sources.list");
   print "result:$result4\n";
   
   system("cat /etc/apt/sources.list");
   
   print "sudo wget -O - \"http://xcat.org/files/xcat/repos/apt/apt.key\" | sudo apt-key add -\n";
   $result5 = system("sudo wget -O - \"http://xcat.org/files/xcat/repos/apt/apt.key\" | sudo apt-key add -");
   print "result:$result5\n";
   
   print "sudo apt-get -qq update\n";
   $result6 = system("sudo apt-get -qq update");
   print "result:$result6\n";
   
   print "sudo apt-get install xCAT --force-yes >/tmp/install-log 2>&1\n";
   $installresult = system("sudo apt-get install xCAT --force-yes >/tmp/install-log 2>&1");
   print "installresult : $installresult\n";
   system("cat /tmp/install-log");
   if($installresult ne "0"){
         print("run installresult if \n");
         $ifile = "/tmp/install-log";
	 @iLogLines = ();
         open (iFILE, $ifile)||die "Can not open $ifile";
	 while($iread_line=<iFILE>){
	   #chomp $read_line;
           push(@iLogLines,$iread_line);
	  }
         close(iFILE);
         #@iLogLines = split(/\n/,$installresult);
         $iLastLine = @iLogLines[-1];
	 print "installresult lastLine : $iLastLine";
	 $iLastLine =~ s/[\n\r]*//g;
	 $iLastLine =~ s/\'//g;
	 $iLastLine =~ s/\"//g;
	 $iLastLine =~ s/\t//g;
	 $iLastLine =~ s/\\//g;
	 print "installresult lastLine : $iLastLine\n";
	 print "isinstall : $isinstall\n";
	 if($isinstall){
	    `curl -u "$username:$password" -X PATCH -d '{"body":"> **INSTALL_ERROR**  : $iLastLine"}'  $installUrl`;
	 }else{
	    `curl -u "$username:$password" -X POST -d '{"body":"> **INSTALL_ERROR**  : $iLastLine"}'  $post_url`;
	 }
   }else{
     print "isinstall : $isinstall\n";
     print "post_url : $post_url\n";
     if($isinstall){
	    `curl -u "$username:$password" -d '{"body":"> **INSTALL SUCCESSFUL!**"}' -X PATCH $installUrl`;
	 }else{
	    $postiresult = `curl -u "$username:$password" -d '{"body":"> **INSTALL SUCCESSFUL!**"}' -X POST $post_url`;
	    print "$postiresult";
	 }
   
   }
   
 ###########################    Verify xCAT Installation   ##################################

   print "source /etc/profile.d/xcat.sh\n";
   system("source /etc/profile.d/xcat.sh");
   
   print "sudo echo $USER";
   system("sudo echo $USER");
   
   print "sudo -s /opt/xcat/share/xcat/scripts/setup-local-client.sh -f travis\n";
   system("sudo -s /opt/xcat/share/xcat/scripts/setup-local-client.sh -f travis");
   
   print "sudo -s /opt/xcat/sbin/chtab priority=1.1 policy.name=travis policy.rule=allow\n";
   system("sudo -s /opt/xcat/sbin/chtab priority=1.1 policy.name=travis policy.rule=allow");
   
   print "lsxcatd -v\n";
   system("lsxcatd -v");
   
   print "tabdump policy\n";
   system("tabdump policy");
   
   print "tabdump site\n";
   system("tabdump site");
   
   print "ls /opt/xcat/sbin\n";
   system("ls /opt/xcat/sbin");
   
   print "service xcatd start\n";
   system("service xcatd start");
   
   print "service xcatd status\n";
   system("service xcatd status");
   
   
  
   ######################################  check syntax  ################################################
   
   
   #chomp($currentPath);
   print "currentPath : $currentPath\n";
	  
   @libPath = ("./check-perl-lib/Confluent",
               "./check-perl-lib/Crypt",
               "./check-perl-lib/HTTP",
               "./check-perl-lib/IO/Socket",
               "./check-perl-lib/LWP",
               "./check-perl-lib/Net",
               "./check-perl-lib/SOAP",
               "./check-perl-lib/XML",
               "./check-perl-lib/xCAT",
               "./check-perl-lib/xCAT_monitoring",
               "./check-perl-lib/xCAT_plugin",
               "./check-perl-lib");
   foreach $checkpath (@libPath){
	     system("mkdir -p $checkpath");
   }
   @libFiles = ("/check-perl-lib/Confluent/Client.pm",
              "/check-perl-lib/Confluent/TLV.pm",
                  "/check-perl-lib/Crypt/CBC.pm",
                  "/check-perl-lib/Crypt/Rijndael.pm",
                   "/check-perl-lib/HTTP/Async.pm",
                   "/check-perl-lib/HTTP/Headers.pm",
              "/check-perl-lib/IO/Socket/SSL.pm",
                    "/check-perl-lib/LWP/Simple.pm",
                    "/check-perl-lib/Net/DNS.pm",
                    "/check-perl-lib/Net/SSLeay.pm",
                    "/check-perl-lib/Net/Telnet.pm",
                    "/check-perl-lib/SOAP/Lite.pm",
                    "/check-perl-lib/XML/LibXML.pm",
                    "/check-perl-lib/XML/Simple.pm",
                   "/check-perl-lib/xCAT/SwitchHandler.pm",
		   "/check-perl-lib/xCAT/Table.pm",
		   "/check-perl-lib/xCAT/Utils.pm",
		   "/check-perl-lib/xCAT/Client.pm",
		   "/check-perl-lib/xCAT/MsgUtils.pm",
		   "/check-perl-lib/xCAT/PPC.pm",
		   "/check-perl-lib/xCAT/Scope.pm",
		   "/check-perl-lib/xCAT/NodeRange.pm",
		   "/check-perl-lib/xCAT/SvrUtils.pm",
		   "/check-perl-lib/xCAT/GlobalDef.pm",
		   "/check-perl-lib/xCAT/Usage.pm",
		   "/check-perl-lib/xCAT/Enabletrace.pm",
		   "/check-perl-lib/xCAT/PasswordUtils.pm",
		   "/check-perl-lib/xCAT/Usage.pm",
		   "/check-perl-lib/xCAT/PPCcli.pm",
		   "/check-perl-lib/xCAT/zvmUtils.pm",
		   "/check-perl-lib/xCAT/NetworkUtils.pm",
        "/check-perl-lib/xCAT_monitoring/monitorctrl.pm",
        "/check-perl-lib/xCAT_monitoring/montbhandler.pm",
        "/check-perl-lib/xCAT_monitoring/rmcmetrix.pm",
        "/check-perl-lib/xCAT_monitoring/rrdutil.pm",
            "/check-perl-lib/xCAT_plugin/blade.pm",
            "/check-perl-lib/xCAT_plugin/bmcconfig.pm",
            "/check-perl-lib/xCAT_plugin/conserver.pm",
            "/check-perl-lib/xCAT_plugin/dhcp.pm",
            "/check-perl-lib/xCAT_plugin/hmc.pm",
            "/check-perl-lib/xCAT_plugin/notification.pm",
                        "/check-perl-lib/Expect.pm",
                        "/check-perl-lib/JSON.pm",
                        "/check-perl-lib/LWP.pm",
                        "/check-perl-lib/SNMP.pm",
                        "/check-perl-lib/probe_global_constant.pm",
                        "/check-perl-lib/probe_utils.pm");
   foreach $value (@libFiles){
     $allpath = "$currentPath$value";
	 system("echo \"1;\" > $allpath");
   }
   system("ls -a ./check-perl-lib");
   @resultArr = ();
   $i=1;
   @pathArr =();
   push(@pathArr,'/home/travis/build/DengShuaiSimon/xcat-core');
   sub wanted{
	  $path = $File::Find::name;
	  if(-f $File::Find::name){
	    $fileType = `file $path 2>&1`;
		if($fileType =~ /Perl/){
		  print "path : $path";
		  $result = `perl -I perl-xCAT/ -I check-perl-lib -I xCAT-server/lib/perl/ -c $path 2>&1`;
		  print "result : $result\n";
		  $subresult = substr($result,-3,2);
		  print "substr(result,-3,2) : $subresult\n";
		  
		  if($subresult ne "OK"){
		    $result =~ s/[\n\r]*//g;
			$result =~ s/\'//g;
			$result =~ s/\"//g;
			$result =~ s/\t//g;
			$result =~ s/\'//g;
			$result =~ s/\\//g;
			$result = "$i $result";
			push(@resultArr,$result);
			$i = $i+1;
		  }
		}
	  }
   }#sub
   find(\&wanted,@pathArr);
   $resultArr1 = join("****",@resultArr);
   print "resultArr1 : $resultArr\n";
   
   ####################   add comments  ########################## 
   if(@resultArr){
      if(issyntax){
	    `curl -u "$username:$password" -X PATCH -d '{"body":"> **SYNTAX_ERROR**  : $resultArr1"}'  $syntaxUrl`;
	  }else{
	    `curl -u "$username:$password" -X POST -d '{"body":"> **SYNTAX_ERROR**  : $resultArr1"}'  $post_url`;
	  }
   }else{
        if(issyntax){
	    `curl -u "$username:$password" -X PATCH -d '{"body":"> **SYNTAX CORRECT!**"}'  $syntaxUrl`;
	  }else{
	    `curl -u "$username:$password" -X POST -d '{"body":"> **SYNTAX CORRECT!**"}'  $post_url`;
	  }
   }
	
####################    stop and print error in travis (red color)  ########## 
	
   print color 'bold red';
   foreach $term (@resultArr){
      print $term;
   }
   print "resultArr : @resultArr\n";
   print color 'reset';

   
   
   
   
   
	
	
	
	
=pod
   $req = HTTP::Request->new(GET=>$uri);
   $req->header('content-type'=>'application/json');
   $resp = $ua->request($req);
   if($resp->is_success){
      $jresp = $resp->decoded_content;
   }else{
     print "HTTP GET error code: ", $resp->code, "\n";
	 print "HTTP GET error message: ", $resp->message, "\n";
   }
=cut
}#pull_request if
