#!/usr/bin/ruby
#require 'opcua/server'
require_relative '../opcua-smart/lib/opcua/server'
#require_relative '../ur-sock/lib/ur-sock'
require 'ur-sock'
require 'net/ssh'

Daemonite.new do
  begin
    server = OPCUA::Server.new
    server.add_namespace "https://centurio.work/ur10evva"

    #ProgramFile
    #TCP ObjectType
    ih = Proc.new do |context,item|
      context.add_variable item
      context.add_variable :Axis1
      context.add_variable :Axis2
      context.add_variable :Axis3
      context.add_variable :Axis4
      context.add_variable :Axis5
      context.add_variable :Axis6
    end
    ax = server.types.add_object_type(:AxisType).tap{|a|
      a.add_object(:ActualPositions, server.types.folder).tap{ |p| ih.call p, :AxisPositions }
      a.add_object(:ActualVelocities, server.types.folder).tap{ |p| ih.call p, :AxisVelocities }
    }

    rt = server.types.add_object_type(:RobotType).tap{ |r|
      r.add_object(:State, server.types.folder).tap{ |s|
        s.add_variable :CurrentProgram
        s.add_variable :RobotMode
        s.add_variable :RobotState
        s.add_variable :JointMode
        s.add_variable :SafetyMode
        s.add_variable :ToolMode
        s.add_variable :ProgramState
        s.add_variable_rw :Override
        s.add_variable :SpeedScaling
      }
      r.add_object(:SafetyBoard, server.types.folder).tap{ |r|
        r.add_variable :MainVoltage
        r.add_variable :RobotVoltage
        r.add_variable :RobotCurrent
      }
      r.add_method :SelectProgram, program: OPCUA::TYPES::STRING do |node, program|
        # do something
        p 'selected' if dash.load_program(program)
      end
      r.add_method :StartProgram do
        if !dash.start_program
          nil
        end
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
          dash.add_to_log
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
