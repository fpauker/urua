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

  a = server.types.add_object_type(:ActualType).tap{ |t|
    t.add_variable :JointPositions
    t.add_variable :JointVelocities
    t.add_variable :JointCurrents
  }
  pt = server.types.add_object_type(:RobotType).tap{ |r|
    r.add_variable :ManufacturerName

    t.add_object(:Tools, server.types.folder).tap{ |u|
      u.add_object :Tool, tt, OPCUA::OPTIONALPLACEHOLDER
    }
  }

  tools = server.objects.instantiate(:KalimatC34, pt).find(:Tools)

  t1 = tools.instantiate(:Tool1,tt)
  t2 = tools.instantiate(:Tool2,tt)
  t3 = tools.instantiate(:Tool3,tt)

  tn = t1.find(:ToolNumber)

  measurments_t1 = t1.find(:Measurements)
  measurments_t1.instantiate(:M1,mt)
  measurments_t1.instantiate(:M2,mt)

  p tn.id

  run do
    sleep server.run
    tn.value = Time.now
  end
end.loop!
