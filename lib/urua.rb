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
      p "speed"
      speed_names, speed_types = conf.get_recipe opts['rtde_config_recipe_speed']
      opts['speed'] = opts['rtde'].send_input_setup(speed_names, speed_types)
      opts['speed']['speed_slider_mask'] = 1
      opts['ov'].value = opts['speed']['speed_slider_fraction'].to_i
    end

    ### Set register
    if opts['rtde_config_recipe_in']
      p "regwrite"
      input_names, input_types = conf.get_recipe opts['rtde_config_recipe_in']
      opts['in'] = opts['rtde'].send_input_setup(input_names,input_types)
      #opts['input_int_register_0'].value = opts['reg']['input_int_register_0']
      p "regfinish"
    end

    ### Setup output
    if not opts['rtde'].send_output_setup(output_names, output_types,10)
      puts 'Unable to configure output'
    end
    if not opts['rtde'].send_start
      puts 'Unable to start synchronization'
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
    opts['rtde_config_recipe_in'] ||= 'in'

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
              p "no ned"
              0.upto(127) do |i|
                b.add_variable_rw :"Bit#{i}" do |node,value,external|
                  puts "floistbeste"
                  opts['in']["input_bit_register_"+i.to_s] = value.to_i
                  opts['rtde'].send(opts['in'])
                end
              end
              #b.add_variables :Bit0 , :Bit1 , :Bit2 , :Bit3 , :Bit4 , :Bit5 , :Bit6 , :Bit7 , :Bit8 , :Bit9 , :Bit10 , :Bit11 , :Bit12 , :Bit13 , :Bit14 , :Bit15 , :Bit16 , :Bit17 , :Bit18 , :Bit19 , :Bit20 , :Bit21 , :Bit22 , :Bit23 , :Bit24 , :Bit25 , :Bit26 , :Bit27 , :Bit28 , :Bit29 , :Bit30 , :Bit31 , :Bit32 , :Bit33 , :Bit34 , :Bit35 , :Bit36 , :Bit37 , :Bit38 , :Bit39 , :Bit40 , :Bit41 , :Bit42 , :Bit43 , :Bit44 , :Bit45 , :Bit46 , :Bit47 , :Bit48 , :Bit49 , :Bit50
            }
            i.add_object(:Intregister, opts['server'].types.folder).tap {|i|
              i.add_variables :Int0 , :Int1 , :Int2 , :Int3 , :Int4 , :Int5 , :Int6 , :Int7 , :Int8 , :Int9 , :Int10 , :Int11 , :Int12 , :Int13 , :Int14 , :Int15 , :Int16 , :Int17 , :Int18 , :Int19 , :Int20 , :Int21 , :Int22 , :Int23 , :Int24 , :Int25 , :Int26 , :Int27 , :Int28 , :Int29 , :Int30 , :Int31 , :Int32 , :Int33 , :Int34 , :Int35 , :Int36 , :Int37 , :Int38 , :Int39 , :Int40 , :Int41 , :Int42 , :Int43 , :Int44 , :Int45 , :Int46 , :Int47 , :Int48 , :Int49 , :Int50
            }
            i.add_object(:Doubleregister, opts['server'].types.folder).tap {|d|
              d.add_variables :Double0 , :Double1 , :Double2 , :Double3 , :Double4 , :Double5 , :Double6 , :Double7 , :Double8 , :Double9 , :Double10 , :Double11 , :Double12 , :Double13 , :Double14 , :Double15 , :Double16 , :Double17 , :Double18 , :Double19 , :Double20 , :Double21 , :Double22 , :Double23 , :Double24 , :Double25 , :Double26 , :Double27 , :Double28 , :Double29 , :Double30 , :Double31 , :Double32 , :Double33 , :Double34 , :Double35 , :Double36 , :Double37 , :Double38 , :Double39 , :Double40 , :Double41 , :Double42 , :Double43 , :Double44 , :Double45 , :Double46 , :Double47 , :Double48 , :Double49 , :Double50
            }
          }
          r.add_object(:Outputs, opts['server'].types.folder).tap{|o|
            o.add_variables :Bit0 , :Bit1 , :Bit2 , :Bit3 , :Bit4 , :Bit5 , :Bit6 , :Bit7 , :Bit8 , :Bit9 , :Bit10 , :Bit11 , :Bit12 , :Bit13 , :Bit14 , :Bit15 , :Bit16 , :Bit17 , :Bit18 , :Bit19 , :Bit20 , :Bit21 , :Bit22 , :Bit23 , :Bit24 , :Bit25 , :Bit26 , :Bit27 , :Bit28 , :Bit29 , :Bit30 , :Bit31 , :Bit32 , :Bit33 , :Bit34 , :Bit35 , :Bit36 , :Bit37 , :Bit38 , :Bit39 , :Bit40 , :Bit41 , :Bit42 , :Bit43 , :Bit44 , :Bit45 , :Bit46 , :Bit47 , :Bit48 , :Bit49 , :Bit50
            o.add_variables :Int0 , :Int1 , :Int2 , :Int3 , :Int4 , :Int5 , :Int6 , :Int7 , :Int8 , :Int9 , :Int10 , :Int11 , :Int12 , :Int13 , :Int14 , :Int15 , :Int16 , :Int17 , :Int18 , :Int19 , :Int20 , :Int21 , :Int22 , :Int23 , :Int24 , :Int25 , :Int26 , :Int27 , :Int28 , :Int29 , :Int30 , :Int31 , :Int32 , :Int33 , :Int34 , :Int35 , :Int36 , :Int37 , :Int38 , :Int39 , :Int40 , :Int41 , :Int42 , :Int43 , :Int44 , :Int45 , :Int46 , :Int47 , :Int48 , :Int49 , :Int50
            o.add_variables :Double0 , :Double1 , :Double2 , :Double3 , :Double4 , :Double5 , :Double6 , :Double7 , :Double8 , :Double9 , :Double10 , :Double11 , :Double12 , :Double13 , :Double14 , :Double15 , :Double16 , :Double17 , :Double18 , :Double19 , :Double20 , :Double21 , :Double22 , :Double23 , :Double24 , :Double25 , :Double26 , :Double27 , :Double28 , :Double29 , :Double30 , :Double31 , :Double32 , :Double33 , :Double34 , :Double35 , :Double36 , :Double37 , :Double38 , :Double39 , :Double40 , :Double41 , :Double42 , :Double43 , :Double44 , :Double45 , :Double46 , :Double47 , :Double48 , :Double49 , :Double50
          }
        }

        # RobotObjectType
        rt = opts['server'].types.add_object_type(:RobotType).tap { |r|
          r.add_variables :SerialNumber, :RobotModel
          r.add_object(:State, opts['server'].types.folder).tap{ |s|
            s.add_variables :CurrentProgram, :RobotMode, :RobotState, :JointMode, :SafetyMode, :ToolMode, :ProgramState, :SpeedScaling, :Remote, :OperationalMode
            s.add_variable_rw :Override
          }
          r.add_object(:SafetyBoard, opts['server'].types.folder).tap{ |r|
            r.add_variables :MainVoltage, :RobotVoltage, :RobotCurrent
          }

          ### Has to be deleted due to new Registerrype
          # r.add_object(:Register, opts['server'].types.folder).tap{ |r|
          #
          #   r.add_variables :Output_int_register_0, :Output_int_register_1
          #
          #
          #   r.add_method :WriteRegister, name: OPCUA::TYPES::STRING, value: OPCUA::TYPES::STRING do |node, name, value|
          #
          #     # only test if writing works
          #     puts value
          #     puts name.downcase
          #     puts opts['reg'].to_s
          #     opts['speed']['speed_slider_fraction'] = 0.2
          #     opts['rtde'].send(opts['speed'])
          #     #puts opts['reg'][name.downcase]
          #     opts['reg'][name.downcase] = value.to_i
          #     opts['rtde'].send(opts['reg'])
          #   end
          #   p "2"
          #}
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
        #how to reduce code and opts values for all registers
        inputs = register.find :Inputs
        ibitreg = inputs.find :Bitregister
        opts['in_bits'] = ibitreg.find :Bit0 , :Bit1 , :Bit2 , :Bit3 , :Bit4 , :Bit5 , :Bit6 , :Bit7 , :Bit8 , :Bit9 , :Bit10 , :Bit11 , :Bit12 , :Bit13 , :Bit14 , :Bit15 , :Bit16 , :Bit17 , :Bit18 , :Bit19 , :Bit20 , :Bit21 , :Bit22 , :Bit23 , :Bit24 , :Bit25 , :Bit26 , :Bit27 , :Bit28 , :Bit29 , :Bit30 , :Bit31 , :Bit32 , :Bit33 , :Bit34 , :Bit35 , :Bit36 , :Bit37 , :Bit38 , :Bit39 , :Bit40 , :Bit41 , :Bit42 , :Bit43 , :Bit44 , :Bit45 , :Bit46 , :Bit47 , :Bit48 , :Bit49 , :Bit50
        p opts['in_bits'][0].value = 0
        iintreg = inputs.find :Intregister
        idoubreg = inputs.find :Doubleregister
        outputs = register.find :Outputs
        obitreg = outputs.find :Bitregister
        ointreg = outputs.find :Intregister
        odoubreg = outputs.find :Doubleregister
        opts['out_int'] = outputs.find :Int0 , :Int1 , :Int2 , :Int3 , :Int4 , :Int5 , :Int6 , :Int7 , :Int8 , :Int9 , :Int10 , :Int11 , :Int12 , :Int13 , :Int14 , :Int15 , :Int16 , :Int17 , :Int18 , :Int19 , :Int20 , :Int21 , :Int22 , :Int23 , :Int24 , :Int25 , :Int26 , :Int27 , :Int28 , :Int29 , :Int30 , :Int31 , :Int32 , :Int33 , :Int34 , :Int35 , :Int36 , :Int37 , :Int38 , :Int39 , :Int40 , :Int41 , :Int42 , :Int43 , :Int44 , :Int45 , :Int46 , :Int47 , :Int48 , :Int49 , :Int50

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
        #opts['regfol'] = robot.find :Register
        #opts['regouti0'] = opts['regfol'].find :Output_int_register_0

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
          #opts['regouti0'].value = data['output_int_register_0']
          opts['in_bits'].each_with_index do |inbits,i|
            inbits.value = data["input_bit_register_"+i.to_s]
          end
          opts['out_int'].each_with_index do |outint,i|
            outint.value = data["output_int_register_"+i.to_s]
          end
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

          ######TODO Fix Write Values that opc ua does not overwrite the speed slider mask of manual changes
          # Write values
          if opts['rtde_config_recipe_speed']
            #if opts['ov'] != opts['ovold']
            #  if opts['ov'] == data['target_speed_fraction']
            #opts['speed']['speed_slider_fraction'] = opts['ov'].value / 100.0
            #opts['rtde'].send(opts['speed'])
            #opts['ovold'] = data['target_speed_fraction']
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
