require 'daemonite'
require 'opcua/server'
if $dev
  require_relative '../../ur-sock/lib/ur-sock'
else
  require 'ur-sock'
end
require 'net/ssh'
require 'net/scp'

module URUA

  def self::add_axis_concept(context, item) #{{{
    context.add_variables item, :Axis1, :Axis2, :Axis3, :Axis4, :Axis5, :Axis6
  end #}}}

  def self::split_vector6_data(vector, item, nodes) #{{{
    # aqd = data['actual_qd'].to_s
    item.value = vector.to_s
    va = vector.to_s[1..-2].split(',')
    nodes.each_with_index do |a, i|
      a.value = vector[i].to_f
    end
    [vector.to_s, va]
  end #}}}

  def self::start_dash(opts) #{{{
    opts['dash'] = UR::Dash.new(opts['ipadress']).connect rescue nil
  end #}}}

  def self::start_psi(opts)
    opts['psi'] = UR::Psi.new(opts['ipadress']).connect rescue nil
  end

  def self::start_rtde(opts) #{{{
    ### Loading config file
    conf = UR::XMLConfigFile.new opts['rtde_config']
    output_names, output_types = conf.get_recipe opts['rtde_config_recipe_base']
    opts['rtde'] = UR::Rtde.new(opts['ipadress']).connect

    ### Set Speed
    if opts['rtde_config_recipe_speed']
      speed_names, speed_types = conf.get_recipe opts['rtde_config_recipe_speed']
      opts['speed'] = opts['rtde'].send_input_setup(speed_names, speed_types)
      opts['speed']['speed_slider_mask'] = 1
    end

    ### Set register
    if opts['rtde_config_recipe_inbit']
      bit_names, bit_types = conf.get_recipe opts['rtde_config_recipe_inbit']
      opts['inbit'] = opts['rtde'].send_input_setup(bit_names,bit_types)
    end
    if opts['rtde_config_recipe_inint']
      int_names, int_types = conf.get_recipe opts['rtde_config_recipe_inint']
      opts['inint'] = opts['rtde'].send_input_setup(int_names,int_types)
    end
    if opts['rtde_config_recipe_indoub']
      doub_names, doub_types = conf.get_recipe opts['rtde_config_recipe_indoub']
      opts['indoub'] = opts['rtde'].send_input_setup(doub_names,doub_types)
    end

    ### Setup output
    if not opts['rtde'].send_output_setup(output_names, output_types,10)
      puts 'Unable to configure output'
    end
    if not opts['rtde'].send_start
      puts 'Unable to start synchronization'
    end

    ###Initialize all inputs
    bit_names.each do |i|
      opts['inbit'][i] = false
    end
    int_names.each do |i|
      opts['inint'][i] = 0
    end
    doub_names.each do |i|
      opts['indoub'][i] = 0.0
    end
  end #}}}

  def self::protect_reconnect_run(opts) #{{{
    tries = 0
    begin
      yield
    rescue UR::Dash::Reconnect => e
      puts e.message
      tries += 1
      if tries < 2
        URUA::start_dash opts
        retry
      end
    rescue UR::Psi::Reconnect => e
      puts e.message
      tries += 1
      if tries < 2
        URUA::start_psi opts
        retry
      end
    end
  end #}}}

  def self::ssh_start(opts) #{{{
    if opts['certificate']
      opts['ssh'] = Net::SSH.start(opts['ipadress'], opts['username'], :keys => [ opts['certificate'] ])
    else
      opts['ssh'] = opts['password'] ? Net::SSH.start(opts['ipadress'], opts['username'], password: opts['password']) : Net::SSH.start(opts['ipadress'], opts['username'])
    end
  end #}}}

  def self::download_program(opts,name) #{{{
    counter = 0
    begin
      opts['ssh'].scp.download! File.join(opts['url'],name)
    rescue => e
      counter += 1
      URUA::ssh_start opts
      retry if counter < 3
    end
  end #}}}

  def self::upload_program(opts,name,program) #{{{
    counter = 0
    begin
      opts['ssh'].scp.upload StringIO.new(program), File.join(opts['url'],name)
    rescue => e
      counter += 1
      URUA::ssh_start opts
      retry if counter < 3
    end
    nil
  end #}}}

  def self::get_robot_programs(opts) #{{{
    progs = []
    begin
      progs = opts['ssh'].exec!('ls ' + File.join(opts['url'],'*.urp') + ' 2>/dev/null').split("\n")
      progs.shift if progs[0] =~ /^bash:/
    rescue => e
      URUA::ssh_start opts
    end
    progs
  end #}}}

  def self::robotprogram_running?(opts)
    opts['ps'].value == 'Playing'
  end

  def self::implementation_startup(opts) #{{{
    opts['rtde_config'] ||= File.join(__dir__,'rtde.conf.xml')
    opts['rtde_config_recipe_base'] ||= 'out'
    opts['rtde_config_recipe_speed'] ||= 'speed'
    opts['rtde_config_recipe_inbit'] ||= 'inbit'
    opts['rtde_config_recipe_inint'] ||= 'inint'
    opts['rtde_config_recipe_indoub'] ||= 'indoub'

    Proc.new do
      on startup do |opts|
        opts['server'] = OPCUA::Server.new
        opts['server'].add_namespace opts['namespace']
        opts['dash'] = nil
        opts['rtde'] = nil
        opts['programs'] = nil
        opts['psi'] = nil

        # ProgramFile
        opts['pf'] = opts['server'].types.add_object_type(:ProgramFile).tap{ |p|
          p.add_method :SelectProgram do |node|
            a = node.id.to_s.split('/')
            URUA::protect_reconnect_run(opts) do
              opts['dash'].load_program(a[-2])
            end
          end
          p.add_method :StartProgram do |node|
            unless URUA::robotprogram_running?(opts)
              a = node.id.to_s.split('/')
              URUA::protect_reconnect_run(opts) do
                opts['dash'].load_program(a[-2])
                opts['dash'].start_program
              end
            end
          end
          p.add_method :StartAsUrScript do |node|
            unless URUA::robotprogram_running?(opts)
              a = node.id.to_s.split('/')
              URUA::protect_reconnect_run(opts) do
                opts['psi'].execute_ur_script(URUA::download_program(opts, a[-2]+".script"))
              end
            end
          end
        }
        # TCP ObjectType
        tcp = opts['server'].types.add_object_type(:Tcp).tap{ |t|
          t.add_object(:ActualPose, opts['server'].types.folder).tap { |p| URUA::add_axis_concept p, :TCPPose }
          t.add_object(:ActualSpeed, opts['server'].types.folder).tap{ |p| URUA::add_axis_concept p, :TCPSpeed }
          t.add_object(:ActualForce, opts['server'].types.folder).tap{ |p| URUA::add_axis_concept p, :TCPForce }
        }
        # AxisObjectType
        ax = opts['server'].types.add_object_type(:AxisType).tap { |a|
          a.add_object(:ActualPositions, opts['server'].types.folder).tap { |p| URUA::add_axis_concept p, :AxisPositions }
          a.add_object(:ActualVelocities, opts['server'].types.folder).tap{ |p| URUA::add_axis_concept p, :AxisVelocities }
          a.add_object(:ActualCurrents, opts['server'].types.folder).tap  { |p| URUA::add_axis_concept p, :AxisCurrents }
          a.add_object(:ActualVoltage, opts['server'].types.folder).tap   { |p| URUA::add_axis_concept p, :AxisVoltage }
          a.add_object(:ActualMomentum, opts['server'].types.folder).tap  { |p| p.add_variable :AxisMomentum }
        }
        # RegitsterType
        reg = opts['server'].types.add_object_type(:RegType).tap {|r|
          r.add_object(:Inputs, opts['server'].types.folder).tap {|i|
            i.add_object(:Bitregister, opts['server'].types.folder).tap {|b|
              64.upto(127) do |z|
                b.add_variable_rw :"Bit#{z}" do |node,value,external|
                  if external
                    opts['inbit']["input_bit_register_" + z.to_s] = value
                    opts['rtde'].send(opts['inbit'])
                  end
                end
              end
            }
            i.add_object(:Intregister, opts['server'].types.folder).tap {|b|
              0.upto(47) do |z|
                b.add_variable_rw :"Int#{z}" do |node,value,external|
                  if external
                    opts['inint']["input_int_register_" + z.to_s] = value.to_i
                    opts['rtde'].send(opts['inint'])
                  end
                end
              end
            }
            i.add_object(:Doubleregister, opts['server'].types.folder).tap {|b|
              0.upto(47) do |z|
                b.add_variable_rw :"Double#{z}" do |node,value,external|
                  if external
                    opts['indoub']["input_double_register_" + z.to_s] = value.to_f
                    opts['rtde'].send(opts['indoub'])
                  end
                end
              end
            }
          }
          r.add_object(:Outputs, opts['server'].types.folder).tap {|o|
            o.add_object(:Bitregister, opts['server'].types.folder).tap {|b|
              64.upto(127) do |z|
                b.add_variable :"Bit#{z}"
              end
            }
            o.add_object(:Intregister, opts['server'].types.folder).tap {|b|
              0.upto(47) do |z|
                b.add_variable :"Int#{z}"
              end
            }
            o.add_object(:Doubleregister, opts['server'].types.folder).tap {|b|
              0.upto(47) do |z|
                b.add_variable :"Double#{z}"
              end
            }
          }
        }


        # RobotObjectType
        rt = opts['server'].types.add_object_type(:RobotType).tap { |r|
          r.add_variables :SerialNumber, :RobotModel
          r.add_object(:State, opts['server'].types.folder).tap{ |s|
            s.add_variables :CurrentProgram, :RobotMode, :RobotState, :JointMode, :SafetyMode, :ToolMode, :ProgramState, :SpeedScaling, :Remote, :OperationalMode
            s.add_variable_rw :Override do |node,value,external|
              if external
                opts['speed']['speed_slider_fraction'] = value / 100.0
                opts['rtde'].send(opts['speed'])
              end
            end
          }
          r.add_object(:SafetyBoard, opts['server'].types.folder).tap{ |r|
            r.add_variables :MainVoltage, :RobotVoltage, :RobotCurrent
          }

          r.add_object(:Programs, opts['server'].types.folder).tap{ |p|
            p.add_object :Program, opts['pf'], OPCUA::OPTIONAL
            p.add_variable :Programs
            opts['file'] = p.add_variable :File
            p.add_method :UploadProgram, name: OPCUA::TYPES::STRING, program: OPCUA::TYPES::STRING do |node, name, program|
              URUA::upload_program opts, name, program
            end
            p.add_method :DownloadProgram, name: OPCUA::TYPES::STRING, return:  OPCUA::TYPES::STRING do |node,name|
              URUA::download_program opts, name
            end
          }
          r.add_method :SelectProgram, name: OPCUA::TYPES::STRING do |node, name|
            URUA::protect_reconnect_run(opts) do
              opts['dash'].load_program(name)
            end
          end
          r.add_method :StartProgram do
            unless URUA::robotprogram_running?(opts)
              URUA::protect_reconnect_run(opts) do
                nil unless opts['dash'].start_program
              end
            end
          end
          r.add_method :StopProgram do
            URUA::protect_reconnect_run(opts) do
              opts['dash'].stop_program
            end
          end
          r.add_method :PauseProgram do
            URUA::protect_reconnect_run(opts) do
              opts['dash'].pause_program
            end
          end
          r.add_method :RunUrScript, content: OPCUA::TYPES::STRING do |node, content|
            unless URUA::robotprogram_running?(opts)
              URUA::protect_reconnect_run(opts) do
                opts['psi'].execute_ur_script(content)
              end
            end
          end
          r.add_method :PowerOn do
            if opts['rm'].value.to_s != 'Running'
              Thread.new do
                sleep 0.5 until opts['rm'].value.to_s == 'Idle'
                URUA::protect_reconnect_run(opts) do
                  puts 'break released' if opts['dash'].break_release
                end
              end
            end
          end
          r.add_method :PowerOff do
            URUA::protect_reconnect_run(opts) do
              opts['dash'].power_off
            end
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
              URUA::protect_reconnect_run(opts) do
                opts['dash'].close_safety_popup
              end
            end
          }
        }
        ### populating the adress space
        ### Robot object
        robot = opts['server'].objects.manifest(File.basename(opts['namespace']), rt)

        opts['sn'] = robot.find(:SerialNumber)
        opts['model'] = robot.find(:RobotModel)

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
        opts['mo'] = st.find(:Remote)
        opts['op'] = st.find(:OperationalMode)

        ### register
        register = robot.manifest(:Register, reg)
        inputs = register.find :Inputs
        ibitreg = inputs.find :Bitregister
        opts['b_bits'] = 64.upto(127).map{|b|
          ib = ibitreg.find :"Bit#{b}"
          ib.value = false
          ib
        }
        iintreg = inputs.find :Intregister
        opts['i_int'] = 0.upto(47).map{|b|
          ii = iintreg.find :"Int#{b}"
          ii.value = 0
          ii
        }
        #extend it with other registers
        idoubreg = inputs.find :Doubleregister
        opts['i_doub'] = 0.upto(47).map{|b|
          id = idoubreg.find :"Double#{b}"
          id.value = 0.0
          id
        }
        #Output register
        outputs = register.find :Outputs
        obitreg = outputs.find :Bitregister
        opts['o_bit'] = 64.upto(127).map{|b|
          ob = obitreg.find :"Bit#{b}"
          ob.value = false
          ob
        }
        ointreg = outputs.find :Intregister
        opts['o_int'] = 0.upto(47).map{|b|
          oi = ointreg.find :"Int#{b}"
          oi.value = 0
          oi
        }

        odoubreg = outputs.find :Doubleregister
        opts['o_doub'] = 0.upto(47).map{|b|
          od = odoubreg.find :"Double#{b}"
          od.value = 0.0
          od
        }

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

        ### Register

        ### Connecting to universal robot
        URUA::start_rtde opts
        URUA::start_dash opts
        URUA::start_psi opts

        ### Manifest programs
        opts['programs'] = robot.find(:Programs)
        opts['prognodes'] = {}
        opts['progs'] = []
        opts['semaphore'] = Mutex.new
        ### check if interfaces are ok
        raise if !opts['dash'] || !opts['rtde'] || !opts['psi']

        # Functionality for threading in loop
        opts['doit_state'] = Time.now.to_i
        opts['doit_progs'] = Time.now.to_i
        opts['doit_rtde'] = Time.now.to_i

        # Serious comment (we do the obvious stuff)
        opts['sn'].value = opts['dash'].get_serial_number
        opts['model'].value = opts['dash'].get_robot_model
      rescue Errno::ECONNREFUSED => e
        print 'ECONNREFUSED: '
        puts e.message
      rescue UR::Dash::Reconnect => e
        URUA::start_dash opts
        puts e.message
        puts e.backtrace
      rescue UR::Psi::Reconnect => e
        URUA::start_psi opts
        puts e.message
        puts e.backtrace
      rescue => e
        puts e.message
        puts e.backtrace
        raise
      end
    end
  end   #}}}

  def self::implementation_run #{{{
    Proc.new do
      run do |opts|
        opts['server'].run

        if Time.now.to_i - 1 > opts['doit_state']
          opts['doit_state'] = Time.now.to_i
          opts['cp'].value = opts['dash'].get_loaded_program
          opts['rs'].value = opts['dash'].get_program_state
          # update remote control state from dashboard server
          opts['mo'].value = opts['dash'].is_in_remote_control
          opts['op'].value = opts['dash'].get_operational_mode
        end

        if Time.now.to_i - 10 > opts['doit_progs']
          opts['doit_progs'] = Time.now.to_i
          Thread.new do
            opts['semaphore'].synchronize do
              # Content of thread
              # check every 10 seconds for new programs
              progs = URUA::get_robot_programs(opts)
              delete = opts['progs'] - progs
              delete.each do |d|
                d = d[0..-5]
                opts['prognodes'][d].delete!
                opts['prognodes'].delete(d)
              end
              add = progs - opts['progs']
              add.each do |a|
                a = a[0..-5]
                opts['prognodes'][a] = opts['programs'].manifest(a, opts['pf'])
              end
              opts['progs'] = progs.dup
              opts['programs'].find(:Programs).value = opts['progs']

            end unless opts['semaphore'].locked?
          end
        end

        data = opts['rtde'].receive
        if data
          # robot object
          opts['mv'].value = data['actual_main_voltage']
          opts['rv'].value = data['actual_robot_voltage']
          opts['rc'].value = data['actual_robot_current']
          opts['ss'].value = data['speed_scaling']

          #register

          #bitregister
          # 64.upto(127).map{|r|
          #   opts[]
          # }

          # State objects
          opts['rm'].value = UR::Rtde::ROBOTMODE[data['robot_mode']]
          opts['sm'].value = UR::Rtde::SAFETYMODE[data['safety_mode']]
          opts['jm'].value = UR::Rtde::JOINTMODE[data['joint_mode']]
          opts['tm'].value = UR::Rtde::TOOLMODE[data['tool_mode']]
          opts['ps'].value = UR::Rtde::PROGRAMSTATE[data['runtime_state']]
          # Axes object
          URUA::split_vector6_data(data['actual_q'],opts['aap'], opts['aapa']) # actual jont positions
          URUA::split_vector6_data(data['actual_qd'],opts['avel'], opts['avela']) # actual joint velocities
          URUA::split_vector6_data(data['actual_joint_voltage'],opts['avol'], opts['avola']) # actual joint voltage
          URUA::split_vector6_data(data['actual_current'],opts['acur'], opts['acura']) # actual current
          opts['amom'].value = data['actual_momentum'].to_s # actual_momentum

          # TCP object
          URUA::split_vector6_data(data['actual_qd'],opts['ap'], opts['apa']) # Actual TCP Pose
          URUA::split_vector6_data(data['actual_qd'],opts['as'], opts['asa']) # Actual TCP Speed
          URUA::split_vector6_data(data['actual_qd'],opts['af'], opts['afa']) # Actual TCP Force

          #speed slider or override
          if opts['ov'].value != (data['target_speed_fraction'] * 100).to_i
            opts['ov'].value = (data['target_speed_fraction'] * 100).to_i
          end

        else
          if Time.now.to_i - 10 > opts['doit_rtde']
            opts['doit_rtde'] = Time.now.to_i
            URUA::start_rtde opts
          end
        end
      rescue Errno::ECONNREFUSED => e
        print 'ECONNREFUSED: '
        puts e.message
      rescue UR::Dash::Reconnect => e
        URUA::start_dash opts
        puts e.message
        puts e.backtrace
      rescue UR::Psi::Reconnect => e
        URUA::start_psi opts
        puts e.message
        puts e.backtrace
      rescue => e
        puts e.message
        puts e.backtrace
        raise
      end
    end
  end #}}}

  def self::implementation_exit #{{{
    Proc.new do
      on exit do
        # reserved for important stuff
        p 'bye'
      end
    end
  end #}}}

end
