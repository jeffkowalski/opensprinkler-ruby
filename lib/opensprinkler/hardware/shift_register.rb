# frozen_string_literal: true

require_relative '../constants'

module OpenSprinkler
  module Hardware
    # Controls 74HC595 shift registers for zone outputs
    #
    # The OSPi uses a chain of 74HC595 shift registers:
    # - Each shift register controls 8 zones
    # - Data is shifted MSB first, from highest board to lowest
    # - The latch pin transfers the shifted data to outputs
    #
    # Pin assignments (BCM):
    #   PIN_SR_LATCH = 22  (active low during shifting)
    #   PIN_SR_DATA  = 27  (or 21 for RPi 1 rev 1)
    #   PIN_SR_CLOCK = 4
    #   PIN_SR_OE    = 17  (output enable, active low)
    class ShiftRegister
      include Constants

      attr_reader :gpio, :num_boards, :station_bits

      def initialize(gpio:, num_boards: 1, use_alt_data_pin: false)
        @gpio = gpio
        @num_boards = num_boards
        @station_bits = Array.new(Constants::MAX_NUM_BOARDS, 0)

        # Pin assignments
        @pin_latch = Constants::Pin::SR_LATCH
        @pin_data = use_alt_data_pin ? Constants::Pin::SR_DATA_ALT : Constants::Pin::SR_DATA
        @pin_clock = Constants::Pin::SR_CLOCK
        @pin_oe = Constants::Pin::SR_OE
      end

      # Initialize the shift register pins
      def setup
        @gpio.open

        # Configure pins as outputs
        @gpio.pin_mode(@pin_latch, Hardware::GPIO::OUTPUT)
        @gpio.pin_mode(@pin_data, Hardware::GPIO::OUTPUT)
        @gpio.pin_mode(@pin_clock, Hardware::GPIO::OUTPUT)
        @gpio.pin_mode(@pin_oe, Hardware::GPIO::OUTPUT)

        # Enable output (OE is active low)
        @gpio.digital_write(@pin_oe, Hardware::GPIO::LOW)

        # Set latch high (inactive)
        @gpio.digital_write(@pin_latch, Hardware::GPIO::HIGH)
      end

      # Set a single station bit
      # @param sid [Integer] Station ID (0-based)
      # @param value [Boolean] true = on, false = off
      # @return [Symbol] :no_change, :turned_on, or :turned_off
      def set_station_bit(sid, value)
        board = sid >> 3           # sid / 8
        bit_pos = sid & 0x07       # sid % 8
        mask = 1 << bit_pos

        if value
          if (@station_bits[board] & mask) != 0
            :no_change  # Already on
          else
            @station_bits[board] |= mask
            :turned_on
          end
        else
          if (@station_bits[board] & mask) == 0
            :no_change  # Already off
          else
            @station_bits[board] &= ~mask
            :turned_off
          end
        end
      end

      # Get a single station bit
      # @param sid [Integer] Station ID (0-based)
      # @return [Boolean] true if on, false if off
      def get_station_bit(sid)
        board = sid >> 3
        bit_pos = sid & 0x07
        mask = 1 << bit_pos
        (@station_bits[board] & mask) != 0
      end

      # Clear all station bits (but don't apply yet)
      def clear_all
        @station_bits.fill(0)
      end

      alias_method :clear, :clear_all

      # Apply all station bits to hardware
      # This shifts out all bits and latches them
      # @param enabled [Boolean] If false, all outputs are off regardless of bits
      def apply(enabled: true)
        # Pull latch low to begin shifting
        @gpio.digital_write(@pin_latch, Hardware::GPIO::LOW)

        # Shift out all station bits from highest board to lowest
        # (MSB of highest board first)
        (0..Constants::MAX_EXT_BOARDS).reverse_each do |board|
          sbits = enabled ? @station_bits[board] : 0

          # Shift out 8 bits, MSB first
          8.times do |s|
            @gpio.digital_write(@pin_clock, Hardware::GPIO::LOW)

            # Set data bit (bit 7-s, so MSB first)
            bit_value = (sbits >> (7 - s)) & 0x01
            @gpio.digital_write(@pin_data, bit_value)

            @gpio.digital_write(@pin_clock, Hardware::GPIO::HIGH)
          end
        end

        # Latch the data (rising edge transfers to outputs)
        @gpio.digital_write(@pin_latch, Hardware::GPIO::HIGH)
      end

      # Get array of currently active station IDs
      def active_stations
        active = []
        @station_bits.each_with_index do |byte, board|
          8.times do |bit|
            if (byte & (1 << bit)) != 0
              active << (board * 8 + bit)
            end
          end
        end
        active
      end

      # Get the number of currently configured stations
      def num_stations
        @num_boards * 8
      end

      # Disable outputs (set OE high)
      def disable_output
        @gpio.digital_write(@pin_oe, Hardware::GPIO::HIGH)
      end

      # Enable outputs (set OE low)
      def enable_output
        @gpio.digital_write(@pin_oe, Hardware::GPIO::LOW)
      end
    end
  end
end
