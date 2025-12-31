# frozen_string_literal: true

require_relative 'opensprinkler/version'
require_relative 'opensprinkler/constants'
require_relative 'opensprinkler/options'
require_relative 'opensprinkler/hardware/gpio'
require_relative 'opensprinkler/hardware/shift_register'
require_relative 'opensprinkler/stations/station'
require_relative 'opensprinkler/stations/station_store'

module OpenSprinkler
  class Error < StandardError; end

  class << self
    # Factory method to create appropriate GPIO instance based on hardware type
    def create_gpio(type = :auto)
      case type
      when :auto
        # Try to detect hardware, fall back to demo
        if File.exist?('/proc/device-tree/compatible')
          Hardware::GPIO.new
        else
          Hardware::DemoGPIO.new
        end
      when :real, :ospi
        Hardware::GPIO.new
      when :demo
        Hardware::DemoGPIO.new
      when :mock, :test
        Hardware::MockGPIO.new
      else
        raise ArgumentError, "Unknown GPIO type: #{type}"
      end
    end
  end
end
