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
if not con.send_output_setup(output_names, output_types, 125)
    logger.error('Unable to configure output')
end

if !con.send_start()
  logger.error('Unable to start synchronization')
end

begin
    # Loop indefinitely

    while true
      state = con.receive
      puts state
      sleep 2
    end
rescue Interrupt => e
    print_exception(e, true)
rescue SignalException => e
    print_exception(e, false)
rescue Exception => e
    print_exception(e, false)
end

p 'Disconnecting'
con.disconnect
puts con.connected?
