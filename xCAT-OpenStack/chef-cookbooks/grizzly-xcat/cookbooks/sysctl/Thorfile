# encoding: utf-8

require 'bundler'
require 'bundler/setup'
require 'thor/foodcritic'
require 'berkshelf/thor'

begin
  require 'kitchen/thor_tasks'
  Kitchen::ThorTasks.new
rescue LoadError
  puts ">>>>> Kitchen gem not loaded, omitting tasks" unless ENV['CI']
end

class Tailor < Thor
  require 'tailor/cli'

  desc "lint", "check style"
  def lint
     ::Tailor::Logger.log = false
     tailor = ::Tailor::CLI.new []
     tailor.execute!
  end
end
