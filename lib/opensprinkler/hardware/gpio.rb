# frozen_string_literal: true

require_relative '../constants'

module OpenSprinkler
  module Hardware
    # GPIO abstraction layer for Raspberry Pi
    # Wraps the lgpio gem for actual hardware control
    #
    # This mirrors the gpio.cpp implementation from the C++ firmware
    class GPIO
      # Pin modes
      INPUT = 0
      OUTPUT = 1
      INPUT_PULLUP = 2

      # Pin values
      LOW = 0
      HIGH = 1

      attr_reader :chip_id, :handle

      def initialize
        @handle = nil
        @chip_id = nil
        @claimed_pins = {}
      end

      # Open connection to GPIO chip
      # On Pi 5 (bcm2712), uses gpiochip4; otherwise gpiochip0
      def open
        return if @handle

        require 'lgpio'

        # Detect Pi 5 by checking for bcm2712 in device tree
        @chip_id = pi5? ? 4 : 0

        @handle = LGPIO.chip_open(@chip_id)
        # Fallback to gpiochip0 if gpiochip4 failed
        if (@handle.nil? || @handle.negative?) && (@chip_id != 0)
          @chip_id = 0
          @handle = LGPIO.chip_open(@chip_id)
        end

        raise 'Failed to open GPIO chip' if @handle.nil? || @handle.negative?
      end

      # Close GPIO connection
      def close
        return unless @handle

        # Release all claimed pins
        @claimed_pins.each_key do |pin|
          LGPIO.gpio_free(@handle, pin)
        end
        @claimed_pins.clear

        LGPIO.chip_close(@handle)
        @handle = nil
      end

      # Set pin mode (INPUT, OUTPUT, or INPUT_PULLUP)
      def pin_mode(pin, mode)
        ensure_open

        # Release if already claimed
        LGPIO.gpio_free(@handle, pin) if @claimed_pins[pin]

        case mode
        when INPUT
          LGPIO.gpio_claim_input(@handle, pin)
        when INPUT_PULLUP
          LGPIO.gpio_claim_input(@handle, pin, LGPIO::SET_PULL_UP)
        when OUTPUT
          LGPIO.gpio_claim_output(@handle, pin, LGPIO::SET_LOW)
        else
          raise ArgumentError, "Invalid pin mode: #{mode}"
        end

        @claimed_pins[pin] = mode
      end

      # Read digital value from pin
      def digital_read(pin)
        ensure_open
        LGPIO.gpio_read(@handle, pin)
      end

      # Write digital value to pin
      def digital_write(pin, value)
        ensure_open
        LGPIO.gpio_write(@handle, pin, value)
      end

      private

      def ensure_open
        open unless @handle
      end

      # Detect if running on Raspberry Pi 5
      def pi5?
        return false unless File.exist?('/proc/device-tree/compatible')

        compatible = File.read('/proc/device-tree/compatible')
        compatible.include?('bcm2712')
      rescue StandardError
        false
      end
    end

    # Mock GPIO for testing and development
    # Logs all operations without touching real hardware
    class MockGPIO
      INPUT = 0
      OUTPUT = 1
      INPUT_PULLUP = 2
      LOW = 0
      HIGH = 1

      attr_reader :pin_modes, :pin_states, :operations
      alias log operations

      def initialize
        @pin_modes = {}
        @pin_states = Hash.new(LOW)
        @operations = []
      end

      def open
        @operations << [:open]
      end

      def close
        @operations << [:close]
        @pin_modes.clear
        @pin_states.clear
      end

      def pin_mode(pin, mode)
        @operations << [:pin_mode, pin, mode]
        @pin_modes[pin] = mode
      end

      def digital_read(pin)
        @operations << [:digital_read, pin]
        @pin_states[pin]
      end

      alias read digital_read

      def digital_write(pin, value)
        @operations << [:digital_write, pin, value]
        @pin_states[pin] = value
      end

      alias write digital_write

      # Test helper: set a pin's input value
      def set_input(pin, value)
        @pin_states[pin] = value
      end

      alias set_state set_input

      # Test helper: clear operation log
      def clear_operations
        @operations.clear
      end

      alias clear_log clear_operations
    end

    # Demo GPIO that prints operations to stdout
    # Useful for testing without hardware
    class DemoGPIO
      INPUT = 0
      OUTPUT = 1
      INPUT_PULLUP = 2
      LOW = 0
      HIGH = 1

      def initialize
        @pin_states = Hash.new(LOW)
      end

      def open
        puts '[GPIO] Opened (demo mode)'
      end

      def close
        puts '[GPIO] Closed'
      end

      def pin_mode(pin, mode)
        mode_name = case mode
                    when INPUT then 'INPUT'
                    when OUTPUT then 'OUTPUT'
                    when INPUT_PULLUP then 'INPUT_PULLUP'
                    else mode.to_s
                    end
        puts "[GPIO] Pin #{pin} mode: #{mode_name}"
      end

      def digital_read(pin)
        value = @pin_states[pin]
        puts "[GPIO] Read pin #{pin}: #{value}"
        value
      end

      def digital_write(pin, value)
        @pin_states[pin] = value
        puts "[GPIO] Write pin #{pin}: #{value}"
      end

      # Allow setting simulated sensor values
      def set_input(pin, value)
        @pin_states[pin] = value
      end
    end
  end
end
