#!/usr/bin/ruby
#require 'opcua/server'
require_relative '../opcua-smart/lib/opcua/server'
require_relative '../ur-sock/lib/ur-sock'
#require 'ur-sock'

Daemonite.new do

  server = OPCUA::Server.new
  server.add_namespace "https://centurio.work/ur10evva"

  pr = server.types.add_object_type(:RobotProgram).tap{|p|
    p.add_variable :CurrentProgram
    p.add_variable :ProgramState


    p.add_method :SelectProgram, program: OPCUA::TYPES::STRING do |node, program|
      # do something

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

  #StateObjectType
  st = server.types.add_object_type(:States).tap{ |s|
    s.add_variable :RobotMode
    s.add_variable :RobotState
    s.add_variable :JointMode
    s.add_variable :SafetyMode
    s.add_variable :ToolMode
    s.add_variable :ProgramState
  }
  #TCP ObjectType
  tcp = server.types.add_object_type(:TCP).tap{ |t|
    t.add_object(:ActualPose, server.types.folder).tap{ |p|
      p.add_variable :TCPPose
      p.add_variable :Axis1
      p.add_variable :Axis2
      p.add_variable :Axis3
      p.add_variable :Axis4
      p.add_variable :Axis5
      p.add_variable :Axis6
    }
    t.add_object(:ActualSpeed, server.types.folder).tap{ |s|
      s.add_variable :TCPSpeed
      s.add_variable :Axis1
      s.add_variable :Axis2
      s.add_variable :Axis3
      s.add_variable :Axis4
      s.add_variable :Axis5
      s.add_variable :Axis6
    }
    t.add_object(:ActualForce, server.types.folder).tap{ |f|
      f.add_variable :TCPForce
      f.add_variable :Axis1
      f.add_variable :Axis2
      f.add_variable :Axis3
      f.add_variable :Axis4
      f.add_variable :Axis5
      f.add_variable :Axis6
    }

  }
  #AxisObjectType
  ax = server.types.add_object_type(:AxisType).tap{|a|
    a.add_object(:ActualPositions, server.types.folder).tap{ |p|
      p.add_variable :AxisPositions
      p.add_variable :Axis1
      p.add_variable :Axis2
      p.add_variable :Axis3
      p.add_variable :Axis4
      p.add_variable :Axis5
      p.add_variable :Axis6
    }
    a.add_object(:ActualVelocities, server.types.folder).tap{ |v|
      v.add_variable :AxisVelocities
      v.add_variable :Axis1
      v.add_variable :Axis2
      v.add_variable :Axis3
      v.add_variable :Axis4
      v.add_variable :Axis5
      v.add_variable :Axis6
    }
    a.add_object(:ActualCurrents, server.types.folder).tap{ |c|
      c.add_variable :AxisCurrents
      c.add_variable :Axis1
      c.add_variable :Axis2
      c.add_variable :Axis3
      c.add_variable :Axis4
      c.add_variable :Axis5
      c.add_variable :Axis6
    }
    a.add_object(:ActualVoltage, server.types.folder).tap{ |v|
      v.add_variable :AxisVoltage
      v.add_variable :Axis1
      v.add_variable :Axis2
      v.add_variable :Axis3
      v.add_variable :Axis4
      v.add_variable :Axis5
      v.add_variable :Axis6
    }
  }
  #RobotObjectType
  rt = server.types.add_object_type(:RobotType).tap{ |r|
    r.add_variable :ManufacturerName
    r.add_variable :MainVoltage
    r.add_variable :RobotVoltage
    r.add_variable :RobotCurrent
    r.add_variable :JointVoltage
    r.add_variable_rw :Override
    r.add_variable :SpeedScaling
    #r.add_object :Target, tt, OPCUA::MANDATORY
    #r.add_object :Actual, at, OPCUA::MANDATORY

    r.add_method :testMethod, test1: OPCUA::TYPES::STRING, test2: OPCUA::TYPES::DATETIME do |node, test1, test2|
      puts 'me'
      puts 'test'
      # do something
    end
  }

  #populating the adress space
  robot = server.objects.manifest(:UR10e, rt)
  #Robot object
  robot.find(:ManufacturerName).value = 'Universal Robot'
  mv = robot.find(:MainVoltage)
  rv = robot.find(:RobotVoltage)
  rc = robot.find(:RobotCurrent)
  jv = robot.find(:JointVoltage)
  ov = robot.find(:Override)
  ss = robot.find(:SpeedScaling)

  #ProgramObject
  prog = robot.manifest(:Program, pr)
  cp = prog.find(:CurrentProgram)


  #StateObject
  st = robot.manifest(:States, st)
  rm = st.find(:RobotMode)
  sm = st.find(:SafetyMode)
  jm = st.find(:JointMode)
  tm = st.find(:ToolMode)
  ps = st.find(:ProgramState)
  rs = st.find(:RobotState)

  #Axes
  axes = robot.manifest(:Axes, ax)
  #Positions
  aapf = axes.find(:ActualPositions)
  aap = aapf.find(:AxisPositions)
  aapa = [aapf.find(:Axis1),aapf.find(:Axis2),aapf.find(:Axis3),aapf.find(:Axis4),aapf.find(:Axis5),aapf.find(:Axis6)]
  #Velocities
  avelf = axes.find(:ActualVelocities)
  avel = avelf.find(:AxisVelocities)
  avela = [avelf.find(:Axis1),avelf.find(:Axis2),avelf.find(:Axis3),avelf.find(:Axis4),avelf.find(:Axis5),avelf.find(:Axis6)]
  #Currents
  acurf = axes.find(:ActualCurrents)
  acur = acurf.find(:AxisCurrents)
  acura = [acurf.find(:Axis1),acurf.find(:Axis2),acurf.find(:Axis3),acurf.find(:Axis4),acurf.find(:Axis5),acurf.find(:Axis6)]
  #Voltage
  avolf = axes.find(:ActualVoltage)
  avol = avolf.find(:AxisVoltage)
  avola = [avolf.find(:Axis1),avolf.find(:Axis2),avolf.find(:Axis3),avolf.find(:Axis4),avolf.find(:Axis5),avolf.find(:Axis6)]

  #TCP
  #TCP Pose
  tcp = robot.manifest(:TCP, tcp)
  apf = tcp.find(:ActualPose)
  ap = apf.find(:TCPPose)
  apa = [apf.find(:Axis1),apf.find(:Axis2),apf.find(:Axis3),apf.find(:Axis4),apf.find(:Axis5),apf.find(:Axis6)]
  #TCP Speed
  asf = tcp.find(:ActualSpeed)
  as = asf.find(:TCPSpeed)
  asa = [asf.find(:Axis1),asf.find(:Axis2),asf.find(:Axis3),asf.find(:Axis4),asf.find(:Axis5),asf.find(:Axis6)]
  #TCP Force
  aff = tcp.find(:ActualForce)
  af = aff.find(:TCPForce)
  afa = [aff.find(:Axis1),aff.find(:Axis2),aff.find(:Axis3),aff.find(:Axis4),aff.find(:Axis5),aff.find(:Axis6)]


  #loading config file
  conf = UR::XMLConfigFile.new "ua.conf.xml"
  output_names, output_types = conf.get_recipe('out')

  #Connecting to universal robot
  # dash = UR::Dash.new('192.168.56.10').connect
  # rtde = UR::Rtde.new('192.168.56.101').connect
  dash = UR::Dash.new('localhost').connect
  rtde = UR::Rtde.new('localhost').connect

  return if !dash || !rtde

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
    while true
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
        jv.value = data['actual_joint_voltage']
        ss.value = data['speed_scaling']


        #State objects
        rm.value = UR::Rtde::ROBOTMODE[data['robot_mode']]
        sm.value = UR::Rtde::SAFETYMODE[data['safety_mode']]
        jm.value = UR::Rtde::JOINTMODE[data['joint_mode']]
        tm.value = UR::Rtde::JOINTMODE[data['tool_mode']]
        ps.value = UR::Rtde::PROGRAMSTATE[data['runtime_state']]



        #Axes object
        aq = data['actual_q'].to_s
        aap.value = aq
        aqa = aq[1..-2].split(",")
        aapa.each_with_index do |a,i|
          a.value = aqa[i].to_f
        end

        aqd = data['actual_qd'].to_s
        avel.value = aqd
        aqda = aqd[1..-2].split(",")
        avela.each_with_index do |a,i|
          a.value = aqda[i].to_f
        end

        ajv = data['actual_joint_voltage'].to_s
        avol.value = ajv
        ajva = ajv[1..-2].split(",")
        avola.each_with_index do |a,i|
          a.value = ajva[i].to_f
        end


        ac = data['actual_current'].to_s
        acur.value = ac
        aca = ac[1..-2].split(",")
        acura.each_with_index do |a,i|
          a.value = aca[i].to_f
        end


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
        speed["speed_slider_fraction"] = ov.value
        rtde.send(speed)
      end
    rescue => e
      puts e.message
    end
  end
  on exit do
    #reserved for important stuff
  end

end.loop!

#   run do
#     #sleep server.run
#     data = rtde.receive
#     tjp.value = rtde["JointPositions"]
#     #tn.value = Time.now
#   end
# end.loop!
