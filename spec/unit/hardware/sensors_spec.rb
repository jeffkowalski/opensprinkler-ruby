# frozen_string_literal: true

require 'spec_helper'
require 'opensprinkler/hardware/sensors'
require 'opensprinkler/hardware/gpio'

RSpec.describe OpenSprinkler::Hardware::Sensors do
  let(:gpio) { OpenSprinkler::Hardware::MockGPIO.new }
  subject(:sensors) { described_class.new(gpio: gpio) }

  describe '#configure' do
    it 'configures sensor 1' do
      sensors.configure(
        sensor_num: 1,
        type: OpenSprinkler::Constants::SENSOR_TYPE_RAIN,
        option: 0,
        on_delay: 1,  # 1 minute
        off_delay: 2  # 2 minutes
      )

      expect(sensors.sensor1.type).to eq(OpenSprinkler::Constants::SENSOR_TYPE_RAIN)
      expect(sensors.sensor1.option).to eq(0)
      expect(sensors.sensor1.on_delay).to eq(60) # converted to seconds
      expect(sensors.sensor1.off_delay).to eq(120)
    end

    it 'enforces minimum 5 second delay' do
      sensors.configure(
        sensor_num: 1,
        type: OpenSprinkler::Constants::SENSOR_TYPE_RAIN,
        on_delay: 0,
        off_delay: 0
      )

      expect(sensors.sensor1.on_delay).to eq(5)
      expect(sensors.sensor1.off_delay).to eq(5)
    end
  end

  describe '#poll' do
    before do
      sensors.configure(
        sensor_num: 1,
        type: OpenSprinkler::Constants::SENSOR_TYPE_RAIN,
        option: 0, # Normally closed
        on_delay: 0,
        off_delay: 0
      )
    end

    it 'detects sensor activation with debounce' do
      # Sensor pin is normally closed (0), triggered when open (1)
      gpio.set_state(OpenSprinkler::Constants::PIN_SENSOR1, 1)

      # First poll starts the on-timer
      changes = sensors.poll(1000)
      expect(sensors.sensor1.active).to be false
      expect(changes[:sensor1_changed]).to be false

      # Second poll after delay expires
      changes = sensors.poll(1010) # 10 seconds later
      expect(sensors.sensor1.active).to be true
      expect(changes[:sensor1_changed]).to be true
    end

    it 'detects sensor deactivation with debounce' do
      # Start with sensor active
      gpio.set_state(OpenSprinkler::Constants::PIN_SENSOR1, 1)
      sensors.poll(1000)
      sensors.poll(1010)
      expect(sensors.sensor1.active).to be true

      # Now sensor goes back to normal
      gpio.set_state(OpenSprinkler::Constants::PIN_SENSOR1, 0)

      # First poll starts off-timer
      sensors.poll(1020)
      expect(sensors.sensor1.active).to be true # Still active during debounce

      # After delay
      changes = sensors.poll(1030)
      expect(sensors.sensor1.active).to be false
      expect(changes[:sensor1_changed]).to be true
    end

    it 'handles normally open sensors' do
      sensors.configure(
        sensor_num: 1,
        type: OpenSprinkler::Constants::SENSOR_TYPE_RAIN,
        option: 1, # Normally open
        on_delay: 0,
        off_delay: 0
      )

      # NO sensor: triggered when closed (read = 0)
      gpio.set_state(OpenSprinkler::Constants::PIN_SENSOR1, 0)

      sensors.poll(1000)
      sensors.poll(1010)

      expect(sensors.sensor1.active).to be true
    end
  end

  describe '#rain_sensed?' do
    it 'returns true when rain sensor is active' do
      sensors.configure(
        sensor_num: 1,
        type: OpenSprinkler::Constants::SENSOR_TYPE_RAIN,
        option: 0
      )

      gpio.set_state(OpenSprinkler::Constants::PIN_SENSOR1, 1)
      sensors.poll(1000)
      sensors.poll(1010)

      expect(sensors.rain_sensed?).to be true
    end

    it 'returns false for soil sensor' do
      sensors.configure(
        sensor_num: 1,
        type: OpenSprinkler::Constants::SENSOR_TYPE_SOIL,
        option: 0
      )

      gpio.set_state(OpenSprinkler::Constants::PIN_SENSOR1, 1)
      sensors.poll(1000)
      sensors.poll(1010)

      expect(sensors.rain_sensed?).to be false
      expect(sensors.soil_sensed?).to be true
    end
  end

  describe '#status' do
    it 'returns current sensor status' do
      sensors.configure(
        sensor_num: 1,
        type: OpenSprinkler::Constants::SENSOR_TYPE_RAIN,
        option: 0
      )

      status = sensors.status

      expect(status[:sensor1]).to eq(0)
      expect(status[:sensor1_type]).to eq(OpenSprinkler::Constants::SENSOR_TYPE_RAIN)
      expect(status[:rain]).to eq(0)
    end
  end
end
