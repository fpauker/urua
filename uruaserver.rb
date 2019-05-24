#!/usr/bin/ruby
#require 'opcua/server'
require_relative '../opcua-smart/lib/opcua/server'
require 'ur-sock'

Daemonite.new do

  server = OPCUA::Server.new
  server.add_namespace "https://centurio.work/ur10evva"

  tt = server.types.add_object_type(:TargetType).tap{ |t|
    t.add_variable :JointPositions
    t.add_variable :JointVelocities
    t.add_variable :JointAcceleration
    t.add_variable :JointCurrents
    t.add_variable :JointMoments
  }
  at = server.types.add_object_type(:ActualType).tap{ |t|
    t.add_variable :JointPositions
    t.add_variable :JointVelocities
    t.add_variable :JointCurrents
  }

  tcp = server.types.add_object_type(:TCP).tap{|t|#
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

  ax = server.types.add_object_type(:AxisType).tap{|a|
    a.add_object(:Positions, server.types.folder).tap{ |p|
      p.add_variable :Axis1
      p.add_variable :Axis2
      p.add_variable :Axis3
      p.add_variable :Axis4
      p.add_variable :Axis5
      p.add_variable :Axis6
    }
    a.add_object(:Velocities, server.types.folder).tap{ |v|
      v.add_variable :Axis1
      v.add_variable :Axis2
      v.add_variable :Axis3
      v.add_variable :Axis4
      v.add_variable :Axis5
      v.add_variable :Axis6
    }
    a.add_object(:Currents, server.types.folder).tap{ |c|
      c.add_variable :Axis1
      c.add_variable :Axis2
      c.add_variable :Axis3
      c.add_variable :Axis4
      c.add_variable :Axis5
      c.add_variable :Axis6
    }
  }

  rt = server.types.add_object_type(:RobotType).tap{ |r|
    r.add_variable :ManufacturerName
    r.add_variable :RobotMode
    r.add_variable :MainVoltage
    r.add_variable :RobotVoltage
    r.add_variable :RobotCurrent
    r.add_variable :JointVoltage
    r.add_variable :Override
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

  robot.find(:ManufacturerName).value = 'Universal Robot'
  rm = robot.find(:RobotMode)
  mv = robot.find(:MainVoltage)
  rv = robot.find(:RobotVoltage)
  rc = robot.find(:RobotCurrent)
  jv = robot.find(:JointVoltage)
  ov = robot.find(:Override)
  #Axes
  robot.manifest(:Axes, ax)
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
  ov.value = 0
  ov.value = speed["speed_slider_fraction"]


  ### Setup output
  if not rtde.send_output_setup(output_names, output_types)
    puts 'Unable to configure output'
  end
  if not rtde.send_start
    puts 'Unable to start synchronization'
  end

  run do
    server.run
    data = rtde.receive
    if data
      #robot object
      rm.value = rtde.get_robotmode[data['robot_mode']]
      mv.value = data["actual_main_voltage"]
      rv.value = data["actual_robot_voltage"]
      rc.value = data["actual_robot_current"]
      jv.value = data["actual_joint_voltage"]

      #axes object

      #TCP object
      #Actual TCP Pose
      atp = data['actual_TCP_pose'].to_s
      ap.value = atp
      atpa = atp.gsub!(/^\[|\]?$/, '').split(",")
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


      #write values
      speed["speed_slider_fraction"] = ov.value
      rtde.send(speed)
    end
  end
end.loop!

#   run do
#     #sleep server.run
#     data = rtde.receive
#     tjp.value = rtde["JointPositions"]
#     #tn.value = Time.now
#   end
# end.loop!
