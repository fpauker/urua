#!/usr/bin/ruby
#require 'opcua/server'
require_relative '../opcua-smart/lib/opcua/server'
require_relative '../ur-sock/lib/ur-sock'
#require 'ur-sock'
require 'net/ssh'

def add_axis_concept(context,item)
  context.add_variables item, :Axis1, :Axis2, :Axis3, :Axis4, :Axis5, :Axis6
end

def split_vector6_data(vector, item, nodes)
  #aqd = data['actual_qd'].to_s
  item.value = vector.to_s
  va = vector.to_s[1..-2].split(",")
  nodes.each_with_index do |a,i|
    a.value = vector[i].to_f
  end
  [vector.to_s, va]
end

def get_robot_programs(ipadress, username, password, url)
  #parsing file system
  #puts 'Manifest'
  ssh = Net::SSH.start(ipadress, username, password: password )
  #folder = ssh.exec!("ls "+url).split("\n")
  #puts folder
  #folder.each do |f|
  programs = ssh.exec!( "ls "+url+" | grep .urp" ).split( "\n" )
  #end
end

Daemonite.new do
  on startup do |opts|
    opts['server'] = OPCUA::Server.new
    opts['server'].add_namespace "https://centurio.work/ur10evva"
    #opts['ipadress'] = '192.168.56.101'
    opts['ipadress'] = 'localhost'
    opts['username'] = 'paukerf87'
    opts['password'] = nil
    #opts['url'] = url = "/home/ur/ursim-current/programs.UR10"
    opts['url'] = url = "/home/paukerf87/projects/ursim-5.3.1.64192/programs.UR5"

    opts['dash'] = nil
    opts['rtde'] = nil
    opts['programs'] = nil


    #ProgramFile
    pf = opts['server'].types.add_object_type(:ProgramFile).tap{|p|
      p.add_method :SelectProgram do |node|
        a = node.id.to_s.split('/')
        opts['dash'].load_program(a[a.size-2].to_s[0..-5])
      end
      p.add_method :StartProgram do
        opts['dash'].start_program
      end
      p.add_method :StopProgram do
        opts['dash'].stop_program
      end
      p.add_method :PauseProgram do
        opts['dash'].pause_program
      end
    }
    #TCP ObjectType
    tcp = opts['server'].types.add_object_type(:Tcp).tap{ |t|
      t.add_object(:ActualPose, opts['server'].types.folder).tap { |p| add_axis_concept p, :TCPPose }
      t.add_object(:ActualSpeed, opts['server'].types.folder).tap{ |p| add_axis_concept p, :TCPSpeed }
      t.add_object(:ActualForce, opts['server'].types.folder).tap{ |p| add_axis_concept p, :TCPForce }
    }
    #AxisObjectType
    ax = opts['server'].types.add_object_type(:AxisType).tap{|a|
      a.add_object(:ActualPositions, opts['server'].types.folder).tap { |p| add_axis_concept p, :AxisPositions }
      a.add_object(:ActualVelocities, opts['server'].types.folder).tap{ |p| add_axis_concept p, :AxisVelocities }
      a.add_object(:ActualCurrents, opts['server'].types.folder).tap  { |p| add_axis_concept p, :AxisCurrents }
      a.add_object(:ActualVoltage, opts['server'].types.folder).tap   { |p| add_axis_concept p, :AxisVoltage }
      a.add_object(:ActualMomentum, opts['server'].types.folder).tap  { |p| p.add_variable :AxisMomentum }
    }

    #RobotObjectType
    rt = opts['server'].types.add_object_type(:RobotType).tap{ |r|
      r.add_object(:State, opts['server'].types.folder).tap{ |s|
        s.add_variables :CurrentProgram, :RobotMode, :RobotState, :JointMode, :SafetyMode, :ToolMode, :ProgramState, :SpeedScaling
        s.add_variable_rw :Override
      }
      r.add_object(:SafetyBoard, opts['server'].types.folder).tap{ |r|
        r.add_variables :MainVoltage, :RobotVoltage, :RobotCurrent
      }
      r.add_object(:Programs, opts['server'].types.folder).tap{ |p|
        p.add_object :Program, pf, OPCUA::OPTIONAL
        p.add_variable :Programs
        opts['file'] = p.add_variable :File
        p.add_method :Refresh do

        end
        p.add_method :SendToServer, program: OPCUA::TYPES::STRING do |node, program|

        end
        p.add_method :ReceiveFromServer, program: OPCUA::TYPES::STRING do |node,name|

        end
      }
      r.add_method :SelectProgram, program: OPCUA::TYPES::STRING do |node, program|
        p 'selected' if opts['dash'].load_program(program)
      end
      r.add_method :StartProgram do
        nil unless opts['dash'].start_program
      end
      r.add_method :StopProgram do
        opts['dash'].stop_program
      end
      r.add_method :PauseProgram do
        opts['dash'].pause_program
      end
      r.add_method :PowerOn do
        #p opts['rm'].value
        if opts['rm'].value.to_s != "Running"
          Thread.new do
            if opts['dash'].power_on
              #p 'powering on'
            end
            while opts['rm'].value.to_s != 'Idle'
              #p opts['rm'].value
              sleep 0.5
            end
            p 'break released' if opts['dash'].break_release
          end
        end
      end
      r.add_method :PowerOff do
        opts['dash'].power_off
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
          opts['dash'].close_safety_popup
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

    ### Loading config file
    conf = UR::XMLConfigFile.new "ua.conf.xml"
    output_names, output_types = conf.get_recipe('out')

    ###Connecting to universal robot
    opts['dash'] = UR::Dash.new(opts['ipadress']).connect
    opts['rtde'] = UR::Rtde.new(opts['ipadress']).connect

    ### Manifest programs
    programs = robot.find(:Programs)
    opts['progs'] = get_robot_programs(opts['ipadress'], opts['username'], opts['password'], opts['url'])
    opts['progs'].each do |p|
      programs.manifest(p,pf)
    end
    programs.find(:Programs).value = opts['progs']


    return if !opts['dash'] || !opts['rtde'] ##### TODO, don't return, raise

    ### Set Speed to very slow
    speed_names, speed_types = conf.get_recipe('speed')
    opts['speed'] = opts['rtde'].send_input_setup(speed_names, speed_types)
    opts['speed']["speed_slider_mask"] = 1
    #opts['ov'].value = 100
    opts['ov'].value = opts['speed']["speed_slider_fraction"].to_i


    ### Setup output
    if not opts['rtde'].send_output_setup(output_names, output_types)
      puts 'Unable to configure output'
    end
    if not opts['rtde'].send_start
      puts 'Unable to start synchronization'
    end

    Thread.new do
      while opts['dash'] != nil
        opts['cp'].value = opts['dash'].get_loaded_program
        opts['rs'].value = opts['dash'].get_program_state
        sleep 1
      end
    end
  rescue => e
    puts e.message
    puts e.backtrace
    exit
  end

  run do |opts|
      opts['server'].run
      data = opts['rtde'].receive
      if data
        #robot object
        opts['mv'].value = data['actual_main_voltage']
        opts['rv'].value = data['actual_robot_voltage']
        opts['rc'].value = data['actual_robot_current']
        opts['ss'].value = data['speed_scaling']

        #State objects
        opts['rm'].value = UR::Rtde::ROBOTMODE[data['robot_mode']]
        #@robmode = UR::Rtde::ROBOTMODE[data['robot_mode']]
        opts['sm'].value = UR::Rtde::SAFETYMODE[data['safety_mode']]
        opts['jm'].value = UR::Rtde::JOINTMODE[data['joint_mode']]
        opts['tm'].value = UR::Rtde::TOOLMODE[data['tool_mode']]
        opts['ps'].value = UR::Rtde::PROGRAMSTATE[data['runtime_state']]

        #Axes object
        split_vector6_data(data['actual_q'],opts['aap'], opts['aapa']) #actual jont positions
        split_vector6_data(data['actual_qd'],opts['avel'], opts['avela']) #actual joint velocities
        split_vector6_data(data['actual_joint_voltage'],opts['avol'], opts['avola']) # #actual joint voltage
        split_vector6_data(data['actual_current'],opts['acur'], opts['acura']) #actual current
        opts['amom'].value = data['actual_momentum'].to_s   #actual_momentum

        # #TCP object
        split_vector6_data(data['actual_qd'],opts['ap'], opts['apa']) #Actual TCP Pose
        split_vector6_data(data['actual_qd'],opts['as'], opts['asa']) #Actual TCP Speed
        split_vector6_data(data['actual_qd'],opts['af'], opts['afa']) #Actual TCP Force

        #write values
        opts['speed']["speed_slider_fraction"] = opts['ov'].value / 100.0
        opts['rtde'].send(opts['speed'])
      end

  rescue Errno::ECONNREFUSED => e
    puts 't'
  rescue => e
    puts e.message
  end
  on exit do
    #reserved for important stuff
    p 'bye'
  end

end.loop!
