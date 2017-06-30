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
   #$syntaxId = "";
   #$buildId = "";
   #$installId = "";
   #$syntaxUrl = "";
   #$buildUrl = "";
   #$installUrl = "";
   
   $json = new JSON;
   $postresp = get($post_url);
   #$postJsonArr = decode_json($postresp);
   $postJsonArr = $json->decode($postresp);
   print "postJsonArr : @{$postJsonArr}\n";
   $length = @{$postJsonArr};
   print "postJsonArr length = $length\n";
   
   if($length >1){
      foreach $postJson (@{$postJsonArr}){
	     $commentBody = $postJson->{'body'};
	     print "body : $commentBody\n";
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
   
   print "\033[42mgpg --list-keys\033[0m\n";
   system("gpg --list-keys");
   
   print "\033[42msudo ./build-ubunturepo -c UP=0 BUILDALL=1 >/tmp/build-log 2>&1\033[0m\n";
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
	 if($isbuild){
	    `curl -u "$username:$password" -X PATCH -d '{"body":"> **BUILD_ERROR**  :  $bLastLine"}'  $buildUrl`;
	 }else{
	    `curl -u "$username:$password" -X POST -d '{"body":"> **BUILD_ERROR**  :  $bLastLine"}'  $post_url`;
	 }
	 die "\033[31mBuild error!\033[0m\n";
   }else{
     if($isbuild){
	    `curl -u "$username:$password" -d '{"body":"> **BUILD SUCCESSFUL-patch!**"}' -X PATCH $buildUrl`;
	    #`curl -u "$username:$password" -d '{"body":"> **BUILD SUCCESSFUL-patch!**"}' -X DELETE $buildUrl`;
	 }else{
	   $postresult = system("curl -u \"$username:$password\"  -d '{\"body\":\"> **BUILD SUCCESSFUL-post!**\"}' -X POST $post_url");
	   print "postresult: $postresult\n";
	 }
   
   }
   
   
   
   ############################       install        ###########################

   print "\033[42mls -a\033[0m\n";
   system("ls -a");
   
   $cdresult = chdir('/home/travis/build/xcat-core') or die "$!";
   print "cdresult : $cdresult\n";
   system("ls -a");
   
   print "\033[42msudo ./mklocalrepo.sh\033[0m\n";
   $result1 = system("sudo ./mklocalrepo.sh");
   print "mklocalrepo.sh result :$result1\n";
   
   print "\033[42msudo chmod 777 /etc/apt/sources.list\033[0m\n";
   $result2 = system("sudo chmod 777 /etc/apt/sources.list");
   print "chmod 777 sources.list result:$result2\n";
   
   print "\033[42msudo echo \"deb [arch=amd64] http://xcat.org/files/xcat/repos/apt/xcat-dep trusty main\" >> /etc/apt/sources.list\033[0m\n";
   $result3 = system("sudo echo \"deb [arch=amd64] http://xcat.org/files/xcat/repos/apt/xcat-dep trusty main\" >> /etc/apt/sources.list");
   print "echo arch=amd64 result:$result3\n";
   
   print "\033[42msudo echo \"deb [arch=ppc64el] http://xcat.org/files/xcat/repos/apt/xcat-dep trusty main\" >> /etc/apt/sources.list\033[0m\n";
   $result4 = system("sudo echo \"deb [arch=ppc64el] http://xcat.org/files/xcat/repos/apt/xcat-dep trusty main\" >> /etc/apt/sources.list");
   print "echo arch=ppc64el result:$result4\n";
   
   system("cat /etc/apt/sources.list");
   
   print "\033[42msudo wget -O - \"http://xcat.org/files/xcat/repos/apt/apt.key\" | sudo apt-key add -\033[0m\n";
   $result5 = system("sudo wget -O - \"http://xcat.org/files/xcat/repos/apt/apt.key\" | sudo apt-key add -");
   print "wget ...key result:$result5\n";
   
   print "\033[42msudo apt-get -qq update\033[0m\n";
   $result6 = system("sudo apt-get -qq update");
   print "apt-get update result:$result6\n";
   
   print "\033[42msudo apt-get install xcat --force-yes >/tmp/install-log 2>&1\033[0m\033[42m";
   $installresult = system("sudo apt-get install xcat --force-yes >/tmp/install-log 2>&1");
   print "installresult : $installresult\n";
   system("cat /tmp/install-log");
   if($installresult != 0){
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
	 die "\033[31mInstall Error!\033[0m\n";
   }else{
     print "isinstall : $isinstall\n";
     print "post_url : $post_url\n";
     if($isinstall){
	    `curl -u "$username:$password" -d '{"body":"> **INSTALL SUCCESSFUL-patch!**"}' -X PATCH $installUrl`;
	 }else{
	    $postiresult = `curl -u "$username:$password" -d '{"body":"> **INSTALL SUCCESSFUL-post!**"}' -X POST $post_url`;
	    print "$postiresult";
	 }
   
   }
   
 ###########################    Verify xCAT Installation   ##################################

   print "\033[42msource /etc/profile.d/xcat.sh\033[0m\n";
   system("source /etc/profile.d/xcat.sh");
   
   print "\033[42msudo echo $USER\033[0m\n";
   system("sudo echo $USER");
   
   print "\033[42msudo -s /opt/xcat/share/xcat/scripts/setup-local-client.sh -f travis\033[0m\n";
   system("sudo -s /opt/xcat/share/xcat/scripts/setup-local-client.sh -f travis");
   
   print "\033[42msudo -s /opt/xcat/sbin/chtab priority=1.1 policy.name=travis policy.rule=allow\033[0m\n";
   system("sudo -s /opt/xcat/sbin/chtab priority=1.1 policy.name=travis policy.rule=allow");
   
   print "\033[42mlsxcatd -v\033[0m\n";
   system("lsxcatd -v");
   
   print "\033[42mtabdump policy\033[0m\n";
   system("tabdump policy");
   
   print "\033[42mtabdump site\033[0m\n";
   system("tabdump site");
   
   print "\033[42mls /opt/xcat/sbin\033[0m\n";
   system("ls /opt/xcat/sbin");
   
   print "\033[42mservice xcatd start\033[0m\n";
   system("service xcatd start");
   
   print "\033[42mservice xcatd status\033[0m\n";
   system("service xcatd status");
   
   #die "\033[42mStop check syntax!\033[0m\n";
  
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
   #push(@pathArr,'/home/travis/build/DengShuaiSimon/xcat-core');
   push(@pathArr,'/opt/xcat');
   sub wanted{
	  $path = $File::Find::name;
	  if(-f $File::Find::name){
	    $fileType = `file $path 2>&1`;
		if(($fileType =~ /Perl/)&&($path !~ /genesis/)){
		  #print "path : $path";
		  #$result = `perl -I perl-xCAT/ -I check-perl-lib -I xCAT-server/lib/perl/ -c $path 2>&1`;
		  $result = `sudo perl -I /opt/xcat/lib/perl -I /opt/xcat/lib -I /usr/lib/perl5 -I /usr/share/perl -c $path 2>&1`;
		  print "result : $result\n";
		  #$subresult = substr($result,-3,2);
		  #print "substr(result,-3,2) : $subresult\n";
		  
		  if($result !~ /syntax OK/){
		        $result =~ s/[\n\r]*//g;
			$result =~ s/\'//g;
			$result =~ s/\"//g;
			$result =~ s/\t//g;
			$result =~ s/\\//g;
			$result = "( $i ) $result";
			push(@resultArr,$result);
			$i = $i+1;
		  }
		}
	  }
   }#sub
   find(\&wanted,@pathArr);
   $resultArr1 = join("****",@resultArr);
   #print "\033[31mresultArr1 : $resultArr1\033[0m\n";
   $checklength = @resultArr;
   print "resultArr length: $checklength\n";
   
   ####################   add comments  ########################## 
   if($checklength>0){
      if($issyntax){
	    `curl -u "$username:$password" -X PATCH -d '{"body":"> **SYNTAX_ERROR**  : $resultArr1"}'  $syntaxUrl`;
	  }else{
	    `curl -u "$username:$password" -X POST -d '{"body":"> **SYNTAX_ERROR**  : $resultArr1"}'  $post_url`;
	  }
	  #######    stop and print error in travis (red color)  ####
	  foreach $term (@resultArr){
              print "\033[31m$term\033[0m\n";
          }
	  #die "\033[31mCheck syntax error!\033[0m\n";
   }else{
        if($issyntax){
	    `curl -u "$username:$password" -X PATCH -d '{"body":"> **SYNTAX CORRECT!**"}'  $syntaxUrl`;
	  }else{
	    `curl -u "$username:$password" -X POST -d '{"body":"> **SYNTAX CORRECT!**"}'  $post_url`;
	  }
   }



##############################   xcat-test install and test cases   ######################################

   print "\033[42msudo apt-get -y install xcat-test\033[0m\n";
   $testresult =`sudo apt-get -y install xcat-test`;
   print "restresult : $testresult\n";
   
   print "sudo find / -name 'xcat-test_*'\n";
   $findresult = `sudo find / -name 'xcat-test_*'`;
   print "findresult : $findresult";
   
   
   






   
   
   
	
	
	
	
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
