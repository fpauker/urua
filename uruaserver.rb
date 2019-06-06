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
  aqd = data['actual_qd'].to_s
  item.value = vector.to_S
  va = vector.to_S[1..-2].split(",")
  va.each_with_index do |a,i|
    a.value = nodes[i].to_f
  end
  [vector.to_s, va]
end

Daemonite.new do |opts|

  opts['server'] = OPCUA::Server.new
  opts['server'].add_namespace "https://centurio.work/ur10evva"
  opts['ipadress'] = '192.168.56.101'
  #ipadress = 'localhost'
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
    }
    r.add_method :SelectProgram, program: OPCUA::TYPES::STRING do |node, program|
      # do something
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
      if @robmode != "Running"
        Thread.new do
          if opts['dash'].power_on
            p 'poweron'
          end
          while @robmode.to_s != 'Idle'
            p @robmode
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

  #Positions
  opts['aap']  = aapf.find :AxisPositions
  opts['aapa'] = aapf.find :Axis1, :Axis2, :Axis3, :Axis4, :Axis5, :Axis6
  #Velocities
  opts['avel']  = avelf.find :AxisVelocities
  opts['avela'] = avelf.find :Axis1, :Axis2, :Axis3, :Axis4, :Axis5, :Axis6
  #Currents
  opts['acur']  = acurf.find :AxisCurrents
  opts['acura'] = acurf.find :Axis1, :Axis2, :Axis3, :Axis4, :Axis5, :Axis6
  #Voltage
  opts['avol']  = avolf.find :AxisVoltage
  opts['avola'] = avolf.find :Axis1, :Axis2, :Axis3, :Axis4, :Axis5, :Axis6
  #Momentum
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


  #loading config file
  conf = UR::XMLConfigFile.new "ua.conf.xml"
  output_names, output_types = conf.get_recipe('out')

  #Connecting to universal robot
  opts['dash'] = UR::Dash.new(ipadress).connect
  opts['rtde'] = UR::Rtde.new(ipadress).connect

  #parsing file system
  ssh = Net::SSH.start( ipadress, 'ur', password: "easybot" )
  programs = ssh.exec!( 'ls /home/ur/ursim-current/programs.UR10 | grep .urp' ).split( "\n" )
  ssh.close()
  pff = robot.find(:Programs)
  programs.each do |n|
    pff.manifest(n[0..-1],pf)
  end

  return if !opts['dash'] || !rtde ##### TODO, don't return, raise

  ## Set Speed to very slow
  speed_names, speed_types = conf.get_recipe('speed')
  opts['speed'] = rtde.send_input_setup(speed_names, speed_types)
  opts['speed']["speed_slider_mask"] = 1
  opts['ov'].value = 100
  opts['ov'].value = opts['speed']["speed_slider_fraction"]


  ### Setup output
  if not opts['rtde'].send_output_setup(output_names, output_types)
    puts 'Unable to configure output'
  end
  if not rtde.send_start
    puts 'Unable to start synchronization'
  end

  Thread.new do
    while opts['dash'] != nil
      cp.value = opts['dash'].get_loaded_program
      rs.value = opts['dash'].get_program_state
      sleep 1
    end
  end

  run do
    begin

      opts['server'].run
      data = rtde.receive
      if data
        #robot object
        mv.value = data['actual_main_voltage']
        rv.value = data['actual_robot_voltage']
        rc.value = data['actual_robot_current']
        ss.value = data['speed_scaling']

        #State objects
        rm.value = UR::Rtde::ROBOTMODE[data['robot_mode']]
        @robmode = UR::Rtde::ROBOTMODE[data['robot_mode']]
        sm.value = UR::Rtde::SAFETYMODE[data['safety_mode']]
        jm.value = UR::Rtde::JOINTMODE[data['joint_mode']]
        tm.value = UR::Rtde::TOOLMODE[data['tool_mode']]
        ps.value = UR::Rtde::PROGRAMSTATE[data['runtime_state']]

        #Axes object
        #actual jont positions
        aq = data['actual_q'].to_s
        aap.value = aq
        aqa = aq[1..-2].split(",")
        aapa.each_with_index do |a,i|
          a.value = aqa[i].to_f
        end
        split_vector6_data(data['actual_qd'],aap, aapa)
        #actual joint velocities
        aqd = data['actual_qd'].to_s
        avel.value = aqd
        aqda = aqd[1..-2].split(",")
        avela.each_with_index do |a,i|
          a.value = aqda[i].to_f
        end
        #actual joint voltage
        ajv = data['actual_joint_voltage'].to_s
        avol.value = ajv
        ajva = ajv[1..-2].split(",")
        avola.each_with_index do |a,i|
          a.value = ajva[i].to_f
        end
        #actual current
        ac = data['actual_current'].to_s
        acur.value = ac
        aca = ac[1..-2].split(",")
        acura.each_with_index do |a,i|
          a.value = aca[i].to_f
        end
        #actual_momentum
        amom.value = data['actual_momentum'].to_s


        #TCP object
        #Actual TCP Pose
        atp = data['actual_TCP_pose'].to_s
        ap.value = atp
        atpa = atp[1..-2].split(",")
        apa.each_with_index do |a,i|
          a.value = atpa[i].to_f
        end
        #Actual TCP Speed
        ats = data['actual_TCP_speed'].to_s
        as.value = ats
        atsa = ats.gsub!(/^\[|\]?$/, '').split(",")
        asa.each_with_index do |a,i|
          a.value = atsa[i].to_f
        end
        #Actual TCP Force
        atf = data['actual_TCP_force'].to_s
        af.value = atf
        atfa = atf.gsub!(/^\[|\]?$/, '').split(",")
        afa.each_with_index do |a,i|
          a.value = atfa[i].to_f
        end

        #write values
        speed["speed_slider_fraction"] = ov.value[0]/100
        rtde.send(speed)
      end

    rescue Errno::ECONNREFUSED => e
      puts 't'
    rescue => e
      puts e.message
    end
  end
  on exit do
    #reserved for important stuff
    p 'bye'
  end

end.loop!
