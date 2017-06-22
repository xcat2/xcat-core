use LWP::UserAgent;
use Encode;  
use Encode::CN; 
use JSON;  
use URI::Escape;  
use LWP::Simple;
#use strict;
use File::Find; 


$ower_repo = $ENV{'TRAVIS_REPO_SLUG'};
print "ower_repo : $ower_repo";
$branch = $ENV{'TRAVIS_BRANCH'};
print "branch : $branch";
$event_type = $ENV{'TRAVIS_EVENT_TYPE'};
print "event_type : $event_type";
$token = $ENV{'GITHUB_TOKEN'};
print "token : $token";
$username = $ENV{'USERNAME'};
print "username : $username";
$password = $ENV{'PASSWORD'};
print "password : $password";
$currentPath = $ENV{'PWD'};
print "currentPath : $currentPath";
##########################     pull_request format check   ####################
if($event_type eq "pull_request"){
   $pull_number = $ENV{TRAVIS_PULL_REQUEST};
   print "pull_number : $pull_number";
   $ua = LWP::UserAgent->new;
   $uri = "https://api.github.com/repos/$ower_repo/pulls/$pull_number";
   print "pull_request_url : $uri";
   $resp = get($uri);
   $jresp = decode_json($resp);
   $title = $jresp->{title};
   print "pull_request title : $title";
   $body = $jresp->{body};
   print "pull_request body : $body";
   $post_url = "https://api.github.com/repos/$ower_repo/issues/$pull_number/comments";
   print "post_url : $post_url";	 
	
   $issyntax = 0;
   $isbuild = 0;
   $isinstall =0;
   $syntaxId = "";
   $buildId = "";
   $installId = "";
   $syntaxUrl = "";
   $buildUrl = "";
   $installUrl = "";
   
   $postresp = get($post_url);
   @postJsonArr = decode_json($postresp);
   print "postJsonArr : @postJsonArr";
   $length = @postJsonArr;
   if($length != 0){
      foreach $postJson (@postJsonArr){
	     $commentBody = $postJson->{body};
		 if($commentBody =~ /> **SYNTAX/){
		    $issyntax = 1;
			$syntaxId = $postJson->{id};
			$syntaxUrl = "https://api.github.com/repos/$ower_repo/issues/comments/$syntaxId";
		 }
		 if($commentBody =~ /> **BUILD/){
		    $isbuild = 1;
			$buildId = $postJson->{id};
			$buildUrl = "https://api.github.com/repos/$ower_repo/issues/comments/$buildId";
		 }
		 if($commentBody =~ /> **INSTALL/){
		    $isinstall = 1;
			$installId = $postJson->{id};
			$installUrl = "https://api.github.com/repos/$ower_repo/issues/comments/$installId";
		 }
	  }#foreach
   }#length if
   
   
   ######################################  check syntax  ################################################
   
   
   #chomp($currentPath);
   print "currentPath : $currentPath";
	  
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
   foreach $chechpath (@libPath){
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
		  print "result : $result";
		  $subresult = substr($result,-3,2);
		  print "substr($result,-3,2) : $subresult";
		  
		  if($subresult eq "OK"){
		    $result =~ s/[\n\r]*//g;
			$result =~ s/\'//g;
			$result =~ s/\"//g;
			$result =~ s/\t//g;
			$result =~ s/\'//g;
			$result =~ s/\\//g;
			$result = "$i $result"
			push(@resultArr,$result);
			i = i+1;
		  }
		}
	  }
   }#sub
   find(\&wanted,@pathArr);
   $resultArr1 = join("****",@resultArr);
   print "resultArr1 : $resultArr";
   
   ####################   add comments  ########################## 
   if(@resultArr){
      if(issyntax){
	    `curl -u "$username:$password" -X PATCH -d '{"body":"> **SYNTAX_ERROR**  : $resultArr1"}'  $syntaxUrl`
	  }else{
	    `curl -u "$username:$password" -X POST -d '{"body":"> **SYNTAX_ERROR**  : $resultArr1"}'  $post_url`
	  }
   }else{
        if(issyntax){
	    `curl -u "$username:$password" -X PATCH -d '{"body":"> **SYNTAX CORRECT!**"}'  $syntaxUrl`
	  }else{
	    `curl -u "$username:$password" -X POST -d '{"body":"> **SYNTAX CORRECT!**"}'  $post_url`
	  }
   }
	
####################    stop and print error in travis (red color)  ########## 
	
   print color 'bold red';
   foreach $term (@resultArr){
      print $term;
   }
   print "resultArr : @resultArr";
   print color 'reset';

   #############################        build         #########################
   print color 'bold green';
   print "gpg --list-keys";
   print color 'reset';
   system("gpg --list-keys");
   
   print color 'bold green';
   print "sudo ./build-ubunturepo -c UP=0 BUILDALL=1 >/tmp/build-log 2>&1";
   print color 'reset';
   $buildresult = system("sudo ./build-ubunturepo -c UP=0 BUILDALL=1 >/tmp/build-log 2>&1");
   print "buildresult : $buildresult";
   if(!$buildresult){
     chomp($buildresult);
     @bLogLines = split(/\n/,$buildresult);
     $bLastLine = @bLogLines[-1];
	 print "buildresult lastLine : $bLastLine";
	 $bLastLine =~ s/[\n\r]*//g;
	 $bLastLine =~ s/\'//g;
	 $bLastLine =~ s/\"//g;
	 $bLastLine =~ s/\t//g;
	 $bLastLine =~ s/\'//g;
	 $bLastLine =~ s/\\//g;
	 print "buildresult lastLine : $bLastLine";
	 if(isbuild){
	    `curl -u "$username:$password" -X PATCH -d '{"body":"> **BUILD_ERROR**  :  $bLastLine"}'  $buildUrl`
	 }else{
	    `curl -u "$username:$password" -X POST -d '{"body":"> **BUILD_ERROR**  :  $bLastLine"}'  $post_url`
	 }
   }else{
     if(isbuild){
	    `curl -u "$username:$password" -X PATCH -d '{"body":"> **BUILD SUCCESSFUL!**"}'  $buildUrl`
	 }else{
	    `curl -u "$username:$password" -X POST -d '{"body":"> **BUILD SUCCESSFUL!**"}'  $post_url`
	 }
   
   }
   
   
   
   ############################       install        ###########################
   print color 'bold green';
   print "ls -a";
   print color 'reset';
   system("ls -a");
   
   print color 'bold green';
   print "sudo ./../../xcat-core/mklocalrepo.sh";
   print color 'reset';
   system("sudo ./../../xcat-core/mklocalrepo.sh");
   
   print color 'bold green';
   print "sudo chmod 777 /etc/apt/sources.list";
   print color 'reset';
   system("sudo chmod 777 /etc/apt/sources.list");
   
   print color 'bold green';
   print "sudo echo \"deb [arch=amd64] http://xcat.org/files/xcat/repos/apt/xcat-dep trusty main\" >> /etc/apt/sources.list";
   print color 'reset';
   system('sudo echo "deb [arch=amd64] http://xcat.org/files/xcat/repos/apt/xcat-dep trusty main" >> /etc/apt/sources.list');
   
   print color 'bold green';
   print "sudo echo \"deb [arch=ppc64el] http://xcat.org/files/xcat/repos/apt/xcat-dep trusty main\" >> /etc/apt/sources.list";
   print color 'reset';
   system('sudo echo "deb [arch=ppc64el] http://xcat.org/files/xcat/repos/apt/xcat-dep trusty main" >> /etc/apt/sources.list');
   
   print color 'bold green';
   print "sudo wget -O - \"http://xcat.org/files/xcat/repos/apt/apt.key\" | sudo apt-key add -";
   print color 'reset';
   system('sudo wget -O - "http://xcat.org/files/xcat/repos/apt/apt.key" | sudo apt-key add -');
   
   print color 'bold green';
   print "sudo apt-get -qq update";
   print color 'reset';
   system("sudo apt-get -qq update");
   
   print color 'bold green';
   print "sudo apt-get install xCAT --force-yes >/tmp/install-log 2>&1";
   print color 'reset';
   $installresult = system("sudo apt-get install xCAT --force-yes >/tmp/install-log 2>&1");
   print "installresult : $installresult";
   if(!$installresult){
     chomp($installresult);
     @iLogLines = split(/\n/,$installresult);
     $iLastLine = @iLogLines[-1];
	 print "installresult lastLine : $iLastLine";
	 $iLastLine =~ s/[\n\r]*//g;
	 $iLastLine =~ s/\'//g;
	 $iLastLine =~ s/\"//g;
	 $iLastLine =~ s/\t//g;
	 $iLastLine =~ s/\'//g;
	 $iLastLine =~ s/\\//g;
	 print "installresult lastLine : $iLastLine";
	 if(isinstall){
	    `curl -u "$username:$password" -X PATCH -d '{"body":"> **INSTALL_ERROR**  : $iLastLine"}'  $installUrl`
	 }else{
	    `curl -u "$username:$password" -X POST -d '{"body":"> **INSTALL_ERROR**  : $iLastLine"}'  $post_url`
	 }
   }else{
     if(isinstall){
	    `curl -u "$username:$password" -X PATCH -d '{"body":"> **INSTALL SUCCESSFUL!**"}'  $installUrl`
	 }else{
	    `curl -u "$username:$password" -X POST -d '{"body":"> **INSTALL SUCCESSFUL!**"}'  $post_url`
	 }
   
   }
   
 ###########################    Verify xCAT Installation   ##################################
   print color 'bold green';
   print "source /etc/profile.d/xcat.sh";
   print color 'reset';
   system("source /etc/profile.d/xcat.sh");
   
   print color 'bold green';
   print "sudo echo $USER";
   print color 'reset';
   system("sudo echo $USER");
   
   print color 'bold green';
   print "sudo -s /opt/xcat/share/xcat/scripts/setup-local-client.sh -f travis";
   print color 'reset';
   system("sudo -s /opt/xcat/share/xcat/scripts/setup-local-client.sh -f travis");
   
   print color 'bold green';
   print "sudo -s /opt/xcat/sbin/chtab priority=1.1 policy.name=travis policy.rule=allow";
   print color 'reset';
   system("sudo -s /opt/xcat/sbin/chtab priority=1.1 policy.name=travis policy.rule=allow");
   
   print color 'bold green';
   print "lsxcatd -v";
   print color 'reset';
   system("lsxcatd -v");
   
   print color 'bold green';
   print "tabdump policy";
   print color 'reset';
   system("tabdump policy");
   
   print color 'bold green';
   print "tabdump site";
   print color 'reset';
   system("tabdump site")
   
   print color 'bold green';
   print "ls /opt/xcat/sbin";
   print color 'reset';
   system("ls /opt/xcat/sbin");
   
   print color 'bold green';
   print "service xcatd start";
   print color 'reset';
   system("service xcatd start");
   
   print color 'bold green';
   print "service xcatd status";
   print color 'reset';
   system("service xcatd status");
   
   
  
   
   
   
   
   
   
	
	
	
	
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
