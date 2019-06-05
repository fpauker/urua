#!/usr/bin/ruby
#require 'opcua/server'
require_relative '../opcua-smart/lib/opcua/server'
require_relative '../ur-sock/lib/ur-sock'
#require 'ur-sock'
require 'net/ssh'

def add_axis_concept(context,item)
  context.add_variables item, :Axis1, :Axis2, :Axis3, :Axis4, :Axis5, :Axis6
end

Daemonite.new do

  server = OPCUA::Server.new
  server.add_namespace "https://centurio.work/ur10evva"
  ipadress = '192.168.56.101'
  #ipadress = 'localhost'
  dash = nil
  rtde = nil
  programs = nil


  #ProgramFile
  pf = server.types.add_object_type(:ProgramFile).tap{|p|
    p.add_method :SelectProgram do |node|
      a = node.id.to_s.split('/')
      dash.load_program(a[a.size-2].to_s[0..-5])
    end
    p.add_method :StartProgram do
      dash.start_program
    end
    p.add_method :StopProgram do
      dash.stop_program
    end
    p.add_method :PauseProgram do
      dash.pause_program
    end
  }
  #TCP ObjectType
  tcp = server.types.add_object_type(:Tcp).tap{ |t|
    t.add_object(:ActualPose, server.types.folder).tap { |p| add_axis_concept p, :TCPPose }
    t.add_object(:ActualSpeed, server.types.folder).tap{ |p| add_axis_concept p, :TCPSpeed }
    t.add_object(:ActualForce, server.types.folder).tap{ |p| add_axis_concept p, :TCPForce }
  }
  #AxisObjectType
  ax = server.types.add_object_type(:AxisType).tap{|a|
    a.add_object(:ActualPositions, server.types.folder).tap { |p| add_axis_concept p, :AxisPositions }
    a.add_object(:ActualVelocities, server.types.folder).tap{ |p| add_axis_concept p, :AxisVelocities }
    a.add_object(:ActualCurrents, server.types.folder).tap  { |p| add_axis_concept p, :AxisCurrents }
    a.add_object(:ActualVoltage, server.types.folder).tap   { |p| add_axis_concept p, :AxisVoltage }
    a.add_object(:ActualMomentum, server.types.folder).tap  { |p| p.add_variable :AxisMomentum }
  }

  #RobotObjectType
  rt = server.types.add_object_type(:RobotType).tap{ |r|
    r.add_object(:State, server.types.folder).tap{ |s|
      s.add_variables :CurrentProgram, :RobotMode, :RobotState, :JointMode, :SafetyMode, :ToolMode, :ProgramState, :SpeedScaling
      s.add_variable_rw :Override
    }
    r.add_object(:SafetyBoard, server.types.folder).tap{ |r|
      r.add_variables :MainVoltage, :RobotVoltage, :RobotCurrent
    }
    r.add_object(:Programs, server.types.folder).tap{ |p|
      p.add_object :Program, pf, OPCUA::OPTIONAL
    }
    r.add_method :SelectProgram, program: OPCUA::TYPES::STRING do |node, program|
      # do something
      p 'selected' if dash.load_program(program)
    end
    r.add_method :StartProgram do
      nil unless dash.start_program
    end
    r.add_method :StopProgram do
      dash.stop_program
    end
    r.add_method :PauseProgram do
      dash.pause_program
    end
    r.add_method :PowerOn do
      if @robmode != "Running"
        Thread.new do
          if dash.power_on
            p 'poweron'
          end
          while @robmode.to_s != 'Idle'
            p @robmode
            sleep 0.5
          end
          p 'break released' if dash.break_release
        end
      end
    end
    r.add_method :PowerOff do
      dash.power_off
    end
    r.add_object(:RobotMode, server.types.folder).tap{ |r|
      r.add_method :AutomaticMode do
        dash.set_operation_mode_auto
      end
      r.add_method :ManualMode do
        dash.set_operation_mode_manual
      end
      r.add_method :ClearMode do
        dash.clear_operation_mode
      end
    }

    r.add_object(:Messaging, server.types.folder).tap{ |r|
      r.add_method :PopupMessage, message: OPCUA::TYPES::STRING do |node, message|
        dash.open_popupmessage(message)
      end
      r.add_method :ClosePopupMessage do
        dash.close_popupmessage
      end
      r.add_method :AddToLog, message: OPCUA::TYPES::STRING do |node, message|
        dash.add_to_log(message)
      end
      r.add_method :CloseSafetyPopup do
        dash.close_safety_popup
      end
    }
  }

  ### populating the adress space
  ### Robot object
  robot = server.objects.manifest(:UR10e, rt)

  ### SafetyBoard
  sb = robot.find(:SafetyBoard)
  mv = sb.find(:MainVoltage)
  rv = sb.find(:RobotVoltage)
  rc = sb.find(:RobotCurrent)

  ### StateObject
  st = robot.find(:State)
  rm = st.find(:RobotMode)
  sm = st.find(:SafetyMode)
  jm = st.find(:JointMode)
  tm = st.find(:ToolMode)
  ps = st.find(:ProgramState)
  rs = st.find(:RobotState)
  cp = st.find(:CurrentProgram)
  ov = st.find(:Override)
  ss = st.find(:SpeedScaling)

  ### Axes
  axes = robot.manifest(:Axes, ax)
  aapf, avelf, acurf, avolf, amomf = axes.find :ActualPositions, :ActualVelocities, :ActualCurrents, :ActualVoltage, :ActualMomentum

  #Positions
  aap  = aapf.find :AxisPositions
  aapa = aapf.find :Axis1, :Axis2, :Axis3, :Axis4, :Axis5, :Axis6
  #Velocities
  avel  = avelf.find :AxisVelocities
  avela = avelf.find :Axis1, :Axis2, :Axis3, :Axis4, :Axis5, :Axis6
  #Currents
  acur  = acurf.find :AxisCurrents
  acura = acurf.find :Axis1, :Axis2, :Axis3, :Axis4, :Axis5, :Axis6
  #Voltage
  avol  = avolf.find :AxisVoltage
  avola = avolf.find :Axis1, :Axis2, :Axis3, :Axis4, :Axis5, :Axis6
  #Momentum
  amom = amomf.find :AxisMomentum


  ### TCP
  tcp = robot.manifest(:Tcp, tcp)
  apf, asf, aff = tcp.find :ActualPose, :ActualSpeed, :ActualForce

  ### TCP Pose
  ap  = apf.find :TCPPose
  apa = apf.find :Axis1, :Axis2, :Axis3, :Axis4, :Axis5, :Axis6
  ### TCP Speed
  as  = asf.find :TCPSpeed
  asa = asf.find :Axis1, :Axis2, :Axis3, :Axis4, :Axis5, :Axis6
  ### TCP Force
  af  = aff.find :TCPForce
  afa = aff.find :Axis1, :Axis2, :Axis3, :Axis4, :Axis5, :Axis6


  #loading config file
  conf = UR::XMLConfigFile.new "ua.conf.xml"
  output_names, output_types = conf.get_recipe('out')

  #Connecting to universal robot
  dash = UR::Dash.new(ipadress).connect
  rtde = UR::Rtde.new(ipadress).connect

  #parsing file system
  ssh = Net::SSH.start( ipadress, 'ur', password: "easybot" )
  programs = ssh.exec!( 'ls /home/ur/ursim-current/programs.UR10 | grep .urp' ).split( "\n" )
  ssh.close()
  pff = robot.find(:Programs)
  programs.each do |n|
    pff.manifest(n[0..-1],pf)
  end

  return if !dash || !rtde ##### TODO, don't return, raise

  ## Set Speed to very slow
  speed_names, speed_types = conf.get_recipe('speed')
  speed = rtde.send_input_setup(speed_names, speed_types)
  speed["speed_slider_mask"] = 1
  ov.value = 100
  ov.value = speed["speed_slider_fraction"]


  ### Setup output
  if not rtde.send_output_setup(output_names, output_types)
    puts 'Unable to configure output'
  end
  if not rtde.send_start
    puts 'Unable to start synchronization'
  end

  Thread.new do
    while dash != nil
      cp.value = dash.get_loaded_program
      rs.value = dash.get_program_state
      sleep 1
    end
  end

  run do
    begin

      server.run
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
