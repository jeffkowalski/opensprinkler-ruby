# frozen_string_literal: true

require 'spec_helper'
require 'opensprinkler/hardware/gpio'
require 'opensprinkler/hardware/shift_register'

RSpec.describe OpenSprinkler::Hardware::ShiftRegister do
  let(:gpio) { OpenSprinkler::Hardware::MockGPIO.new }
  subject(:sr) { described_class.new(gpio: gpio, num_boards: 2) }

  describe '#setup' do
    it 'configures all pins as outputs' do
      sr.setup

      expect(gpio.pin_modes[22]).to eq(OpenSprinkler::Hardware::MockGPIO::OUTPUT) # latch
      expect(gpio.pin_modes[27]).to eq(OpenSprinkler::Hardware::MockGPIO::OUTPUT) # data
      expect(gpio.pin_modes[4]).to eq(OpenSprinkler::Hardware::MockGPIO::OUTPUT)  # clock
      expect(gpio.pin_modes[17]).to eq(OpenSprinkler::Hardware::MockGPIO::OUTPUT) # OE
    end

    it 'enables output (OE low)' do
      sr.setup

      expect(gpio.pin_states[17]).to eq(OpenSprinkler::Hardware::MockGPIO::LOW)
    end
  end

  describe '#set_station_bit' do
    it 'sets a station bit on' do
      result = sr.set_station_bit(0, true)

      expect(result).to eq(:turned_on)
      expect(sr.station_bits[0]).to eq(0b00000001)
    end

    it 'sets a station bit off' do
      sr.set_station_bit(0, true)
      result = sr.set_station_bit(0, false)

      expect(result).to eq(:turned_off)
      expect(sr.station_bits[0]).to eq(0b00000000)
    end

    it 'returns :no_change when already on' do
      sr.set_station_bit(0, true)
      result = sr.set_station_bit(0, true)

      expect(result).to eq(:no_change)
    end

    it 'handles multiple stations' do
      sr.set_station_bit(0, true)
      sr.set_station_bit(3, true)
      sr.set_station_bit(7, true)

      expect(sr.station_bits[0]).to eq(0b10001001)
    end

    it 'handles stations on second board' do
      sr.set_station_bit(8, true)  # First station on board 1
      sr.set_station_bit(15, true) # Last station on board 1

      expect(sr.station_bits[1]).to eq(0b10000001)
    end
  end

  describe '#get_station_bit' do
    it 'returns true when bit is set' do
      sr.set_station_bit(5, true)

      expect(sr.get_station_bit(5)).to be true
    end

    it 'returns false when bit is not set' do
      expect(sr.get_station_bit(5)).to be false
    end
  end

  describe '#clear_all' do
    it 'clears all station bits' do
      sr.set_station_bit(0, true)
      sr.set_station_bit(8, true)
      sr.clear_all

      expect(sr.station_bits).to all(eq(0))
    end
  end

  describe '#apply' do
    before { sr.setup }

    it 'shifts out data to hardware' do
      sr.set_station_bit(0, true)
      gpio.clear_operations
      sr.apply

      # Check that latch went low, data was shifted, latch went high
      expect(gpio.operations.first).to eq([:digital_write, 22, 0]) # latch low
      expect(gpio.operations.last).to eq([:digital_write, 22, 1])  # latch high
    end

    it 'shifts out zeros when disabled' do
      sr.set_station_bit(0, true)
      gpio.clear_operations
      sr.apply(enabled: false)

      # All data writes should be 0
      data_writes = gpio.operations.select { |op| op[0] == :digital_write && op[1] == 27 }
      expect(data_writes.map { |op| op[2] }).to all(eq(0))
    end
  end

  describe '#active_stations' do
    it 'returns list of active station IDs' do
      sr.set_station_bit(0, true)
      sr.set_station_bit(5, true)
      sr.set_station_bit(12, true)

      expect(sr.active_stations).to contain_exactly(0, 5, 12)
    end

    it 'returns empty array when no stations active' do
      expect(sr.active_stations).to be_empty
    end
  end

  describe '#num_stations' do
    it 'returns total number of stations' do
      expect(sr.num_stations).to eq(16) # 2 boards * 8
    end
  end
end
