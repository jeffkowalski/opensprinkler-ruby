# frozen_string_literal: true

require 'net/http'
require 'uri'

module OpenSprinkler
  # InfluxDB client for logging valve state changes
  #
  # Posts line protocol data to InfluxDB:
  # - valveXX value=0|1 for individual valve state
  # - valves value=N for current active valve (0 if none)
  class InfluxDBClient
    attr_accessor :enabled, :host, :port, :database

    def initialize(host: 'localhost', port: 8086, database: 'opensprinkler', enabled: false)
      @host = host
      @port = port
      @database = database
      @enabled = enabled
      @last_states = {} # Track valve states to detect changes
      @current_active = 0
    end

    # Load configuration from YAML file
    def self.from_config(config_path)
      return new(enabled: false) unless config_path && File.exist?(config_path)

      require 'yaml'
      config = YAML.load_file(config_path, permitted_classes: [Symbol])
      return new(enabled: false) unless config

      new(
        host: config['host'] || 'localhost',
        port: config['port'] || 8086,
        database: config['database'] || 'opensprinkler',
        enabled: config['enabled'] || false
      )
    end

    # Log a valve state change
    # @param valve_id [Integer] 0-based valve ID
    # @param state [Integer] 0=off, 1=on
    # @param timestamp [Time] Optional timestamp
    def log_valve(valve_id, state, timestamp = Time.now)
      return unless @enabled

      # Check if state changed
      prev_state = @last_states[valve_id]
      return if prev_state == state

      @last_states[valve_id] = state
      timestamp_ns = (timestamp.to_f * 1_000_000_000).to_i

      # Build line protocol data
      lines = []

      # Individual valve measurement
      valve_name = format('valve%02d', valve_id + 1)
      lines << "#{valve_name} value=#{state} #{timestamp_ns}"

      # Update current active valve
      if state == 1
        @current_active = valve_id + 1
      elsif @current_active == valve_id + 1
        @current_active = 0
      end

      # Active valve measurement
      lines << "valves value=#{@current_active} #{timestamp_ns}"

      # Send to InfluxDB
      write_lines(lines)
    end

    # Log multiple valve states at once
    # @param states [Hash<Integer, Integer>] valve_id => state
    # @param timestamp [Time] Optional timestamp
    def log_valves(states, timestamp = Time.now)
      return unless @enabled

      timestamp_ns = (timestamp.to_f * 1_000_000_000).to_i
      lines = []

      states.each do |valve_id, state|
        prev_state = @last_states[valve_id]
        next if prev_state == state

        @last_states[valve_id] = state
        valve_name = format('valve%02d', valve_id + 1)
        lines << "#{valve_name} value=#{state} #{timestamp_ns}"
      end

      return if lines.empty?

      # Find highest active valve or 0
      active_valves = @last_states.select { |_, v| v == 1 }.keys
      @current_active = active_valves.empty? ? 0 : active_valves.max + 1
      lines << "valves value=#{@current_active} #{timestamp_ns}"

      write_lines(lines)
    end

    # Check if client is properly configured
    def configured?
      @enabled && !@host.nil? && !@port.nil? && !@database.nil?
    end

    private

    # Write line protocol data to InfluxDB
    def write_lines(lines)
      return if lines.empty?

      uri = URI("http://#{@host}:#{@port}/write?db=#{@database}")

      begin
        Net::HTTP.start(uri.host, uri.port, read_timeout: 5, open_timeout: 5) do |http|
          request = Net::HTTP::Post.new(uri)
          request.body = lines.join("\n")
          request['Content-Type'] = 'text/plain'

          response = http.request(request)

          warn "[InfluxDB] Write failed: #{response.code} #{response.body}" unless response.is_a?(Net::HTTPSuccess) || response.code == '204'
        end
      rescue StandardError => e
        warn "[InfluxDB] Error: #{e.message}"
      end
    end
  end
end
