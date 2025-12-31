# frozen_string_literal: true

require_relative '../constants'

module OpenSprinkler
  module Hardware
    # Sensor state for each sensor
    SensorState = Struct.new(
      :type,           # Sensor type (rain, soil, flow, none)
      :option,         # 0 = normally closed, 1 = normally open
      :raw_state,      # Current raw reading (0 or 1)
      :active,         # Debounced active state
      :on_timer,       # Time when on-delay expires
      :off_timer,      # Time when off-delay expires
      :on_delay,       # On delay in seconds
      :off_delay,      # Off delay in seconds
      :last_active_time, # Time when sensor became active
      keyword_init: true
    ) do
      def binary?
        [Constants::SENSOR_TYPE_RAIN, Constants::SENSOR_TYPE_SOIL].include?(type)
      end

      def flow?
        type == Constants::SENSOR_TYPE_FLOW
      end
    end

    # Manages rain, soil, and flow sensors
    #
    # Binary sensors (rain/soil) have debounce logic with configurable
    # on/off delays to prevent false triggers from noise.
    class Sensors
      include Constants

      attr_reader :sensor1, :sensor2
      attr_accessor :flow_count

      def initialize(gpio:)
        @gpio = gpio
        @flow_count = 0
        @flow_count_log_start = 0

        @sensor1 = SensorState.new(
          type: Constants::SENSOR_TYPE_NONE,
          option: 0,
          raw_state: 0,
          active: false,
          on_timer: 0,
          off_timer: 0,
          on_delay: 5, # minimum 5 seconds
          off_delay: 5,
          last_active_time: 0
        )

        @sensor2 = SensorState.new(
          type: Constants::SENSOR_TYPE_NONE,
          option: 0,
          raw_state: 0,
          active: false,
          on_timer: 0,
          off_timer: 0,
          on_delay: 5,
          off_delay: 5,
          last_active_time: 0
        )

        @old_sensor1_active = false
        @old_sensor2_active = false
      end

      # Configure sensor from options
      # @param sensor_num [Integer] 1 or 2
      # @param type [Integer] Sensor type constant
      # @param option [Integer] 0 = normally closed, 1 = normally open
      # @param on_delay [Integer] On delay in minutes
      # @param off_delay [Integer] Off delay in minutes
      def configure(sensor_num:, type:, option: 0, on_delay: 0, off_delay: 0)
        sensor = sensor_num == 1 ? @sensor1 : @sensor2
        sensor.type = type
        sensor.option = option
        # Convert minutes to seconds, with minimum 5 seconds
        sensor.on_delay = [(on_delay * 60), 5].max
        sensor.off_delay = [(off_delay * 60), 5].max
      end

      # Poll sensors and update state
      # @param current_time [Integer] Current time in epoch seconds
      # @return [Hash] Status changes (sensor1_changed, sensor2_changed)
      def poll(current_time)
        changes = { sensor1_changed: false, sensor2_changed: false }

        # Poll sensor 1
        if @sensor1.binary?
          poll_binary_sensor(@sensor1, PIN_SENSOR1, current_time)

          if @old_sensor1_active != @sensor1.active
            @sensor1.last_active_time = current_time if @sensor1.active
            changes[:sensor1_changed] = true
            @old_sensor1_active = @sensor1.active
          end
        end

        # Poll sensor 2
        if @sensor2.binary?
          poll_binary_sensor(@sensor2, PIN_SENSOR2, current_time)

          if @old_sensor2_active != @sensor2.active
            @sensor2.last_active_time = current_time if @sensor2.active
            changes[:sensor2_changed] = true
            @old_sensor2_active = @sensor2.active
          end
        end

        changes
      end

      # Check if rain sensor is active (should stop watering)
      def rain_sensed?
        (@sensor1.type == SENSOR_TYPE_RAIN && @sensor1.active) ||
          (@sensor2.type == SENSOR_TYPE_RAIN && @sensor2.active)
      end

      # Check if soil sensor is active
      def soil_sensed?
        (@sensor1.type == SENSOR_TYPE_SOIL && @sensor1.active) ||
          (@sensor2.type == SENSOR_TYPE_SOIL && @sensor2.active)
      end

      # Get sensor status for API
      def status
        {
          sensor1: @sensor1.active ? 1 : 0,
          sensor2: @sensor2.active ? 1 : 0,
          sensor1_type: @sensor1.type,
          sensor2_type: @sensor2.type,
          rain: rain_sensed? ? 1 : 0
        }
      end

      # Reset flow counter and record start
      def reset_flow_count
        @flow_count_log_start = @flow_count
      end

      # Get flow since last reset
      def flow_since_reset
        @flow_count - @flow_count_log_start
      end

      private

      def poll_binary_sensor(sensor, pin, current_time)
        # Read raw value
        raw_val = @gpio.read(pin)

        # Compare with option (0 = NC, 1 = NO)
        # If sensor option is 0 (NC), triggered when read is 1 (open)
        # If sensor option is 1 (NO), triggered when read is 0 (closed)
        sensor.raw_state = raw_val == sensor.option ? 0 : 1

        if sensor.raw_state == 1
          # Sensor is triggered
          if sensor.on_timer.zero?
            # Start on-delay timer
            sensor.on_timer = current_time + sensor.on_delay
            sensor.off_timer = 0
          elsif current_time >= sensor.on_timer
            # On-delay expired, sensor is now active
            sensor.active = true
          end
        elsif sensor.off_timer.zero?
          # Sensor is not triggered
          sensor.off_timer = current_time + sensor.off_delay
          sensor.on_timer = 0
        # Start off-delay timer
        elsif current_time >= sensor.off_timer
          # Off-delay expired, sensor is now inactive
          sensor.active = false
        end
      end
    end
  end
end
