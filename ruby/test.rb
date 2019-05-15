#!/usr/bin/env ruby

require 'logger'
require_relative 'rtde'


con = Rtde.new '192.168.56.101', 30004
con.connect
puts con.connected?

version = con.get_controller_version

puts version.to_s
p 'Disconnecting'
con.disconnect
puts con.connected?
