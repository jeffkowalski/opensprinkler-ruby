# frozen_string_literal: true

require 'yaml'
require_relative 'station'
require_relative '../constants'

module OpenSprinkler
  module Stations
    # Manages collection of stations with persistence
    class StationStore
      include Constants

      attr_reader :stations
      attr_accessor :file_path

      def initialize(file_path: nil, num_stations: 8)
        @file_path = file_path
        @stations = []
        @num_stations = num_stations
        initialize_stations
      end

      # Get station by ID
      def [](id)
        @stations[id]
      end

      # Iterate over all stations
      def each(&block)
        @stations.each(&block)
      end

      include Enumerable

      # Number of stations
      def count
        @stations.length
      end

      # Resize station array (when expansion boards change)
      def resize(num_stations)
        return if num_stations == @num_stations

        if num_stations > @num_stations
          # Add new stations
          (@num_stations...num_stations).each do |id|
            @stations << Station.new(id: id)
          end
        else
          # Remove excess stations
          @stations = @stations[0...num_stations]
        end
        @num_stations = num_stations
      end

      # Load from YAML file
      def load
        return unless @file_path && File.exist?(@file_path)

        data = YAML.load_file(@file_path, permitted_classes: [Symbol])
        return unless data.is_a?(Hash) && data['stations'].is_a?(Array)

        data['stations'].each do |station_data|
          id = station_data['id']
          next unless id && id < @stations.length

          @stations[id] = Station.from_h(station_data)
        end
      end

      # Save to YAML file
      def save
        return unless @file_path

        data = {
          'stations' => @stations.map(&:to_h)
        }
        File.write(@file_path, data.to_yaml)
      end

      # Get station names as array (for /jn API)
      def names
        @stations.map(&:name)
      end

      # Get attribute bitfield for a board (for /jn API backward compatibility)
      # Returns byte where each bit represents a station on that board
      def master1_bits(board)
        bits = 0
        8.times do |i|
          sid = board * 8 + i
          next if sid >= @stations.length

          bits |= (1 << i) if @stations[sid].master1_bound
        end
        bits
      end

      def master2_bits(board)
        bits = 0
        8.times do |i|
          sid = board * 8 + i
          next if sid >= @stations.length

          bits |= (1 << i) if @stations[sid].master2_bound
        end
        bits
      end

      def ignore_rain_bits(board)
        bits = 0
        8.times do |i|
          sid = board * 8 + i
          next if sid >= @stations.length

          bits |= (1 << i) if @stations[sid].ignore_rain_delay
        end
        bits
      end

      def ignore_sensor1_bits(board)
        bits = 0
        8.times do |i|
          sid = board * 8 + i
          next if sid >= @stations.length

          bits |= (1 << i) if @stations[sid].ignore_sensor1
        end
        bits
      end

      def ignore_sensor2_bits(board)
        bits = 0
        8.times do |i|
          sid = board * 8 + i
          next if sid >= @stations.length

          bits |= (1 << i) if @stations[sid].ignore_sensor2
        end
        bits
      end

      def disabled_bits(board)
        bits = 0
        8.times do |i|
          sid = board * 8 + i
          next if sid >= @stations.length

          bits |= (1 << i) if @stations[sid].disabled
        end
        bits
      end

      def special_bits(board)
        bits = 0
        8.times do |i|
          sid = board * 8 + i
          next if sid >= @stations.length

          bits |= (1 << i) if @stations[sid].special?
        end
        bits
      end

      def sequential_bits(board)
        bits = 0
        8.times do |i|
          sid = board * 8 + i
          next if sid >= @stations.length

          # Sequential if group_id is not the parallel group (255)
          bits |= (1 << i) if @stations[sid].group_id != Constants::PARALLEL_GROUP_ID
        end
        bits
      end

      def activate_relay_bits(board)
        bits = 0
        8.times do |i|
          sid = board * 8 + i
          next if sid >= @stations.length

          bits |= (1 << i) if @stations[sid].activate_relay
        end
        bits
      end

      # Get all group IDs (for /jn API)
      def group_ids
        @stations.map(&:group_id)
      end

      # Set attribute from bitfield (for /cs API backward compatibility)
      def set_master1_bits(board, bits)
        8.times do |i|
          sid = board * 8 + i
          next if sid >= @stations.length

          @stations[sid].master1_bound = (bits & (1 << i)) != 0
        end
      end

      def set_master2_bits(board, bits)
        8.times do |i|
          sid = board * 8 + i
          next if sid >= @stations.length

          @stations[sid].master2_bound = (bits & (1 << i)) != 0
        end
      end

      def set_ignore_rain_bits(board, bits)
        8.times do |i|
          sid = board * 8 + i
          next if sid >= @stations.length

          @stations[sid].ignore_rain_delay = (bits & (1 << i)) != 0
        end
      end

      def set_ignore_sensor1_bits(board, bits)
        8.times do |i|
          sid = board * 8 + i
          next if sid >= @stations.length

          @stations[sid].ignore_sensor1 = (bits & (1 << i)) != 0
        end
      end

      def set_ignore_sensor2_bits(board, bits)
        8.times do |i|
          sid = board * 8 + i
          next if sid >= @stations.length

          @stations[sid].ignore_sensor2 = (bits & (1 << i)) != 0
        end
      end

      def set_disabled_bits(board, bits)
        8.times do |i|
          sid = board * 8 + i
          next if sid >= @stations.length

          @stations[sid].disabled = (bits & (1 << i)) != 0
        end
      end

      # Get special stations data (for /je API)
      def special_stations
        result = {}
        @stations.each_with_index do |station, id|
          next unless station.special?

          result[id.to_s] = {
            'st' => station.type,
            'sd' => encode_special_data(station)
          }
        end
        result
      end

      private

      def initialize_stations
        @num_stations.times do |id|
          @stations << Station.new(id: id)
        end
      end

      # Encode special station data to hex string (for API compatibility)
      def encode_special_data(station)
        return '' unless station.special_data

        case station.type
        when StationType::GPIO
          data = station.special_data
          # 3 bytes: pin (2 bytes) + active state (1 byte)
          format('%04x%02x', data.pin, data.active_high ? 1 : 0)
        when StationType::HTTP, StationType::HTTPS
          data = station.special_data
          # CSV format: host,port,on_cmd,off_cmd
          "#{data.host},#{data.port},#{data.on_command},#{data.off_command}"
        when StationType::REMOTE_IP
          data = station.special_data
          # 14 bytes: IP (8 hex chars) + port (4 hex chars) + station (2 hex chars)
          ip_parts = data.ip.split('.').map(&:to_i)
          ip_hex = ip_parts.pack('C4').unpack1('H*')
          format('%s%04x%02x', ip_hex, data.port, data.station_id)
        else
          ''
        end
      end
    end
  end
end
