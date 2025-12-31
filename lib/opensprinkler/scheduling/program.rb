# frozen_string_literal: true

require_relative '../constants'

module OpenSprinkler
  module Scheduling
    # Represents a watering program/schedule
    #
    # Program types:
    # - weekly: runs on specific days of the week
    # - single_run: runs once on a specific date, then deleted
    # - monthly: runs on a specific day of the month
    # - interval: runs every N days
    #
    # Start time types:
    # - fixed: up to 4 specific start times
    # - repeating: start time + repeat count + interval
    class Program
      include Constants

      # Program types
      TYPE_WEEKLY     = 0
      TYPE_SINGLE_RUN = 1
      TYPE_MONTHLY    = 2
      TYPE_INTERVAL   = 3

      # Odd/even restrictions
      ODDEVEN_NONE = 0
      ODDEVEN_ODD  = 1
      ODDEVEN_EVEN = 2

      # Start time encoding bits
      STARTTIME_SUNRISE_BIT = 14
      STARTTIME_SUNSET_BIT  = 13
      STARTTIME_SIGN_BIT    = 12
      STARTTIME_DISABLED    = 0x8000  # bit 15 set = disabled

      MAX_STARTTIMES = 4

      attr_accessor :id, :name, :enabled, :use_weather
      attr_accessor :type, :oddeven, :starttime_type, :date_range_enabled
      attr_accessor :days  # [days0, days1] - interpretation depends on type
      attr_accessor :starttimes  # Array of 4 start times
      attr_accessor :durations   # Array of durations per station (seconds)
      attr_accessor :date_range  # [from, to] encoded as (month << 5) + day

      def initialize(id: nil)
        @id = id
        @name = ''
        @enabled = false
        @use_weather = false
        @type = TYPE_WEEKLY
        @oddeven = ODDEVEN_NONE
        @starttime_type = :repeating  # :repeating or :fixed
        @date_range_enabled = false
        @days = [0, 0]
        @starttimes = [0, 0, 0, 0]  # [start, repeat_count, interval, unused] for repeating
        @durations = Array.new(MAX_NUM_STATIONS, 0)
        @date_range = [0, 0]  # min to max
      end

      # Check if program matches given time
      # @param time [Time] Current time
      # @param sunrise_time [Integer] Sunrise in minutes from midnight
      # @param sunset_time [Integer] Sunset in minutes from midnight
      # @return [Integer, nil] Match count (1-based) or nil if no match
      def check_match(time, sunrise_time:, sunset_time:)
        return nil unless @enabled

        current_minute = (time.hour * 60) + time.min

        # Check if today matches
        if check_day_match(time)
          match = check_time_match(time, current_minute, sunrise_time, sunset_time)
          return match if match
        end

        # For repeating programs, check if started yesterday and ran overnight
        if @starttime_type == :repeating && @starttimes[2] > 0  # has interval
          yesterday = time - 86400
          if check_day_match(yesterday)
            match = check_overnight_match(time, current_minute, sunrise_time, sunset_time)
            return match if match
          end
        end

        nil
      end

      # Decode a start time value to minutes from midnight
      # Handles sunrise/sunset relative times
      def decode_starttime(encoded, sunrise_time:, sunset_time:)
        return nil if (encoded >> 15) & 1 == 1  # Disabled

        offset = encoded & 0x7FF  # Lower 11 bits
        offset = -offset if (encoded >> STARTTIME_SIGN_BIT) & 1 == 1

        if (encoded >> STARTTIME_SUNRISE_BIT) & 1 == 1
          result = sunrise_time + offset
          [result, 0].max  # Clamp to 0
        elsif (encoded >> STARTTIME_SUNSET_BIT) & 1 == 1
          result = sunset_time + offset
          [result, 1439].min  # Clamp to 1439
        else
          encoded & 0x7FF  # Standard time (0-1439)
        end
      end

      # Get stations that should run (have non-zero duration)
      def active_stations
        @durations.each_with_index.filter_map do |dur, idx|
          idx if dur > 0
        end
      end

      # Get duration for a station, optionally adjusted by water percentage
      def duration_for(station_id, water_percentage: 100)
        base = @durations[station_id] || 0
        return 0 if base == 0

        if @use_weather && water_percentage != 100
          adjusted = (base * water_percentage) / 100
          # Skip if adjustment makes it too short
          return 0 if water_percentage < 20 && adjusted < 10
          adjusted
        else
          base
        end
      end

      # Convert to hash for persistence
      def to_h
        {
          'id' => @id,
          'name' => @name,
          'enabled' => @enabled,
          'use_weather' => @use_weather,
          'type' => @type,
          'oddeven' => @oddeven,
          'starttime_type' => @starttime_type.to_s,
          'date_range_enabled' => @date_range_enabled,
          'days' => @days,
          'starttimes' => @starttimes,
          'durations' => @durations.take_while.with_index { |d, i| d > 0 || i < 8 },
          'date_range' => @date_range
        }
      end

      # Load from hash
      def self.from_h(data)
        prog = new(id: data['id'])
        prog.name = data['name'] || ''
        prog.enabled = data['enabled'] || false
        prog.use_weather = data['use_weather'] || false
        prog.type = data['type'] || TYPE_WEEKLY
        prog.oddeven = data['oddeven'] || ODDEVEN_NONE
        prog.starttime_type = (data['starttime_type'] || 'repeating').to_sym
        prog.date_range_enabled = data['date_range_enabled'] || false
        prog.days = data['days'] || [0, 0]
        prog.starttimes = data['starttimes'] || [0, 0, 0, 0]
        prog.durations = Array.new(MAX_NUM_STATIONS, 0)
        (data['durations'] || []).each_with_index { |d, i| prog.durations[i] = d }
        prog.date_range = data['date_range'] || [0, 0]
        prog
      end

      # Encode flag byte (for API compatibility)
      def flag_byte
        flag = 0
        flag |= 0x01 if @enabled
        flag |= 0x02 if @use_weather
        flag |= (@oddeven & 0x03) << 2
        flag |= (@type & 0x03) << 4
        flag |= 0x40 if @starttime_type == :fixed
        flag |= 0x80 if @date_range_enabled
        flag
      end

      # Decode flag byte (for API compatibility)
      def self.decode_flag(flag)
        {
          enabled: (flag & 0x01) != 0,
          use_weather: (flag & 0x02) != 0,
          oddeven: (flag >> 2) & 0x03,
          type: (flag >> 4) & 0x03,
          starttime_type: ((flag & 0x40) != 0) ? :fixed : :repeating,
          date_range_enabled: (flag & 0x80) != 0
        }
      end

      # Set program attributes from flag byte (for API compatibility)
      def flag_byte=(flag)
        @enabled = (flag & 0x01) != 0
        @use_weather = (flag & 0x02) != 0
        @oddeven = (flag >> 2) & 0x03
        @type = (flag >> 4) & 0x03
        @starttime_type = ((flag & 0x40) != 0) ? :fixed : :repeating
        @date_range_enabled = (flag & 0x80) != 0
      end

      private

      # Check if a given time matches the program's scheduled day
      def check_day_match(time)
        # Check date range if enabled
        if @date_range_enabled
          current_date = encode_date(time.month, time.day)
          from_date, to_date = @date_range

          if from_date <= to_date
            return false if current_date < from_date || current_date > to_date
          else
            # Range crosses year end
            return false if current_date > to_date && current_date < from_date
          end
        end

        # Check day match based on type
        case @type
        when TYPE_WEEKLY
          weekday = (time.wday + 6) % 7  # Convert to Monday=0
          (@days[0] & (1 << weekday)) != 0

        when TYPE_SINGLE_RUN
          epoch_day = time.to_i / 86400
          target_day = (@days[0] << 8) + @days[1]
          epoch_day == target_day

        when TYPE_MONTHLY
          day_of_month = @days[0] & 0x1F
          if day_of_month == 0
            # Last day of month
            last_day_of_month?(time)
          else
            time.day == day_of_month
          end

        when TYPE_INTERVAL
          interval = @days[1]
          remainder = @days[0]
          return false if interval == 0
          ((time.to_i / 86400) % interval) == remainder

        else
          false
        end && check_oddeven(time)
      end

      # Check odd/even day restriction
      def check_oddeven(time)
        case @oddeven
        when ODDEVEN_NONE
          true
        when ODDEVEN_ODD
          # Skip 31st and Feb 29
          return false if time.day == 31
          return false if time.day == 29 && time.month == 2
          time.day.odd?
        when ODDEVEN_EVEN
          time.day.even?
        else
          true
        end
      end

      # Check time match for today
      def check_time_match(time, current_minute, sunrise_time, sunset_time)
        if @starttime_type == :fixed
          check_fixed_time_match(current_minute, sunrise_time, sunset_time)
        else
          check_repeating_time_match(current_minute, sunrise_time, sunset_time)
        end
      end

      # Check fixed start times
      def check_fixed_time_match(current_minute, sunrise_time, sunset_time)
        @starttimes.each_with_index do |st, i|
          decoded = decode_starttime(st, sunrise_time: sunrise_time, sunset_time: sunset_time)
          next unless decoded
          return (i + 1) if current_minute == decoded
        end
        nil
      end

      # Check repeating start time
      def check_repeating_time_match(current_minute, sunrise_time, sunset_time)
        start = decode_starttime(@starttimes[0], sunrise_time: sunrise_time, sunset_time: sunset_time)
        return nil unless start

        repeat_count = @starttimes[1]
        interval = @starttimes[2]

        return 1 if current_minute == start

        return nil unless current_minute > start && interval > 0

        count = (current_minute - start) / interval
        if (count * interval == (current_minute - start)) && count <= repeat_count
          count + 1
        end
      end

      # Check for overnight program match
      def check_overnight_match(time, current_minute, sunrise_time, sunset_time)
        start = decode_starttime(@starttimes[0], sunrise_time: sunrise_time, sunset_time: sunset_time)
        return nil unless start

        repeat_count = @starttimes[1]
        interval = @starttimes[2]

        return nil if interval == 0

        count = (current_minute - start + 1440) / interval
        if (count * interval == (current_minute - start + 1440)) && count <= repeat_count
          count + 1
        end
      end

      # Encode date as (month << 5) + day
      def encode_date(month, day)
        (month << 5) + day
      end

      # Check if time is last day of month
      def last_day_of_month?(time)
        next_day = time + 86400
        next_day.month != time.month
      end
    end
  end
end
