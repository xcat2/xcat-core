require 'rubygems'
#require 'nokogiri'
#require 'open-uri'
require 'json'
require 'net/http'
require 'uri'
#require 'pry'
require 'find'

#repo =Travis::Repository.current
#puts repo
#ower_repo = system('echo $TRAVIS_REPO_SLUG')
ower_repo = ENV['TRAVIS_REPO_SLUG']
puts "ower_repo : #{ower_repo}"
#branch = system('echo $TRAVIS_BRANCH')
branch = ENV['TRAVIS_BRANCH']
puts "branch : #{branch}"
#event_type = system('echo $TRAVIS_EVENT_TYPE')
event_type = ENV['TRAVIS_EVENT_TYPE']
puts "event_type : #{event_type}"
token = ENV["GITHUB_TOKEN"]
puts "token : #{token}"
username = ENV['USERNAME']
puts "username : #{username}"
password = ENV["PASSWORD"]
puts "password : #{password}"

#build
#`gpg --gen-key`
#`sudo ./build-ubunturepo -c UP=0 BUILDALL=1;`
#`gpg --list-keys`
#`gpg --gen-key`
tmppath = "./lalala/lala"
system("mkdir -p #{tmppath}")
system("echo \"1;\" > #{tmppath}/1.txt")
system("cat #{tmppath}/1.txt")




##########################     pull_request format check   ####################
if(event_type == "pull_request")
  #pull_number = system('echo $TRAVIS_PULL_REQUEST')
  pull_number = ENV['TRAVIS_PULL_REQUEST']
  puts "pull_number : #{pull_number}"
  uri = "https://api.github.com/repos/#{ower_repo}/pulls/#{pull_number}"
  puts "pull_request_url : #{uri}"
  resp = Net::HTTP.get_response(URI.parse(uri))
  jresp = JSON.parse(resp.body)
  #puts "jresp: #{jresp}"
  title = jresp['title']
  puts "pull_request title : #{title}"
  body = jresp['body']
  puts "pull_request body : #{body}"
  post_url = "https://api.github.com/repos/#{ower_repo}/issues/#{pull_number}/comments"
  puts "post_url : #{post_url}"	
  
  issyntax = false
  isbuild = false
  isinstall =false
  syntaxId = ""
  buildId = ""
  installId = ""
  syntaxUrl = ""
  buildUrl = ""
  installUrl = ""
	
  # Remove digits
  #title = title.gsub!(/\D/, "")
  
  if(!(title =~ /^Add|Refine test case|cases for issue|feature(.*)/))
    #raise "The title of this pull_request have a wrong format. Fix it!"
  end
  if(!(body =~ (/Add|Refine \d case|cases in this pull request(.*)/m))||!(body =~ (/This|These case|cases is|are added|refined for issue|feature(.*)/m))||!(body =~ (/This pull request is for task(.*)/m)))
    #raise "The description of this pull_request have a wrong format. Fix it!"
  end
 
  postresp = Net::HTTP.get_response(URI.parse(post_url))
  postJsonArr = Array.new
  postJsonArr = JSON.parse(postresp.body)
  puts "postJsonArr : #{postJsonArr}"
  if(postJsonArr.length != 0)
     postJsonArr.each{|postJson| 
	commentBody = postJson['body']
	if(commentBody.include?("> **SYNTAX"))
		issyntax = true
		syntaxId = postJson['id']
		syntaxUrl = "https://api.github.com/repos/#{ower_repo}/issues/comments/#{syntaxId}"
	end
	if(commentBody.include?("> **BUILD"))
		isbuild = true
		buildId = postJson['id']
		buildUrl = "https://api.github.com/repos/#{ower_repo}/issues/comments/#{buildId}"
	end
	if(commentBody.include?("> **INSTALL"))
		isinstall = true
		installId = postJson['id']
		installUrl = "https://api.github.com/repos/#{ower_repo}/issues/comments/#{installId}"
	end 
    }
  end
  ######################################  check syntax  ################################################
  currentPath = `pwd`
  puts "currentPath ---------\n"
  currentPath.chomp!
  p currentPath
	
  libPath =  ["./check-perl-lib/Confluent",
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
                        "./check-perl-lib",
                        ]
  libPath.each{|checkpath| system("mkdir -p #{checkpath}")}
	
  libFiles = ["/check-perl-lib/Confluent/Client.pm",
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
                        "/check-perl-lib/probe_utils.pm"]
  
  libFiles.each{|value|
	#f=File.new(File.join("#{currentPath}#{key}","#{value}"),"w+")
 	#f.puts("1;")
	#f=File.new("#{value}","r+")
	#if f
	#	f.syswrite("1;")
        #else
        #        puts "Unable to open file!"
        #end
	allpath = "#{currentPath}#{value}"
	system("echo \"1;\" > #{allpath}")
}
 
 
 
 
  resultArr = Array.new
  #print all path at current path
  puts "work path : #{Dir.pwd}"
  i = 1
  Find.find('/home/travis/build/DengShuaiSimon/xcat-core') do |path| 
    if(File.file?(path))
	    
=begin
     #--------file command test----------
     fileType = `file #{path} 2>&1`
     puts "fileReturn : #{fileType}"
     if(fileType.include?("shell"))
           puts "shell"
     elsif(fileType.include?("Perl"))
           puts "Perl"
     end
=end
     
      base_name = File.basename(path,".*")
      #puts "notype_basename : #{base_name}"
      file_type = path.split(base_name)
      #puts "file type : #{file_type[1]}"
    
      #puts "\n" 
      if(file_type[1] == ".pm")
        puts "path : #{path}"
        result = %x[perl -I perl-xCAT/ -I check-perl-lib -I xCAT-server/lib/perl/ -c #{path} 2>&1]
        puts result
        puts "result[-3..-2] : #{result[-3..-2]}"

        if(result[-3..-2]!="OK")
          #p result
	  result.delete!('\'')
	  result.delete!('\"')
          result.delete!('\\')
	  result.gsub!("\n"," ")
	  result.gsub!("\r"," ")
          result.gsub!("\t"," ")
          result.chomp!
	  result = "(#{i}) #{result}"
          resultArr.push(result)
	  i = i+1
        end

        puts "\n"
      end
    end
  
  end #find ... do
  resultArr1 = resultArr.join("****")
  puts "resultArr : #{resultArr1}"
   
  ####################   add comments  ########################## 
  #####follow code is added in <set post_url >###
  #PATCH /repos/:owner/:repo/issues/comments/:id
  #`curl -X POST -s -u "#{username}:#{token}" -H "Content-Type: application/json" -d '{"body": "successful!"}' #{post_url}`
  if(resultArr.length!=0)
	  if(issyntax)
		  `curl -u "#{username}:#{password}" -X PATCH -d '{"body":"> **SYNTAX_ERROR**  : #{resultArr1}"}'  #{syntaxUrl}`
	  else
		  `curl -u "#{username}:#{password}" -X POST -d '{"body":"> **SYNTAX_ERROR**  : #{resultArr1}"}'  #{post_url}`
	  end
  else
	  if(issyntax)
		  `curl -u "#{username}:#{password}" -X PATCH -d '{"body":"> **SYNTAX CORRECT!**>"}'  #{syntaxUrl}`
	  else
		  `curl -u "#{username}:#{password}" -X POST -d '{"body":"> **SYNTAX CORRECT!**"}'  #{post_url}`
	  end
  end

  
 
	
  ####################    stop and print error in travis (red color)   #######################
  puts "\033[31m error begin---------------------------------------------------------------------------------------------------------\033[0m\n"
  #puts "\033[31m#{resultArr}\033[0m\n"
  resultArr.each{|x| puts "\033[31m#{x}\033[0m\n",""}
  puts "\033[31m error   end---------------------------------------------------------------------------------------------------------\033[0m\n"
  #raise "There is a syntax error on the above file. Fix it!"
  puts "resultArr: #{resultArr}"
	
	
  
  #############################        build         #########################
  puts "\033[42m gpg --list-keys\033[0m\n"
  system("gpg --list-keys")
  puts "\033[42msudo -s ./build-ubunturepo -c UP=0 BUILDALL=1;\033[0m\n"
  #buildresult = `sudo ./build-ubunturepo -c UP=0 BUILDALL=1 2>&1`
  buildresult = system("sudo ./build-ubunturepo -c UP=0 BUILDALL=1 >/tmp/build-log 2>&1")
  puts "buildresult: #{buildresult}"
  if(!buildresult)
    bLogLines = IO.readlines("/tmp/build-log")
    bLastIndex = bLogLines.size-1
    bLastLine = logLinesArr[bLastIndex]
    puts "lastline : -------------------\n"
    p bLastLine
    bLastLine.delete!('\'')
    bLastLine.delete!('\"')
    #bLastLine.delete!('\:')
    bLastLine.chomp!
    p bLastLine
    if(isbuild)
	    `curl -u "#{username}:#{password}" -X PATCH -d '{"body":"> **BUILD_ERROR**  :  #{bLastLine}"}'  #{buildUrl}`
    else
	    `curl -u "#{username}:#{password}" -X POST -d '{"body":"> **BUILD_ERROR**  :  #{bLastLine}"}'  #{post_url}`
    end
  else
    if(isbuild)
	    `curl -u "#{username}:#{password}" -X PATCH -d '{"body":"> **BUILD SUCCESSFUL!**"}'  #{buildUrl}`
    else
	    `curl -u "#{username}:#{password}" -X POST -d '{"body":"> **BUILD SUCCESSFUL!**"}'  #{post_url}`
    end
  end
  

=begin
  if(buildresult.include?("ERROR")||buildresult.include?("error"))
    errorindex = buildresult.rindex("ERROR")
    puts "errorindex : #{errorindex}"
    puts "error: #{buildresult}"
    `curl -u "#{username}:#{password}" -X POST -d '{"body":"> **BUILDERROR**  :  #{buildresult}"}'  #{post_url}`  
  end
=end


  ############################       install        ###########################
  #system("cd ..")
  #system("cd ..")
  #`cd ..`
  puts "\033[42mls -a \033[0m\n"
  system("ls -a")
  #system("cd xcat-core")
  puts "\033[42msudo ./mklocalrepo.sh\033[0m\n"
  system("sudo ./../../xcat-core/mklocalrepo.sh")
	
  puts "\033[42m sudo apt-get  install software-properties-common \033[0m\n"
  system("sudo apt-get  install software-properties-common")
	
  puts "\033[42m sudo wget -O - \"http://xcat.org/files/xcat/repos/apt/apt.key\" | sudo apt-key add - \033[0m\n"
  system('sudo wget -O - "http://xcat.org/files/xcat/repos/apt/apt.key" | sudo apt-key add -')
	
  system('sudo add-apt-repository "deb http://archive.ubuntu.com/ubuntu $(lsb_release -sc) main"')
  system('sudo add-apt-repository "deb http://archive.ubuntu.com/ubuntu $(lsb_release -sc)-updates main"')
  system('sudo add-apt-repository "deb http://archive.ubuntu.com/ubuntu $(lsb_release -sc) universe"')
  system('sudo add-apt-repository "deb http://archive.ubuntu.com/ubuntu $(lsb_release -sc)-updates universe"')
	
	
  system("sudo chmod 777 /etc/apt/sources.list")
  system('sudo echo "deb [arch=amd64] http://xcat.org/files/xcat/repos/apt/xcat-dep trusty main" >> /etc/apt/sources.list')
  system('sudo echo "deb [arch=ppc64el] http://xcat.org/files/xcat/repos/apt/xcat-dep trusty main" >> /etc/apt/sources.list')
  system("sudo cat /etc/apt/sources.list")
 
  
  `sudo apt-get clean all`
  puts "\033[42m sudo apt-get -qq update \033[0m\n"
  system("sudo apt-get -qq update")
  ##`sudo apt-get install xCAT --force-yes -y`
  puts "\033[42m sudo apt-get install xcat --force-yes \033[0m\n"
  installresult = system("sudo apt-get install xcat --force-yes >/tmp/install-log 2>&1")
  puts "installresult : #{installresult}"
  system("cat /tmp/install-log")
  if(!installresult)
    logLinesArr = IO.readlines("/tmp/install-log")
    lastIndex = logLinesArr.size-1
    lastLine = logLinesArr[lastIndex]
    puts "lastline : -------------------\n"
    p lastLine
    lastLine.delete!('\'')
    lastLine.delete!('\"')
    #lastLine.delete!('\:')
    lastLine.chomp!
    p lastLine
    if(isinstall)
	    `curl -u "#{username}:#{password}" -X PATCH -d '{"body":"> **INSTALL_ERROR**  :  #{lastLine}"}'  #{installUrl}`
    else
	    `curl -u "#{username}:#{password}" -X POST -d '{"body":"> **INSTALL_ERROR**  :  #{lastLine}"}'  #{post_url}`
    end
  else
     if(isinstall)
	     `curl -u "#{username}:#{password}" -X PATCH -d '{"body":"> **INSTALL SUCCESSFUL!**"}'  #{installUrl}`
     else
	     `curl -u "#{username}:#{password}" -X POST -d '{"body":"> **INSTALL SUCCESSFUL!**"}'  #{post_url}`
     end
  end


###########################    Verify xCAT Installation   ##################################
  puts "\033[42msource /etc/profile.d/xcat.sh\033[0m\n"
  system("source /etc/profile.d/xcat.sh")
  system("sudo echo $USER")
  #`sudo cat /opt/xcat/share/xcat/scripts/setup-local-client.sh`
  #`sudo -s /opt/xcat/share/xcat/scripts/setup-local-client.sh travis "" -f`
  puts "\033[42m sudo -s /opt/xcat/share/xcat/scripts/setup-local-client.sh -f travis \033[0m\n"
  system("sudo -s /opt/xcat/share/xcat/scripts/setup-local-client.sh -f travis")
  system("sudo -s /opt/xcat/sbin/chtab priority=1.1 policy.name=travis policy.rule=allow")
  puts "\033[42mlsxcatd -v\033[0m\n"
  system("lsxcatd -v")
  #puts lsxcatedresult
  #`sudo -s /opt/xcat/sbin/tabdump policy`
  #`sudo -s /opt/xcat/sbin/tabdump site`
  puts "\033[42mtabdump policy\033[0m\n"
  system("tabdump policy")
 
  puts "\033[42mtabdump site\033[0m\n"
  system("tabdump site")
  system("ls /opt/xcat/sbin")
  system("ls /opt/xcat")
  puts "\033[42m service xcatd start \033[0m\n"
  system("service xcatd start")
  puts "\033[42m service xcatd status \033[0m\n"
  system("service xcatd status")
  
end  #pull_request if






=begin
####################   add comments  ########################## 
number= "1"
#post_url = "https://api.github.com/repos/#{ower_repo}/issues/#{pull_number}/comments"
post_url = "https://api.github.com/repos/#{ower_repo}/issues/#{number}/comments"
puts post_url

`curl -u "#{username}:#{password}" -X POST -d '{"body":"hope this work2"}'  #{post_url}`

#echo "Add comment in issue $number"
#`curl -d '{"body":"successful"}' "#{post_url}"`
`curl -X POST -s -u "#{username}:#{token}" -H "Content-Type: application/json" -d '{"body": "successful!"}' #{post_url}`
#`curl -X POST \
#     -u #{token}:x-oauth-basic \
#     -H "Content-Type: application/json" \
#     -d "{\"body\": \"successful!\"}" \
#     https://api.github.com/repos/DengShuaiSimon/xcat-core/issues/1/comments`

=end
