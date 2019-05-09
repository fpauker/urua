require 'socket'        # Sockets are in standard library

class Command
    _RTDE_REQUEST_PROTOCOL_VERSION = 86        # ascii V
    _RTDE_GET_URCONTROL_VERSION = 118          # ascii v
    _RTDE_TEXT_MESSAGE = 77                    # ascii M
    _RTDE_DATA_PACKAGE = 85                    # ascii U
    _RTDE_CONTROL_PACKAGE_SETUP_OUTPUTS = 79   # ascii O
    _RTDE_CONTROL_PACKAGE_SETUP_INPUTS = 73    # ascii I
    _RTDE_CONTROL_PACKAGE_START = 83           # ascii S
    _RTDE_CONTROL_PACKAGE_PAUSE = 80           # ascii P
end

RTDE_PROTOCOL_VERSION = 2

class ConnectionState
    _DISCONNECTED = 0
    _CONNECTED = 1
    _STARTED = 2
    _PAUSED = 3
end

#class RTDEException(Exception):
#    def __init__(self, msg):
#        self.msg = msg
#    def __str__(self):
#        return repr(self.msg)

class RTDE
  def initialize(hostname, port)
    @hostname = hostname
    @port = port
    @conn_state = ConnectionState._DISCONNECTED
    @sock = nil
    @output_config = nil
    @input_config = {}
   end

   def connected

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
     @sock = ConnectionState._CONNECTED
   end

   def disconnect
     if @sock
       @sock.close
       @sock = nil
    @conn_state = ConnectionState._DISCONNECTED


end
