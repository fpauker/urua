#!/usr/bin/ruby
require 'urua'
### add stuff if necessary

Thread.abort_on_exception=true

Daemonite.new do |opts|
  ### add or replace building blocks if necessary
  use URUA::implementation_startup(opts)
  use URUA::implementation_run
  use URUA::implementation_exit
end.loop!
