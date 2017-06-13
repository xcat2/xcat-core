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




######################################  check syntax  ################################################
resultArr = Array.new
#print all path at current path
puts "work path : #{Dir.pwd}"
Find.find('/home/travis/build/DengShuaiSimon/xcat-core') do |path| 
  #puts path unless FileTest.directory?(path)  #if the path is not a directory,print it.
  #puts File.ftype(File.basename(path)) unless FileTest.directory?(path)
  if(File.file?(path))
    #puts "path : #{path}"
    #puts "file type : #{File.basename(path)[/\.[^\.]+$/]}"
    
    base_name = File.basename(path,".*")
    #puts "notype_basename : #{base_name}"
    file_type = path.split(base_name)
    #puts "file type : #{file_type[1]}"
    
    #puts "\n"
    if(file_type[1] == ".pm")
      puts "path : #{path}"
      result = %x[perl -I perl-xCAT/ -I ds-perl-lib -I xCAT-server/lib/perl/ -c #{path} 2>&1]
      #result = `perl -I perl-xCAT/ -I ds-perl-lib -I xCAT-server/lib/perl/ -c #{path} 2>&1`
      puts result
      puts "result[-3..-2] : #{result[-3..-2]}"

      if(result[-3..-2]!="OK")
        #p result
        resultArr.push(result)
      end

      puts "\n"
    end
  end
  
end 

puts "\033[31m error begin---------------------------------------------------------------------------------------------------------\033[0m\n"
#puts "\033[31m#{resultArr}\033[0m\n"
resultArr.each{|x| puts "\033[31m#{x}\033[0m\n",""}
puts "\033[31m error   end---------------------------------------------------------------------------------------------------------\033[0m\n"
#raise "There is a syntax error on the above file. Fix it!"




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
  
  # Remove digits
  #title = title.gsub!(/\D/, "")
  
  if(!(title =~ /^Add|Refine test case|cases for issue|feature(.*)/))
    raise "The title of this pull_request have a wrong format. Fix it!"
  end
  if(!(body =~ (/Add|Refine \d case|cases in this pull request(.*)/m))||!(body =~ (/This|These case|cases is|are added|refined for issue|feature(.*)/m))||!(body =~ (/This pull request is for task(.*)/m)))
    raise "The description of this pull_request have a wrong format. Fix it!"
  end
 
    
    
  ########################   add  comments   ###########################  
  post_url = "https://api.github.com/repos/#{ower_repo}/issues/#{pull_number}/comments"
  puts post_url
  post_uri = URI.parse(post_url)
  params = {} 
  params["body"] = 'successful'
  res = Net::HTTP.post_form(post_uri, params)  
  puts res.header['set-cookie'] 
  puts res.body
  
end
