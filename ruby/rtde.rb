#!/usr/bin/env ruby
require 'socket'        # Sockets are in standard library

class Command
  @rtde_request_protocol_version = 86        # ascii V
  @rtde_get_urcontrol_version = 118           # ascii v
  @rtde_text_message = 77                    # ascii m
  @rtde_data_package = 85                    # ascii u
  @rtde_control_package_setup_outputs = 79   # ascii o
  @rtde_control_package_setup_inputs = 73    # ascii i
  @rtde_control_package_start = 83           # ascii s
  @rtde_control_package_pause = 80           # ascii p
  class << self
    attr_reader :rtde_request_protocol_version
    attr_reader :rtde_get_urcontrol_version
    attr_reader :rtde_text_message
    attr_reader :rtde_data_package
    attr_reader :rtde_control_package_setup_outputs
    attr_reader :rtde_control_package_setup_inputs
    attr_reader :rtde_control_package_start
    attr_reader :rtde_control_package_pause
  end
end

#_RTDE_PROTOCOL_VERSION = 2

class ConnectionState
  @disconnected = 0
  @connected = 1
  @started = 2
  @paused = 3
  class << self
    attr_reader :disconnected
    attr_reader :connected
    attr_reader :started
    attr_reader :paused
   end
end

#class RTDEException(Exception):
#    def __init__(self, msg):
#        self.msg = msg
#    def __str__(self):
#        return repr(self.msg)

class Rtde
  def initialize(hostname, port)
    @hostname = hostname
    @port = port
    @conn_state = ConnectionState.disconnected
    @sock = nil
    @output_config = nil
    @input_config = {}
  end

  def hello
    puts "hello"
  end

  def connect
  #connect to robot controller using the rtde socket
    if @sock
      return
    end

    @buf = 'b' # buffer data in binary format
    #self.__sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    #self.__sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    #self.__sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    #self.__sock.settimeout(DEFAULT_TIMEOUT)
    @sock = TCPSocket.open(hostname, port)
    @sock = ConnectionState.connected
  end

  def disconnect
    if @sock
      @sock.close
      @sock = nil
      @conn_state = ConnectionState.disconnected
    end
  end
  def get_controller_version
    cmd = Command.rtde_get_urcontrol_version
  end
end

rtde = Rtde. new("192.168.56.1",30004)
rtde.connect
