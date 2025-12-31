# frozen_string_literal: true

require 'roda'
require 'json'
require 'digest/md5'
require_relative '../constants'

module OpenSprinkler
  module Web
    # Main Roda application for OpenSprinkler API
    #
    # Implements the 23 two-character URL endpoints:
    # Read:  /jc, /jo, /jp, /js, /jn, /je, /jl, /ja
    # Write: /cv, /co, /cp, /dp, /up, /mp, /cs, /cm, /cr, /pq, /su, /cu, /sp, /db, /dl
    class App < Roda
      plugin :json
      plugin :all_verbs
      plugin :request_headers

      # API result codes
      module Result
        SUCCESS        = { 'result' => 1 }
        UNAUTHORIZED   = { 'result' => 2 }
        MISMATCH       = { 'result' => 3 }
        DATA_MISSING   = { 'result' => 16 }
        OUT_OF_BOUND   = { 'result' => 17 }
        FORMAT_ERROR   = { 'result' => 18 }
        PAGE_NOT_FOUND = { 'result' => 32 }
        NOT_PERMITTED  = { 'result' => 48 }
      end

      # Set the controller instance
      def self.controller=(ctrl)
        @controller = ctrl
      end

      def self.controller
        @controller
      end

      # Set options (for password verification)
      def self.options=(opts)
        @options = opts
      end

      def self.options
        @options
      end

      route do |r|
        # Helper to get controller
        controller = App.controller
        options = App.options

        # Password verification helper
        verify_password = lambda do
          return true if options&.int&.[](:ignore_password) == 1

          pw = r.params['pw']
          return false unless pw

          stored_hash = options&.string&.[](:password) || Constants::Defaults::PASSWORD
          pw == stored_hash
        end

        # JSON response helper
        json_response = ->(data) { response['Content-Type'] = 'application/json'; data.to_json }

        # Root - redirect to UI
        r.root do
          r.redirect 'https://ui.opensprinkler.com'
        end

        # ============ Read Endpoints ============

        # /jc - Controller status (main status endpoint)
        r.get 'jc' do
          unless verify_password.call
            json_response.call(Result::UNAUTHORIZED)
          else
            json_response.call(controller.controller_status)
          end
        end

        # /jo - Options
        r.get 'jo' do
          unless verify_password.call
            json_response.call(Result::UNAUTHORIZED)
          else
            json_response.call(options_to_api(options))
          end
        end

        # /jp - Programs
        r.get 'jp' do
          unless verify_password.call
            json_response.call(Result::UNAUTHORIZED)
          else
            json_response.call(programs_to_api(controller))
          end
        end

        # /js - Station status (which stations are on)
        r.get 'js' do
          unless verify_password.call
            json_response.call(Result::UNAUTHORIZED)
          else
            json_response.call(station_status_to_api(controller))
          end
        end

        # /jn - Station names
        r.get 'jn' do
          unless verify_password.call
            json_response.call(Result::UNAUTHORIZED)
          else
            json_response.call(station_names_to_api(controller))
          end
        end

        # /je - Station special data (attributes)
        r.get 'je' do
          unless verify_password.call
            json_response.call(Result::UNAUTHORIZED)
          else
            json_response.call(station_special_to_api(controller))
          end
        end

        # /jl - Logs
        r.get 'jl' do
          unless verify_password.call
            json_response.call(Result::UNAUTHORIZED)
          else
            # Parse date parameters
            start_date = r.params['start']&.to_i || 0
            end_date = r.params['end']&.to_i || Time.now.to_i
            json_response.call(logs_to_api(controller, start_date, end_date))
          end
        end

        # /ja - All data (combined endpoint)
        r.get 'ja' do
          unless verify_password.call
            json_response.call(Result::UNAUTHORIZED)
          else
            json_response.call(all_data_to_api(controller, options))
          end
        end

        # ============ Write Endpoints ============

        # /cv - Change controller values
        # Parameters: rsn (reset all), en (enable), rd (rain delay hours), rbt (reboot)
        r.get 'cv' do
          unless verify_password.call
            json_response.call(Result::UNAUTHORIZED)
          else
            result = handle_change_values(r.params, controller)
            json_response.call(result)
          end
        end

        # /co - Change options
        r.get 'co' do
          unless verify_password.call
            json_response.call(Result::UNAUTHORIZED)
          else
            result = handle_change_options(r.params, options)
            json_response.call(result)
          end
        end

        # /cp - Change program (create/update)
        r.get 'cp' do
          unless verify_password.call
            json_response.call(Result::UNAUTHORIZED)
          else
            result = handle_change_program(r.params, controller)
            json_response.call(result)
          end
        end

        # /dp - Delete program
        r.get 'dp' do
          unless verify_password.call
            json_response.call(Result::UNAUTHORIZED)
          else
            result = handle_delete_program(r.params, controller)
            json_response.call(result)
          end
        end

        # /up - Move program up
        r.get 'up' do
          unless verify_password.call
            json_response.call(Result::UNAUTHORIZED)
          else
            result = handle_move_program_up(r.params, controller)
            json_response.call(result)
          end
        end

        # /mp - Move program (reorder)
        r.get 'mp' do
          unless verify_password.call
            json_response.call(Result::UNAUTHORIZED)
          else
            result = handle_move_program(r.params, controller)
            json_response.call(result)
          end
        end

        # /cs - Change station attributes
        r.get 'cs' do
          unless verify_password.call
            json_response.call(Result::UNAUTHORIZED)
          else
            result = handle_change_stations(r.params, controller)
            json_response.call(result)
          end
        end

        # /cm - Manual control (turn station on/off)
        r.get 'cm' do
          unless verify_password.call
            json_response.call(Result::UNAUTHORIZED)
          else
            result = handle_manual_control(r.params, controller)
            json_response.call(result)
          end
        end

        # /cr - Run once program
        r.get 'cr' do
          unless verify_password.call
            json_response.call(Result::UNAUTHORIZED)
          else
            result = handle_run_once(r.params, controller)
            json_response.call(result)
          end
        end

        # /pq - Pause/resume queue
        r.get 'pq' do
          unless verify_password.call
            json_response.call(Result::UNAUTHORIZED)
          else
            result = handle_pause_queue(r.params, controller)
            json_response.call(result)
          end
        end

        # /dl - Delete logs
        r.get 'dl' do
          unless verify_password.call
            json_response.call(Result::UNAUTHORIZED)
          else
            result = handle_delete_logs(r.params, controller)
            json_response.call(result)
          end
        end

        # 404 for unknown routes
        r.on do
          json_response.call(Result::PAGE_NOT_FOUND)
        end
      end

      private

      # Convert options to API format
      def options_to_api(options)
        return {} unless options

        int_opts = options.int
        str_opts = options.string

        {
          'fwv' => Constants::FW_VERSION,
          'fwm' => Constants::FW_MINOR,
          'tz' => int_opts[:timezone],
          'ntp' => int_opts[:use_ntp],
          'dhcp' => int_opts[:use_dhcp],
          'hp0' => int_opts[:httpport_0],
          'hp1' => int_opts[:httpport_1],
          'hwv' => int_opts[:hw_version],
          'ext' => int_opts[:ext_boards],
          'sdt' => int_opts[:station_delay_time],
          'mas' => int_opts[:master_station],
          'mton' => int_opts[:master_on_adj],
          'mtof' => int_opts[:master_off_adj],
          'wl' => int_opts[:water_percentage],
          'den' => int_opts[:device_enable],
          'ipas' => int_opts[:ignore_password],
          'devid' => int_opts[:device_id],
          'con' => int_opts[:lcd_contrast],
          'lit' => int_opts[:lcd_backlight],
          'dim' => int_opts[:lcd_dimming],
          'bst' => int_opts[:boost_time],
          'uwt' => int_opts[:use_weather],
          'lg' => int_opts[:enable_logging],
          'mas2' => int_opts[:master_station_2],
          'mton2' => int_opts[:master_on_adj_2],
          'mtof2' => int_opts[:master_off_adj_2],
          'fpr0' => int_opts[:pulse_rate_0],
          'fpr1' => int_opts[:pulse_rate_1],
          're' => int_opts[:remote_ext_mode],
          'sar' => int_opts[:spe_auto_refresh],
          'sn1t' => int_opts[:sensor1_type],
          'sn1o' => int_opts[:sensor1_option],
          'sn2t' => int_opts[:sensor2_type],
          'sn2o' => int_opts[:sensor2_option],
          'sn1on' => int_opts[:sensor1_on_delay],
          'sn1of' => int_opts[:sensor1_off_delay],
          'sn2on' => int_opts[:sensor2_on_delay],
          'sn2of' => int_opts[:sensor2_off_delay],
          'loc' => str_opts&.[](:location) || '',
          'jsp' => str_opts&.[](:javascript_url) || '',
          'wsp' => str_opts&.[](:weather_url) || '',
          'dname' => str_opts&.[](:device_name) || ''
        }
      end

      # Convert programs to API format
      def programs_to_api(controller)
        store = controller.program_store
        num_boards = controller.options.int.num_boards

        {
          'nprogs' => store.count,
          'nboards' => num_boards,
          'mnp' => Scheduling::ProgramStore::MAX_PROGRAMS,
          'mnst' => Scheduling::Program::MAX_STARTTIMES,
          'pnsize' => Constants::STATION_NAME_SIZE,
          'pd' => store.map { |p| program_to_api_array(p) }
        }
      end

      def program_to_api_array(program)
        [
          program.flag_byte,
          program.days[0],
          program.days[1],
          program.starttimes,
          program.durations,
          program.name,
          [
            program.date_range_enabled ? 1 : 0,
            program.date_range[0],
            program.date_range[1]
          ]
        ]
      end

      # Station status to API format
      def station_status_to_api(controller)
        stations = controller.stations
        running = controller.scheduler.queue.active_station_ids(Time.now.to_i)

        sn = Array.new(stations.count) { |i| running.include?(i) ? 1 : 0 }
        nboards = controller.options.int.num_boards

        {
          'sn' => sn,
          'nboards' => nboards
        }
      end

      # Station names to API format
      def station_names_to_api(controller)
        stations = controller.stations
        {
          'snames' => stations.map(&:name),
          'maxlen' => Constants::STATION_NAME_SIZE
        }
      end

      # Station special data to API format
      def station_special_to_api(controller)
        stations = controller.stations
        num_boards = controller.options.int.num_boards

        # Build arrays of bitfields for each board
        masop = (0...num_boards).map { |b| stations.master1_bits(b) }
        masop2 = (0...num_boards).map { |b| stations.master2_bits(b) }
        ignore_rain = (0...num_boards).map { |b| stations.ignore_rain_bits(b) }
        ignore_sn1 = (0...num_boards).map { |b| stations.ignore_sensor1_bits(b) }
        ignore_sn2 = (0...num_boards).map { |b| stations.ignore_sensor2_bits(b) }
        act_relay = (0...num_boards).map { |b| stations.activate_relay_bits(b) }
        stn_dis = (0...num_boards).map { |b| stations.disabled_bits(b) }
        stn_seq = (0...num_boards).map { |b| stations.sequential_bits(b) }
        stn_spe = (0...num_boards).map { |b| stations.special_bits(b) }

        {
          'masop' => masop,
          'masop2' => masop2,
          'ignore_rain' => ignore_rain,
          'ignore_sn1' => ignore_sn1,
          'ignore_sn2' => ignore_sn2,
          'act_relay' => act_relay,
          'stn_dis' => stn_dis,
          'stn_seq' => stn_seq,
          'stn_spe' => stn_spe,
          'stn_grp' => stations.group_ids,
          'stn_type' => stations.map(&:type)
        }
      end

      # Logs to API format
      def logs_to_api(controller, start_date, end_date)
        controller.log_store.get_entries(start_time: start_date, end_time: end_date)
      end

      # ========== Write Endpoint Handlers ==========

      # Handle /cv - change controller values
      # rsn: reset all stations
      # rrsn: remote reset all stations (same as rsn)
      # en: enable/disable controller
      # rd: set rain delay (hours)
      # rbt: reboot (ignored in Ruby version)
      def handle_change_values(params, controller)
        # Reset all stations
        if params['rsn']
          controller.stop_all_stations
        end

        # Remote reset (same behavior)
        if params['rrsn']
          controller.stop_all_stations
        end

        # Enable/disable controller
        if params.key?('en')
          en_val = params['en'].to_i
          controller.options.int[:device_enable] = en_val
          controller.options.save if controller.options.respond_to?(:save)
        end

        # Rain delay
        if params.key?('rd')
          rd_val = params['rd'].to_i
          controller.set_rain_delay(rd_val)
        end

        # Reboot - in Ruby version we just ignore this or could restart the service
        # if params.key?('rbt') && params['rbt'].to_i == 1
        #   # Could exec restart command here
        # end

        Result::SUCCESS
      end

      # Handle /co - change options
      def handle_change_options(params, options)
        return Result::DATA_MISSING unless options

        int_opts = options.int
        str_opts = options.string

        # Map API parameter names to internal option keys
        int_mappings = {
          'tz' => :timezone,
          'ntp' => :use_ntp,
          'dhcp' => :use_dhcp,
          'hp0' => :httpport_0,
          'hp1' => :httpport_1,
          'ext' => :ext_boards,
          'sdt' => :station_delay_time,
          'mas' => :master_station,
          'mton' => :master_on_adj,
          'mtof' => :master_off_adj,
          'wl' => :water_percentage,
          'den' => :device_enable,
          'ipas' => :ignore_password,
          'devid' => :device_id,
          'con' => :lcd_contrast,
          'lit' => :lcd_backlight,
          'dim' => :lcd_dimming,
          'bst' => :boost_time,
          'uwt' => :use_weather,
          'lg' => :enable_logging,
          'mas2' => :master_station_2,
          'mton2' => :master_on_adj_2,
          'mtof2' => :master_off_adj_2,
          'fpr0' => :pulse_rate_0,
          'fpr1' => :pulse_rate_1,
          're' => :remote_ext_mode,
          'sar' => :spe_auto_refresh,
          'sn1t' => :sensor1_type,
          'sn1o' => :sensor1_option,
          'sn2t' => :sensor2_type,
          'sn2o' => :sensor2_option,
          'sn1on' => :sensor1_on_delay,
          'sn1of' => :sensor1_off_delay,
          'sn2on' => :sensor2_on_delay,
          'sn2of' => :sensor2_off_delay
        }

        str_mappings = {
          'loc' => :location,
          'jsp' => :javascript_url,
          'wsp' => :weather_url,
          'dname' => :device_name
        }

        # Apply integer options
        int_mappings.each do |api_key, opt_key|
          if params.key?(api_key)
            int_opts[opt_key] = params[api_key].to_i
          end
        end

        # Apply string options
        str_mappings.each do |api_key, opt_key|
          if params.key?(api_key)
            str_opts[opt_key] = params[api_key]
          end
        end

        # Handle password change (npw = new password MD5 hash)
        if params.key?('npw')
          str_opts[:password] = params['npw']
        end

        # Handle 'o' parameter - bulk options as comma-separated integers
        # This is used by some API versions for backwards compatibility
        if params.key?('o')
          values = params['o'].split(',').map(&:to_i)
          # Map positional values to options (subset of common options)
          option_order = %i[timezone use_ntp use_dhcp ext_boards station_delay_time
                           master_station master_on_adj master_off_adj water_percentage
                           device_enable ignore_password]
          values.each_with_index do |val, idx|
            break if idx >= option_order.length

            int_opts[option_order[idx]] = val
          end
        end

        options.save if options.respond_to?(:save)
        Result::SUCCESS
      end

      # Handle /cp - change/create program
      # pid: program index (0-based, -1 for new)
      # v: program data array as JSON
      # name: program name
      def handle_change_program(params, controller)
        return Result::DATA_MISSING unless params.key?('v')

        begin
          program_data = JSON.parse(params['v'])
        rescue JSON::ParserError
          return Result::FORMAT_ERROR
        end

        pid = params['pid']&.to_i || -1
        store = controller.program_store

        if pid < 0 || pid >= store.count
          # Create new program
          return Result::OUT_OF_BOUND if store.count >= Scheduling::ProgramStore::MAX_PROGRAMS

          program = parse_program_data(program_data, params['name'])
          store.add(program)
        else
          # Update existing program
          program = store[pid]
          return Result::OUT_OF_BOUND unless program

          update_program_from_data(program, program_data, params['name'])
        end

        store.save
        Result::SUCCESS
      end

      # Handle /dp - delete program
      def handle_delete_program(params, controller)
        return Result::DATA_MISSING unless params.key?('pid')

        pid = params['pid'].to_i
        store = controller.program_store

        return Result::OUT_OF_BOUND if pid < 0 || pid >= store.count

        store.delete(pid)
        store.save
        Result::SUCCESS
      end

      # Handle /up - move program up (swap with previous)
      def handle_move_program_up(params, controller)
        return Result::DATA_MISSING unless params.key?('pid')

        pid = params['pid'].to_i
        store = controller.program_store

        return Result::OUT_OF_BOUND if pid <= 0 || pid >= store.count

        store.move_up(pid)
        store.save
        Result::SUCCESS
      end

      # Handle /mp - move program to new position
      def handle_move_program(params, controller)
        return Result::DATA_MISSING unless params.key?('from') && params.key?('to')

        from = params['from'].to_i
        to = params['to'].to_i
        store = controller.program_store

        return Result::OUT_OF_BOUND if from < 0 || from >= store.count
        return Result::OUT_OF_BOUND if to < 0 || to >= store.count

        store.move(from, to)
        store.save
        Result::SUCCESS
      end

      # Handle /cs - change station attributes
      # Supports various formats for station data
      def handle_change_stations(params, controller)
        stations = controller.stations
        num_boards = controller.options.int.num_boards

        # Station names (snames or s[n])
        if params.key?('snames')
          begin
            names = JSON.parse(params['snames'])
            names.each_with_index do |name, idx|
              stations[idx]&.name = name.to_s[0, Constants::STATION_NAME_SIZE]
            end
          rescue JSON::ParserError
            return Result::FORMAT_ERROR
          end
        end

        # Individual station name (sn=name, sid=station_id)
        if params.key?('sn') && params.key?('sid')
          sid = params['sid'].to_i
          if sid >= 0 && sid < stations.count
            stations[sid].name = params['sn'].to_s[0, Constants::STATION_NAME_SIZE]
          end
        end

        # Master operation bits (masop for board arrays)
        if params.key?('masop')
          begin
            bits = JSON.parse(params['masop'])
            bits.each_with_index do |byte, board|
              stations.set_master1_bits(board, byte) if board < num_boards
            end
          rescue JSON::ParserError
            return Result::FORMAT_ERROR
          end
        end

        # Master 2 operation bits
        if params.key?('masop2')
          begin
            bits = JSON.parse(params['masop2'])
            bits.each_with_index do |byte, board|
              stations.set_master2_bits(board, byte) if board < num_boards
            end
          rescue JSON::ParserError
            return Result::FORMAT_ERROR
          end
        end

        # Ignore rain bits
        if params.key?('ignore_rain')
          begin
            bits = JSON.parse(params['ignore_rain'])
            bits.each_with_index do |byte, board|
              stations.set_ignore_rain_bits(board, byte) if board < num_boards
            end
          rescue JSON::ParserError
            return Result::FORMAT_ERROR
          end
        end

        # Ignore sensor1 bits
        if params.key?('ignore_sn1')
          begin
            bits = JSON.parse(params['ignore_sn1'])
            bits.each_with_index do |byte, board|
              stations.set_ignore_sensor1_bits(board, byte) if board < num_boards
            end
          rescue JSON::ParserError
            return Result::FORMAT_ERROR
          end
        end

        # Ignore sensor2 bits
        if params.key?('ignore_sn2')
          begin
            bits = JSON.parse(params['ignore_sn2'])
            bits.each_with_index do |byte, board|
              stations.set_ignore_sensor2_bits(board, byte) if board < num_boards
            end
          rescue JSON::ParserError
            return Result::FORMAT_ERROR
          end
        end

        # Disable bits
        if params.key?('stn_dis')
          begin
            bits = JSON.parse(params['stn_dis'])
            bits.each_with_index do |byte, board|
              stations.set_disabled_bits(board, byte) if board < num_boards
            end
          rescue JSON::ParserError
            return Result::FORMAT_ERROR
          end
        end

        # Group IDs
        if params.key?('stn_grp')
          begin
            groups = JSON.parse(params['stn_grp'])
            groups.each_with_index do |group_id, idx|
              stations[idx]&.group_id = group_id.to_i
            end
          rescue JSON::ParserError
            return Result::FORMAT_ERROR
          end
        end

        stations.save
        Result::SUCCESS
      end

      # Handle /cm - manual station control
      # sid: station id (0-based)
      # en: enable (1) or disable (0)
      # t: duration in seconds (for enable)
      def handle_manual_control(params, controller)
        return Result::DATA_MISSING unless params.key?('sid')

        sid = params['sid'].to_i
        return Result::OUT_OF_BOUND if sid < 0 || sid >= controller.stations.count

        en = params['en']&.to_i || 0
        duration = params['t']&.to_i || 0

        if en == 1
          # Turn station on
          return Result::DATA_MISSING if duration <= 0

          controller.manual_start_station(sid, duration)
        else
          # Turn station off
          controller.manual_stop_station(sid)
        end

        Result::SUCCESS
      end

      # Handle /cr - run once program
      # t: array of durations (JSON) for each station
      # uwt: use weather adjustment (0/1)
      def handle_run_once(params, controller)
        return Result::DATA_MISSING unless params.key?('t')

        begin
          durations = JSON.parse(params['t'])
        rescue JSON::ParserError
          return Result::FORMAT_ERROR
        end

        return Result::FORMAT_ERROR unless durations.is_a?(Array)

        use_weather = (params['uwt']&.to_i || 0) == 1

        controller.run_once(
          durations.map(&:to_i),
          use_weather: use_weather
        )

        Result::SUCCESS
      end

      # Handle /pq - pause/resume queue
      # dur: pause duration in seconds (0 = resume)
      def handle_pause_queue(params, controller)
        dur = params['dur']&.to_i || 0

        if dur > 0
          controller.pause(dur)
        else
          controller.resume
        end

        Result::SUCCESS
      end

      # Handle /dl - delete logs
      # day: delete logs before this day (0 = delete all)
      def handle_delete_logs(params, controller)
        day = params['day']&.to_i || 0

        if day == 0
          controller.log_store.clear
        else
          before_date = Time.at(day * 86400)
          controller.log_store.delete_before(before_date)
        end

        Result::SUCCESS
      end

      # ========== Program Parsing Helpers ==========

      def parse_program_data(data, name = nil)
        program = Scheduling::Program.new
        update_program_from_data(program, data, name)
        program
      end

      def update_program_from_data(program, data, name = nil)
        # Data format: [flag, days0, days1, starttimes[], durations[], name, daterange]
        program.flag_byte = data[0].to_i if data[0]
        program.days = [data[1].to_i, data[2].to_i] if data[1] && data[2]

        if data[3].is_a?(Array)
          program.starttimes = data[3].map(&:to_i)
        end

        if data[4].is_a?(Array)
          program.durations = data[4].map(&:to_i)
        end

        program.name = (name || data[5] || 'Program').to_s

        # Date range: [enabled, start, end]
        if data[6].is_a?(Array) && data[6].length >= 3
          program.date_range_enabled = data[6][0].to_i == 1
          program.date_range = [data[6][1].to_i, data[6][2].to_i]
        end
      end

      # All data combined
      def all_data_to_api(controller, options)
        {
          'settings' => controller.controller_status,
          'programs' => programs_to_api(controller),
          'options' => options_to_api(options),
          'status' => station_status_to_api(controller),
          'stations' => station_names_to_api(controller).merge(station_special_to_api(controller))
        }
      end
    end
  end
end
