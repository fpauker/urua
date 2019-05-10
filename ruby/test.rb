#!/usr/bin/env ruby

require 'logger'
require_relative 'rtde'


rtde = Rtde.new '192.168.56.101', 30004
rtde.connect
puts 'done!'
