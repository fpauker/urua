#!/usr/bin/env ruby

require 'logger'
require_relative 'rtde'
require_relative 'rtde_conf'

conf = ConfigFile.new "record_configuration.xml"
output_names, output_types = conf.get_recipe('out')

con = Rtde.new '192.168.56.101', 30004
con.connect
puts con.connected?



version = con.get_controller_version

if  not con.send_output_setup(output_names, output_types, 125)
    puts('Unable to configure output')
end

if not con.send_start()
  puts('Unable to start synchronization')
end

begin
    # Loop indefinitely

    while true
      state = con.receive
      if state
        puts state
      end
    end
rescue Interrupt => e
    print_exception(e, true)
rescue SignalException => e
    print_exception(e, false)
rescue Exception => e
    print_exception(e, false)
end

p 'Disconnecting'
con.send_pause
con.disconnect
puts con.connected?
