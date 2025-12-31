# frozen_string_literal: true

require_relative '../constants'

module OpenSprinkler
  module Stations
    # Represents a single irrigation station (zone)
    #
    # Each station has:
    # - A name (up to 32 characters)
    # - Attributes (master binding, sensor ignore flags, group ID, etc.)
    # - A type (standard, GPIO, HTTP, RF, remote)
    # - Type-specific data for special stations
    class Station
      include Constants

      attr_accessor :name, :type, :group_id
      attr_accessor :master1_bound, :master2_bound
      attr_accessor :ignore_sensor1, :ignore_sensor2, :ignore_rain_delay
      attr_accessor :disabled, :activate_relay
      attr_reader :special_data

      def initialize(id:, name: nil)
        @id = id
        @name = name || format('S%02d', id + 1)
        @type = StationType::STANDARD
        @group_id = 0  # 0 = sequential group 0, 255 = parallel
        @special_data = nil

        # Attribute flags
        @master1_bound = false
        @master2_bound = false
        @ignore_sensor1 = false
        @ignore_sensor2 = false
        @ignore_rain_delay = false
        @disabled = false
        @activate_relay = false
      end

      # Station ID (0-based)
      attr_reader :id

      # Human-readable station number (1-based)
      def number
        @id + 1
      end

      # Board number (0-based)
      def board
        @id >> 3
      end

      # Bit position within board (0-7)
      def bit_position
        @id & 0x07
      end

      # Is this a special (non-standard) station?
      def special?
        @type != StationType::STANDARD
      end

      # Is this station in parallel mode?
      def parallel?
        @group_id == Constants::PARALLEL_GROUP_ID
      end

      # Set special station data based on type
      def special_data=(data)
        @special_data = data
      end

      # Convert to hash for persistence/API
      def to_h
        h = {
          'id' => @id,
          'name' => @name,
          'type' => @type,
          'group_id' => @group_id,
          'master1_bound' => @master1_bound,
          'master2_bound' => @master2_bound,
          'ignore_sensor1' => @ignore_sensor1,
          'ignore_sensor2' => @ignore_sensor2,
          'ignore_rain_delay' => @ignore_rain_delay,
          'disabled' => @disabled
        }
        h['special_data'] = @special_data.to_h if @special_data
        h
      end

      # Load from hash
      def self.from_h(data)
        station = new(id: data['id'], name: data['name'])
        station.type = data['type'] || StationType::STANDARD
        station.group_id = data['group_id'] || 0
        station.master1_bound = data['master1_bound'] || false
        station.master2_bound = data['master2_bound'] || false
        station.ignore_sensor1 = data['ignore_sensor1'] || false
        station.ignore_sensor2 = data['ignore_sensor2'] || false
        station.ignore_rain_delay = data['ignore_rain_delay'] || false
        station.disabled = data['disabled'] || false

        if data['special_data']
          station.special_data = SpecialStationData.from_h(data['special_data'], station.type)
        end

        station
      end
    end

    # Base class for special station data
    class SpecialStationData
      def self.from_h(data, type)
        case type
        when StationType::GPIO
          GPIOStationData.new(
            pin: data['pin'],
            active_high: data['active_high']
          )
        when StationType::HTTP, StationType::HTTPS
          HTTPStationData.new(
            host: data['host'],
            port: data['port'],
            on_command: data['on_command'],
            off_command: data['off_command']
          )
        when StationType::REMOTE_IP
          RemoteIPStationData.new(
            ip: data['ip'],
            port: data['port'],
            station_id: data['station_id']
          )
        else
          nil
        end
      end
    end

    # GPIO station data
    class GPIOStationData < SpecialStationData
      attr_accessor :pin, :active_high

      def initialize(pin:, active_high: true)
        @pin = pin
        @active_high = active_high
      end

      def to_h
        {
          'pin' => @pin,
          'active_high' => @active_high
        }
      end
    end

    # HTTP/HTTPS station data
    class HTTPStationData < SpecialStationData
      attr_accessor :host, :port, :on_command, :off_command

      def initialize(host:, port: 80, on_command:, off_command:)
        @host = host
        @port = port
        @on_command = on_command
        @off_command = off_command
      end

      def to_h
        {
          'host' => @host,
          'port' => @port,
          'on_command' => @on_command,
          'off_command' => @off_command
        }
      end
    end

    # Remote IP station data (another OpenSprinkler)
    class RemoteIPStationData < SpecialStationData
      attr_accessor :ip, :port, :station_id

      def initialize(ip:, port: 8080, station_id:)
        @ip = ip
        @port = port
        @station_id = station_id
      end

      def to_h
        {
          'ip' => @ip,
          'port' => @port,
          'station_id' => @station_id
        }
      end
    end
  end
end
