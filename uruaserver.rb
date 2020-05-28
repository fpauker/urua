#!/usr/bin/ruby
# require 'opcua/server'
require_relative '../opcua-smart/lib/opcua/server'
require_relative '../ur-sock/lib/ur-sock'
# require 'ur-sock'
require 'net/ssh'
require 'net/scp'

Thread.abort_on_exception=true

def add_axis_concept(context, item) #{{{
  context.add_variables item, :Axis1, :Axis2, :Axis3, :Axis4, :Axis5, :Axis6
end #}}}

def split_vector6_data(vector, item, nodes) #{{{
  # aqd = data['actual_qd'].to_s
  item.value = vector.to_s
  va = vector.to_s[1..-2].split(',')
  nodes.each_with_index do |a, i|
    a.value = vector[i].to_f
  end
  [vector.to_s, va]
end #}}}

def start_dash(opts) #{{{
  opts['dash'] = UR::Dash.new(opts['ipadress']).connect rescue nil
end #}}}

def start_rtde(opts) #{{{
  ### Loading config file
  conf = UR::XMLConfigFile.new opts['rtde_config']
  output_names, output_types = conf.get_recipe opts['rtde_config_recipe_base']

  opts['rtde'] = UR::Rtde.new(opts['ipadress']).connect
  ### Set Speed to very slow
  if opts['rtde_config_recipe_speed']
    speed_names, speed_types = conf.get_recipe opts['rtde_config_recipe_speed']
    opts['speed'] = opts['rtde'].send_input_setup(speed_names, speed_types)
    opts['speed']['speed_slider_mask'] = 1
    opts['ov'].value = opts['speed']['speed_slider_fraction'].to_i
  end

  ### Setup output
  if not opts['rtde'].send_output_setup(output_names, output_types,10)
    puts 'Unable to configure output'
  end
  if not opts['rtde'].send_start
    puts 'Unable to start synchronization'
  end
end #}}}

def protect_reconnect_run(opts) #{{{
  tries = 0
  begin
    yield
  rescue UR::Dash::Reconnect => e
    tries += 1
    if tries < 2
      start_dash opts
      opts['mo'].value = false
      retry
    end
  end
end #}}}

def ssh_start(opts)
  opts['ssh'] = opts['password'] ? Net::SSH.start(opts['ipadress'], opts['username'], password: opts['password']) : Net::SSH.start(opts['ipadress'], opts['username'])
end

def download_program(opts,name)
  counter = 0
  begin
    opts['ssh'].scp.download File.join(opts['url'],name)
  rescue => e
    counter += 1
    ssh_start opts
    retry if counter < 3
  end
end
def upload_program(opts,name,program)
  counter = 0
  begin
    opts['ssh'].scp.upload StringIO.new(program), File.join(opts['url'],name)
  rescue => e
    counter += 1
    ssh_start opts
    retry if counter < 3
  end
  nil
end

def get_robot_programs(opts)
  progs = []
  begin
    progs = opts['ssh'].exec!('ls ' + File.join(opts['url'],'*.urp') + ' 2>/dev/null').split("\n")
    progs.shift if progs[0] =~ /^bash:/
  rescue => e
    ssh_start opts
  end
  progs
end

Daemonite.new do
  on startup do |opts|
    opts['server'] = OPCUA::Server.new
    opts['server'].add_namespace opts['namespace']
    opts['dash'] = nil
    opts['rtde'] = nil
    opts['programs'] = nil

    # ProgramFile
    opts['pf'] = opts['server'].types.add_object_type(:ProgramFile).tap{ |p|
      p.add_method :SelectProgram do |node|
        a = node.id.to_s.split('/')
        protect_reconnect_run(opts) do
          opts['dash'].load_program(a[-2])
        end
      end
      p.add_method :StartProgram do |node|
        a = node.id.to_s.split('/')
        protect_reconnect_run(opts) do
          opts['dash'].load_program(a[-2])
          opts['dash'].start_program
        end
      end
    }
    # TCP ObjectType
    tcp = opts['server'].types.add_object_type(:Tcp).tap{ |t|
      t.add_object(:ActualPose, opts['server'].types.folder).tap { |p| add_axis_concept p, :TCPPose }
      t.add_object(:ActualSpeed, opts['server'].types.folder).tap{ |p| add_axis_concept p, :TCPSpeed }
      t.add_object(:ActualForce, opts['server'].types.folder).tap{ |p| add_axis_concept p, :TCPForce }
    }
    # AxisObjectType
    ax = opts['server'].types.add_object_type(:AxisType).tap { |a|
      a.add_object(:ActualPositions, opts['server'].types.folder).tap { |p| add_axis_concept p, :AxisPositions }
      a.add_object(:ActualVelocities, opts['server'].types.folder).tap{ |p| add_axis_concept p, :AxisVelocities }
      a.add_object(:ActualCurrents, opts['server'].types.folder).tap  { |p| add_axis_concept p, :AxisCurrents }
      a.add_object(:ActualVoltage, opts['server'].types.folder).tap   { |p| add_axis_concept p, :AxisVoltage }
      a.add_object(:ActualMomentum, opts['server'].types.folder).tap  { |p| p.add_variable :AxisMomentum }
    }

    # RobotObjectType
    rt = opts['server'].types.add_object_type(:RobotType).tap { |r|
      r.add_object(:State, opts['server'].types.folder).tap{ |s|
        s.add_variables :CurrentProgram, :RobotMode, :RobotState, :JointMode, :SafetyMode, :ToolMode, :ProgramState, :SpeedScaling, :Remote
        s.add_variable_rw :Override
      }
      r.add_object(:SafetyBoard, opts['server'].types.folder).tap{ |r|
        r.add_variables :MainVoltage, :RobotVoltage, :RobotCurrent
      }
      r.add_object(:Programs, opts['server'].types.folder).tap{ |p|
        p.add_object :Program, opts['pf'], OPCUA::OPTIONAL
        p.add_variable :Programs
        opts['file'] = p.add_variable :File
        p.add_method :UploadProgram, name: OPCUA::TYPES::STRING, program: OPCUA::TYPES::STRING do |node, name, program|
          upload_program opts, name, program
        end
        p.add_method :DownloadProgram, name: OPCUA::TYPES::STRING, return:  OPCUA::TYPES::STRING do |node,name|
          download_program opts, name
        end
      }
      r.add_method :SelectProgram, name: OPCUA::TYPES::STRING do |node, name|
        protect_reconnect_run(opts) do
          opts['dash'].load_program(name)
        end
      end
      r.add_method :StartProgram do
        protect_reconnect_run(opts) do
          nil unless opts['dash'].start_program
        end
      end
      r.add_method :StopProgram do
        protect_reconnect_run(opts) do
          opts['dash'].stop_program
        end
      end
      r.add_method :PauseProgram do
        protect_reconnect_run(opts) do
          opts['dash'].pause_program
        end
      end
      r.add_method :PowerOn do
        if opts['rm'].value.to_s != 'Running'
          Thread.new do
            sleep 0.5 until opts['rm'].value.to_s == 'Idle'
            protect_reconnect_run(opts) do
              puts 'break released' if opts['dash'].break_release
            end
          end
        end
      end
      r.add_method :PowerOff do
        protect_reconnect_run(opts) do
          opts['dash'].power_off
        end
      end
      r.add_object(:RobotMode, opts['server'].types.folder).tap{ |r|
        r.add_method :AutomaticMode do
          opts['dash'].set_operation_mode_auto
        end
        r.add_method :ManualMode do
          opts['dash'].set_operation_mode_manual
        end
        r.add_method :ClearMode do
          opts['dash'].clear_operation_mode
        end
      }

      r.add_object(:Messaging, opts['server'].types.folder).tap{ |r|
        r.add_method :PopupMessage, message: OPCUA::TYPES::STRING do |node, message|
          opts['dash'].open_popupmessage(message)
        end
        r.add_method :ClosePopupMessage do
          opts['dash'].close_popupmessage
        end
        r.add_method :AddToLog, message: OPCUA::TYPES::STRING do |node, message|
          opts['dash'].add_to_log(message)
        end
        r.add_method :CloseSafetyPopup do
          protect_reconnect_run(opts) do
            opts['dash'].close_safety_popup
          end
        end
      }
    }
    ### populating the adress space
    ### Robot object
    robot = opts['server'].objects.manifest(:UR10e, rt)

    ### SafetyBoard
    sb = robot.find(:SafetyBoard)
    opts['mv'] = sb.find(:MainVoltage)
    opts['rv'] = sb.find(:RobotVoltage)
    opts['rc'] = sb.find(:RobotCurrent)

    ### StateObject
    st = robot.find(:State)
    opts['rm'] = st.find(:RobotMode)
    opts['sm'] = st.find(:SafetyMode)
    opts['jm'] = st.find(:JointMode)
    opts['tm'] = st.find(:ToolMode)
    opts['ps'] = st.find(:ProgramState)
    opts['rs'] = st.find(:RobotState)
    opts['cp'] = st.find(:CurrentProgram)
    opts['ov'] = st.find(:Override)
    opts['ss'] = st.find(:SpeedScaling)
    opts['mo'] = st.find(:Remote)

    ### Axes
    axes = robot.manifest(:Axes, ax)
    aapf, avelf, acurf, avolf, amomf = axes.find :ActualPositions, :ActualVelocities, :ActualCurrents, :ActualVoltage, :ActualMomentum

    ### Positions
    opts['aap']  = aapf.find :AxisPositions
    opts['aapa'] = aapf.find :Axis1, :Axis2, :Axis3, :Axis4, :Axis5, :Axis6
    ### Velocities
    opts['avel']  = avelf.find :AxisVelocities
    opts['avela'] = avelf.find :Axis1, :Axis2, :Axis3, :Axis4, :Axis5, :Axis6
    ### Currents
    opts['acur']  = acurf.find :AxisCurrents
    opts['acura'] = acurf.find :Axis1, :Axis2, :Axis3, :Axis4, :Axis5, :Axis6
    ### Voltage
    opts['avol']  = avolf.find :AxisVoltage
    opts['avola'] = avolf.find :Axis1, :Axis2, :Axis3, :Axis4, :Axis5, :Axis6
    ### Momentum
    opts['amom'] = amomf.find :AxisMomentum
    ### TCP
    tcp = robot.manifest(:Tcp, tcp)
    apf, asf, aff = tcp.find :ActualPose, :ActualSpeed, :ActualForce
    ### TCP Pose
    opts['ap']  = apf.find :TCPPose
    opts['apa'] = apf.find :Axis1, :Axis2, :Axis3, :Axis4, :Axis5, :Axis6
    ### TCP Speed
    opts['as']  = asf.find :TCPSpeed
    opts['asa'] = asf.find :Axis1, :Axis2, :Axis3, :Axis4, :Axis5, :Axis6
    ### TCP Force
    opts['af']  = aff.find :TCPForce
    opts['afa'] = aff.find :Axis1, :Axis2, :Axis3, :Axis4, :Axis5, :Axis6

    ### Connecting to universal robot
    start_rtde opts
    start_dash opts

    ### Manifest programs
    opts['programs'] = robot.find(:Programs)
    opts['prognodes'] = {}
    opts['progs'] = []
    opts['semaphore'] = Mutex.new
    ### check if interfaces are ok
    raise if !opts['dash'] || !opts['rtde'] ##### TODO, don't return, raise

    # functionality for threading in loop
    opts['doit_state'] = Time.now.to_i
    opts['doit_progs'] = Time.now.to_i
    opts['doit_rtde'] = Time.now.to_i
  rescue => e
    puts e.message
    puts e.backtrace
    raise
  end

  run do |opts|
    opts['server'].run

    if Time.now.to_i - 1 > opts['doit_state']
      opts['doit_state'] = Time.now.to_i
      opts['cp'].value = opts['dash'].get_loaded_program
      opts['rs'].value = opts['dash'].get_program_state
    end

    if Time.now.to_i - 10 > opts['doit_progs']
      opts['doit_progs'] = Time.now.to_i
      Thread.new do
        opts['semaphore'].synchronize do
          # Content of thread
          # check every 10 seconds for new programs
          progs = get_robot_programs(opts)
          delete = opts['progs'] - progs
          # puts 'Missing Nodes: ' + delete.to_s
          delete.each do |d|
            d = d[0..-5]
            opts['prognodes'][d].delete!
            opts['prognodes'].delete(d)
          end
          add = progs - opts['progs']
          # puts 'New nodes: ' + add.to_s
          add.each do |a|
            a = a[0..-5]
            opts['prognodes'][a] = opts['programs'].manifest(a, opts['pf'])
          end
          opts['progs'] = progs.dup
          opts['programs'].find(:Programs).value = opts['progs']
          opts['mo'].value = true
        end unless opts['semaphore'].locked?
      end
    end

    data = opts['rtde'].receive
    if data
      # robot object
      opts['mv'].value = data['actual_main_voltage']
      opts['rv'].value = data['actual_robot_voltage']
      opts['rc'].value = data['actual_robot_current']
      opts['ss'].value = data['speed_scaling']

      # State objects
      opts['rm'].value = UR::Rtde::ROBOTMODE[data['robot_mode']]
      opts['sm'].value = UR::Rtde::SAFETYMODE[data['safety_mode']]
      opts['jm'].value = UR::Rtde::JOINTMODE[data['joint_mode']]
      opts['tm'].value = UR::Rtde::TOOLMODE[data['tool_mode']]
      opts['ps'].value = UR::Rtde::PROGRAMSTATE[data['runtime_state']]

      # Axes object
      split_vector6_data(data['actual_q'],opts['aap'], opts['aapa']) # actual jont positions
      split_vector6_data(data['actual_qd'],opts['avel'], opts['avela']) # actual joint velocities
      split_vector6_data(data['actual_joint_voltage'],opts['avol'], opts['avola']) # actual joint voltage
      split_vector6_data(data['actual_current'],opts['acur'], opts['acura']) # actual current
      opts['amom'].value = data['actual_momentum'].to_s # actual_momentum

      # TCP object
      split_vector6_data(data['actual_qd'],opts['ap'], opts['apa']) # Actual TCP Pose
      split_vector6_data(data['actual_qd'],opts['as'], opts['asa']) # Actual TCP Speed
      split_vector6_data(data['actual_qd'],opts['af'], opts['afa']) # Actual TCP Force

      # Write values
      if opts['rtde_config_recipe_speed']
        opts['speed']['speed_slider_fraction'] = opts['ov'].value / 100.0
        opts['rtde'].send(opts['speed'])
      end
    else
      if Time.now.to_i - 10 > opts['doit_rtde']
        opts['doit_rtde'] = Time.now.to_i
        start_rtde opts
      end
    end

  rescue Errno::ECONNREFUSED => e
    puts 'ECONNREFUSED:'
    puts e.message
  rescue UR::Dash::Reconnect => e
    start_dash opts
    opts['mo'].value = false
  rescue => e
    unless opts['dash']
      start_dash opts
    end
    p e.message
    p e.backtrace
  end
  on exit do
    # reserved for important stuff
    p 'bye'
  end
end.loop!
