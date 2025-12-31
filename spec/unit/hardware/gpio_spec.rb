# frozen_string_literal: true

require 'spec_helper'
require 'opensprinkler/hardware/gpio'

RSpec.describe OpenSprinkler::Hardware::MockGPIO do
  subject(:gpio) { described_class.new }

  describe '#pin_mode' do
    it 'records pin modes' do
      gpio.pin_mode(17, OpenSprinkler::Hardware::MockGPIO::OUTPUT)

      expect(gpio.pin_modes[17]).to eq(OpenSprinkler::Hardware::MockGPIO::OUTPUT)
    end

    it 'logs the operation' do
      gpio.pin_mode(17, OpenSprinkler::Hardware::MockGPIO::OUTPUT)

      expect(gpio.operations).to include([:pin_mode, 17, OpenSprinkler::Hardware::MockGPIO::OUTPUT])
    end
  end

  describe '#digital_write' do
    it 'sets pin state' do
      gpio.digital_write(22, OpenSprinkler::Hardware::MockGPIO::HIGH)

      expect(gpio.pin_states[22]).to eq(OpenSprinkler::Hardware::MockGPIO::HIGH)
    end

    it 'logs the operation' do
      gpio.digital_write(22, OpenSprinkler::Hardware::MockGPIO::HIGH)

      expect(gpio.operations).to include([:digital_write, 22, OpenSprinkler::Hardware::MockGPIO::HIGH])
    end
  end

  describe '#digital_read' do
    it 'returns set input value' do
      gpio.set_input(14, OpenSprinkler::Hardware::MockGPIO::HIGH)

      expect(gpio.digital_read(14)).to eq(OpenSprinkler::Hardware::MockGPIO::HIGH)
    end

    it 'defaults to LOW' do
      expect(gpio.digital_read(99)).to eq(OpenSprinkler::Hardware::MockGPIO::LOW)
    end
  end

  describe '#clear_operations' do
    it 'clears the operation log' do
      gpio.pin_mode(1, 0)
      gpio.digital_write(1, 1)
      gpio.clear_operations

      expect(gpio.operations).to be_empty
    end
  end
end
