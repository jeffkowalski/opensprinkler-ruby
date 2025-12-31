# frozen_string_literal: true

require 'json'
require 'fileutils'

module OpenSprinkler
  # File-based log storage for watering events
  #
  # Logs are stored as JSON files organized by date:
  # data/logs/YYYYMMDD.json
  #
  # Each log entry format (compatible with OpenSprinkler API):
  # [program_id, station_id, duration, end_time, record_type]
  #
  # Record types:
  # 0 = scheduled program run
  # 1 = manual run
  # 2 = run-once program
  # 3 = sensor activated (rain/soil)
  # 4 = flow sensor reading
  class LogStore
    # Record types
    RECORD_PROGRAM  = 0
    RECORD_MANUAL   = 1
    RECORD_RUNONCE  = 2
    RECORD_SENSOR   = 3
    RECORD_FLOW     = 4

    attr_reader :log_dir

    def initialize(log_dir:)
      @log_dir = log_dir
      @cache = {}  # Date string => entries
      FileUtils.mkdir_p(@log_dir)
    end

    # Log a watering event
    # @param station_id [Integer] 0-based station ID
    # @param program_id [Integer] Program ID (0 = manual, 254 = run-once)
    # @param duration [Integer] Duration in seconds
    # @param end_time [Time] When the run ended
    # @param record_type [Integer] Record type constant
    def log_run(station_id:, program_id:, duration:, end_time:, record_type: RECORD_PROGRAM)
      date_str = date_string(end_time)
      entry = [program_id, station_id, duration, end_time.to_i, record_type]

      # Add to cache
      @cache[date_str] ||= load_entries(date_str)
      @cache[date_str] << entry

      # Write to file
      save_entries(date_str, @cache[date_str])
    end

    # Log a sensor event
    # @param sensor_num [Integer] 1 or 2
    # @param active [Boolean] Sensor activated (true) or deactivated (false)
    # @param timestamp [Time] When the event occurred
    def log_sensor(sensor_num:, active:, timestamp:)
      date_str = date_string(timestamp)

      # Encode sensor event: station_id encodes sensor number and state
      # sensor_id = 200 + sensor_num - 1 (200 for sensor 1, 201 for sensor 2)
      station_id = 200 + sensor_num - 1
      duration = active ? 1 : 0  # 1 = on, 0 = off

      entry = [0, station_id, duration, timestamp.to_i, RECORD_SENSOR]

      @cache[date_str] ||= load_entries(date_str)
      @cache[date_str] << entry
      save_entries(date_str, @cache[date_str])
    end

    # Log a flow sensor reading
    # @param count [Integer] Flow pulse count
    # @param timestamp [Time] When the reading was taken
    def log_flow(count:, timestamp:)
      date_str = date_string(timestamp)

      # Station ID 240 = flow sensor
      entry = [0, 240, count, timestamp.to_i, RECORD_FLOW]

      @cache[date_str] ||= load_entries(date_str)
      @cache[date_str] << entry
      save_entries(date_str, @cache[date_str])
    end

    # Get log entries for a date range
    # @param start_time [Integer] Unix timestamp (start of range)
    # @param end_time [Integer] Unix timestamp (end of range)
    # @return [Array] Array of log entries
    def get_entries(start_time:, end_time:)
      entries = []

      # Iterate through dates in range
      current = Time.at(start_time)
      end_date = Time.at(end_time)

      while current <= end_date
        date_str = date_string(current)
        day_entries = load_entries(date_str)

        # Filter by exact time range
        day_entries.each do |entry|
          entry_time = entry[3]
          entries << entry if entry_time >= start_time && entry_time <= end_time
        end

        current += 86400  # Next day
      end

      entries.sort_by { |e| e[3] }  # Sort by timestamp
    end

    # Delete logs before a given date
    # @param before_date [Time] Delete logs before this date
    # @return [Integer] Number of files deleted
    def delete_before(before_date)
      deleted = 0
      before_str = date_string(before_date)

      Dir.glob(File.join(@log_dir, '*.json')).each do |file|
        basename = File.basename(file, '.json')
        if basename < before_str
          File.delete(file)
          @cache.delete(basename)
          deleted += 1
        end
      end

      deleted
    end

    # Delete all logs
    def clear
      Dir.glob(File.join(@log_dir, '*.json')).each { |f| File.delete(f) }
      @cache.clear
    end

    # Get total log size in bytes
    def total_size
      Dir.glob(File.join(@log_dir, '*.json')).sum { |f| File.size(f) }
    end

    private

    def date_string(time)
      time = Time.at(time) if time.is_a?(Integer)
      time.strftime('%Y%m%d')
    end

    def file_path(date_str)
      File.join(@log_dir, "#{date_str}.json")
    end

    def load_entries(date_str)
      path = file_path(date_str)
      return [] unless File.exist?(path)

      JSON.parse(File.read(path))
    rescue JSON::ParserError
      []
    end

    def save_entries(date_str, entries)
      path = file_path(date_str)
      File.write(path, JSON.generate(entries))
    end
  end
end
