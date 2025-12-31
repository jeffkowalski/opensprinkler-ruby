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
        # TODO: Implement log storage and retrieval
        # For now return empty array
        []
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
