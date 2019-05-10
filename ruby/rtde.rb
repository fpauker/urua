#!/usr/bin/env ruby
require 'socket'        # Sockets are in standard library

module Command
  RTDE_REQUEST_PROTOCOL_VERSION = 86        # ASCII V
  RTDE_GET_URCONTROL_VERSION = 118           # ASCII V
  RTDE_TEXT_MESSAGE = 77                    # ASCII M
  RTDE_DATA_PACKAGE = 85                    # ASCII U
  RTDE_CONTROL_PACKAGE_SETUP_OUTPUTS = 79   # ASCII O
  RTDE_CONTROL_PACKAGE_SETUP_INPUTS = 73    # ASCII I
  RTDE_CONTROL_PACKAGE_START = 83           # ASCII S
  RTDE_CONTROL_PACKAGE_PAUSE = 80           # ascii p
end

module ConnectionState
  DISCONNECTED = 0
  CONNECTED = 1
  STARTED = 2
  PAUSED = 3
end

class RTDEException < RuntimeException; end

class Rtde
  RTDE_PROTOCOL_VERSION = 2
  def initialize(hostname, port)
    @hostname = hostname
    @port = port
    @conn_state = ConnectionState::DISCONNECTED
    @sock = nil
    @output_config = nil
    @input_config = {}
  end

  def connect
  #connect to robot controller using the rtde socket
    return if @sock

    @buf = 'b' # buffer data in binary format
    #self.__sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    #self.__sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    #self.__sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    #self.__sock.settimeout(DEFAULT_TIMEOUT)
    @sock = TCPSocket.open(@hostname, @port)
    @conn_state = ConnectionState::CONNECTED
  end

  def disconnect
    if @sock
      @sock.close
      @sock = nil
      @conn_state = ConnectionState::DISCONNECTED
    end
  end

  def is_connected
    @conn_state
  end

  def get_controller_version
    cmd = Command.rtde_get_urcontrol_version
  end
end

rtde = Rtde. new("192.168.56.1",30004)
rtde.connect
