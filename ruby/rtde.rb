#!/usr/bin/env ruby
require 'socket'        # Sockets are in standard library
require 'logger'
require 'serialize'

logger = Logger.new STDOUT

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

class RTDEException < Exception; end

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
    #get controller version
    cmd = Command::RTDE_GET_URCONTROL_VERSION
    version = sendAndReceive(cmd)
    if version
      logger.info('Controller version' + version.major)
      if version.major == 3 && version.minor <=2 && version.bugfix < 19171
        logger.error 'Upgrade your controller to versino 3.2.19171 or higher'
        exit
      end
      version.major, version.minor, version.bugfix, version.build
    else
      nil, nil, nil, nil
    end
  end

  def negotiate_protocol_version
    cmd = Command::RTDE_REQUEST_PROTOCOL_VERSION
    payload = [RTDE_PROTOCOL_VERSION].pack 'S>'
    sucess = sendAndReceive cmd, payload
  end

  def send_input_setup variables, types=[]
    #rework necessary
    cmd = Command::RTDE_CONTROL_PACKAGE_SETUP_INPUTS
    payload = variables.join ','
    result = sendAndReceive cmd, payload
    return nil if types.len <> 0 && !  result.types == types

    result.names = variables
    @input_config[result.id] = result
    #DataObject.create_empty variables result.id
  end

  def send_output_setup variables, types=[], frequency = 125
    #rework necessary
    cmd = Command::RTDE_CONTROL_PACKAGE_SETUP_OUTPUTS
    payload = [frequency].pack 'G'
    payload = payload + variables.join ','
    result = sendAndReceive cmd, payload
    #if len(types)!=0 and not self.__list_equals(result.types, types):
    #    logging.error('Data type inconsistency for output setup: ' +
    #             str(types) + ' - ' +
    #             str(result.types))
    #    return False
    result.names = variables
    @output_config = result
    return TRUE
  end

  def send_start
    cmd = Command::RTDE_CONTROL_PACKAGE_START
    sucess = sendAndReceive(cmd)
    if success
      logger.info('RTDE synchronization started')
      @conn_state = ConnectionState::STARTED
    else
      logger.error('RTDE synchronization failed to start')
    end
    success
  end

  def send_pause
    cmd = Command::RTDE_CONTROL_PACKAGE_PAUSE
    sucess = sendAndReceive(cmd)
    if success
      logger.info('RTDE synchronization paused')
      @conn_state = ConnectionState::PAUSED
    else
      logger.error('RTDE synchronization failed to pause')
    end
    success
  end

  def send input_data
    if @conn_state != ConnectionState::STARTED
      logger.error 'Cannot send when RTDE synchroinization is inactive'
      return
    end
    if not @input_config.key?(input_data.recipe_id)
      logger.error 'Input configuration id not found: ' + @input_data.recipe_id
      return
    end
  config = @input_config[input_data.recipe_id]
  sendall Command::RTDE_DATA_PACKAGE, config.pack input_data #not sure if this is correct
  end



end
