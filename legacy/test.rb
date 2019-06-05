#!/usr/bin/ruby
require_relative '../../opcua-smart/lib/opcua/server'
require 'ur-sock'

def add_axis_concept(context,item)
  context.add_variables item, :Axis1, :Axis2, :Axis3, :Axis4, :Axis5, :Axis6
end

Daemonite.new do
  begin
    server = OPCUA::Server.new
    server.add_namespace "https://centurio.work/ur10evva"

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

    robot = server.objects.manifest(:UR10e, rt)
    axes = robot.manifest(:Axes, ax)
  rescue => e
    puts e.message
  end

  run do
    begin
      server.run
    rescue => e
      puts e.message
    end
  end

end.loop!
