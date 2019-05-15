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

class RtdeException < Exception; end

class Rtde
  RTDE_PROTOCOL_VERSION = 2   #moved to Rtde class
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

    @buf = '' # buffer data in binary format
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

  def connected?
    @conn_state != ConnectionState::DISCONNECTED
  end

  def get_controller_version
    cmd = Command::RTDE_GET_URCONTROL_VERSION
    version = sendAndReceive cmd
    if version
      logger.info 'Controller version' + version.major
      if version.major == 3 && version.minor <=2 && version.bugfix < 19171
        logger.error 'Upgrade your controller to version 3.2.19171 or higher'
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
    sendAndReceive cmd, payload
  end

  def send_input_setup(variables, types=[])
    cmd = Command::RTDE_CONTROL_PACKAGE_SETUP_INPUTS
    payload = variables.join ','
    result = sendAndReceive cmd, payload
    if types.length != 0 && result.types != types
      logger.error(
        'Data type inconsistency for input setup: ' +
        types.to_s + ' - ' +
        result.types.to_s
      )
      return nil
    end

    result.names = variables
    @input_config[result.id] = result
    Serialize::DataObject.create_empty variables, result.id
  end

  def send_output_setup(variables, types=[], frequency = 125)
    cmd = Command::RTDE_CONTROL_PACKAGE_SETUP_OUTPUTS
    payload = [frequency].pack 'G'
    payload = payload + variables.join ','
    result = sendAndReceive cmd, payload
    if types.length != 0 and not result.types != types
      logger.error(
        'Data type inconsistency for output setup: ' +
        types.to_s + ' - ' +
        result.types.to_s
      )
      return false
    end
    result.names = variables
    @output_config = result
    return true
  end

  def send_start
    cmd = Command::RTDE_CONTROL_PACKAGE_START
    if sendAndReceive cmd
      logger.info 'RTDE synchronization started'
      @conn_state = ConnectionState::STARTED
      true
    else
      logger.error 'RTDE synchronization failed to start'
      false
    end
  end

  def send_pause
    cmd = Command::RTDE_CONTROL_PACKAGE_PAUSE
    sucess = sendAndReceive(cmd)
    if success
      logger.info 'RTDE synchronization paused'
      @conn_state = ConnectionState::PAUSED
    else
      logger.error('RTDE synchronization failed to pause')
    end
    success
  end

  def send(input_data)
    if @conn_state != ConnectionState::STARTED
      logger.error 'Cannot send when RTDE synchroinization is inactive'
      return
    end
    if not @input_config.key?(input_data.recipe_id)
      logger.error 'Input configuration id not found: ' + @input_data.recipe_id
      return
    end
    config = @input_config[input_data.recipe_id]
    sendall Command::RTDE_DATA_PACKAGE, config.pack(input_data)
  end

  def receive
    return nil if @output_config
    return nil if @conn_state != ConnectionState::STARTED
    recv Command::RTDE_DATA_PACKAGE
  end

  def send_message(message, source = 'Ruby Client', type = Serialize::Message::INFO_MESSAGE)
    cmd = Command::RTDE_TEXT_MESSAGE
    fmt = 'Ca%dCa%dC' % (message.length, source.length)
    payload = struct.pack(fmt, message.length, message, source.length, source, type)
    sendall(cmd, payload)
  end

  def on_packet(cmd, payload)
    return unpack_protocol_version_package(payload)    if cmd == Command::RTDE_REQUEST_PROTOCOL_VERSION
    return unpack_urcontrol_version_package(payload)   if cmd == Command::RTDE_GET_URCONTROL_VERSION
    return unpack_text_message(payload)                if cmd == Command::RTDE_TEXT_MESSAGE
    return unpack_setup_outputs_package(payload)       if cmd == Command::RTDE_CONTROL_PACKAGE_SETUP_OUTPUTS
    return unpack_setup_inputs_package(payload)        if cmd == Command::RTDE_CONTROL_PACKAGE_SETUP_INPUTS
    return unpack_start_package(payload)               if cmd == Command::RTDE_CONTROL_PACKAGE_START
    return unpack_pause_package(payload)               if cmd == Command::RTDE_CONTROL_PACKAGE_PAUSE
    return unpack_data_package(payload, output_config) if cmd == Command::RTDE_DATA_PACKAGE
    logger.error 'Unknown package command' + cmd.to_s
  end

  def sendAndReceive(cmd, payload)
    sendall(cmd, payload) ? recv(cmd) : nil
  end

  def sendall(command, payload)
    fmt = 'S>C'
    size = ([0,0].pack fmt).length + payload.length
    if @sock
      logger.error('Unable to send: not connected to Robot')
      return false
    end

    _, writable, _ = IO.select([], [@sock], [])
    if writable.length > 0
      @sock.sendall(buf)
      true
    else
      trigger_disconnected
      false
    end
  end

  def has_data
    timeout = 0
    readable, _, _ = IO.select([@sock], [], [], timeout)
    readable.length != 0
  end

  def recv(command)
    while connected?
      readable, _, xlist = IO.select([@sock], [], [@sock])
      if len(readable):
        more = @sock.recv(4096)
        if len(more) == 0
          trigger_disconnected
          return nil
        end
        @buf += more
      end

      if xlist.length > 0 || readable.length == 0
        logger.info 'lost connection with controller'
        trigger_disconnected
        return nil
      end

      while @buf.length >= 3
        packet_header = Serialize::ControlHeader.unpack(@buf)
        if @buf.length >= packet_header.size
          packet, @buf = @buf[3..packet_header.size], @buf[packet_header.size..-1]
          data = on_packet(packet_header.command, packet)
          if @buf.length >= 3 && command == Command.RTDE_DATA_PACKAGE:
            next_packet_header = Serialize::ControlHeader.unpack(@buf)
            if next_packet_header.command == command
              logger.info 'skipping package(1)'
              continue
            end
          end
          if packet_header.command == command
            return data
          else
            logger.info 'skipping package(2)'
          end
        else
          break
				end
			end
		end
    return nil
  end

	def trigger_disconnected
		logger.info 'RTDE disconnected'
		disconnect
	end

	def unpack_protocol_version_package(payload)
		return nil if payload.length != 1
		Serialize::ReturnValue.unpack(payload).success
	end

	def unpack_urcontrol_version_package(payload)
		return nil if payload.length != 16
		Serialize::ControlVersion.unpack payload
	end

	def unpack_text_message(payload)
		return nil if payload.length < 1
		msg = Serialize::Message.unpack payload
		logger.error  (msg.source + ':' + msg.message) if msg.level == Serialize::Message::EXCEPTION_MESSAGE || msg.level == Serialize::Message::ERROR_MESSAGE
		logger.warning(msg.source + ':' + msg.message) if msg.level == Serialize::Message::WARNING_MESSAGE
		logger.info   (msg.source + ':' + msg.message) if msg.level == Serialize::Message::INFO_MESSAGE
	end

	def unpack_setup_outputs_package(payload)
		if payload.length < 1
			logger.error 'RTDE_CONTROL_PACKAGE_SETUP_OUTPUTS: No payload'
			return nil
		end
		Serialize::DataConfig.unpack_recipe payload
	end

	def unpack_setup_inputs_package(payload)
		if payload.length < 1
			logger.error 'RTDE_CONTROL_PACKAGE_SETUP_INPUTS: No payload'
			return nil
		end
		Serialize::DataConfig.unpack_recipe payload
	end

	def unpack_start_package(payload)
		if payload.length != 1
			logger.error 'RTDE_CONTROL_PACKAGE_START: Wrong payload size'
			return nil
		end
		Serialize::ReturnValue.unpack(payload).success
	end

	def unpack_pause_package(payload)
		if payload.length != 1
			logger.error 'RTDE_CONTROL_PACKAGE_PAUSE: Wrong payload size'
			return nil
		end
		Serialize::ReturnValue.unpack(payload).success
	end

	def unpack_data_package(payload)
		if payload.length < 1
			logger.error 'RTDE_DATA_PACKAGE: Missing output configuration'
			return nil
		end
		output.config.unpack payload
	end

end
