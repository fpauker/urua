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
  #causes errors, because both Jointpositions got the same nodeid
  at = server.types.add_object_type(:ActualType).tap{ |t|
    t.add_variable :JointPositions
    t.add_variable :JointVelocities
    t.add_variable :JointCurrents
  }

  rt = server.types.add_object_type(:RobotType).tap{ |r|
    r.add_variable :ManufacturerName
    r.add_variable :RobotMode
    r.add_variable :MainVoltage
    r.add_variable :RobotVoltage
    r.add_variable :RobotCurrent
    r.add_variable :JointVoltage
    r.add_variable :Override
    r.add_object :Target, tt, OPCUA::MANDATORY
    r.add_object :Actual, at, OPCUA::MANDATORY
    r.add_method :testMethod, test1: OPCUA::TYPES::STRING, test2: OPCUA::TYPES::DATETIME do |node, test1, test2|
      puts 'me'
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
  actual = robot.find(:Target)
  tjp = actual.find(:JointPositions)


  #loading config file
  conf = UR::XMLConfigFile.new "ua.conf.xml"
  output_names, output_types = conf.get_recipe('out')

  #Connecting to universal robot
  dash = UR::Dash.new('192.168.56.101').connect
  rtde = UR::Rtde.new('192.168.56.101').connect

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
      rm.value = rtde.get_robotmode[data['robot_mode']]
      tjp.value = data["actual_q"].to_s
      mv.value = data["actual_main_voltage"]
      rv.value = data["actual_robot_voltage"]
      rc.value = data["actual_robot_current"]
      jv.value = data["actual_joint_voltage"]


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
