#!/usr/bin/ruby
#require_relative '../lib/opcua/server'
require 'opcua/server'
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
    #r.add_object :Target, tt, OPCUA::MANDATORY
    #r.add_object :Actual, at, OPCUA::MANDATORY
  }

  robot = server.objects.manifest(:UR10e, rt)
  robot.manifest(:Target, tt)
  actual = robot.find(:Target)
  tjp = actual.find(:JointPositions)

  p tjp.id

  run do
    sleep server.run
    #tn.value = Time.now
  end
end.loop!
