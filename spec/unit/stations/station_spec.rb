# frozen_string_literal: true

require 'spec_helper'
require 'opensprinkler/stations/station'

RSpec.describe OpenSprinkler::Stations::Station do
  subject(:station) { described_class.new(id: 0) }

  describe '#initialize' do
    it 'sets default name based on ID' do
      expect(station.name).to eq('S01')
    end

    it 'sets default type to standard' do
      expect(station.type).to eq(OpenSprinkler::Constants::StationType::STANDARD)
    end

    it 'sets default group to 0' do
      expect(station.group_id).to eq(0)
    end

    it 'allows custom name' do
      s = described_class.new(id: 5, name: 'Front Lawn')
      expect(s.name).to eq('Front Lawn')
    end
  end

  describe '#number' do
    it 'returns 1-based station number' do
      expect(station.number).to eq(1)
      expect(described_class.new(id: 7).number).to eq(8)
    end
  end

  describe '#board' do
    it 'returns board index' do
      expect(described_class.new(id: 0).board).to eq(0)
      expect(described_class.new(id: 7).board).to eq(0)
      expect(described_class.new(id: 8).board).to eq(1)
      expect(described_class.new(id: 15).board).to eq(1)
    end
  end

  describe '#bit_position' do
    it 'returns bit position within board' do
      expect(described_class.new(id: 0).bit_position).to eq(0)
      expect(described_class.new(id: 7).bit_position).to eq(7)
      expect(described_class.new(id: 8).bit_position).to eq(0)
      expect(described_class.new(id: 15).bit_position).to eq(7)
    end
  end

  describe '#special?' do
    it 'returns false for standard stations' do
      expect(station.special?).to be false
    end

    it 'returns true for GPIO stations' do
      station.type = OpenSprinkler::Constants::StationType::GPIO
      expect(station.special?).to be true
    end
  end

  describe '#parallel?' do
    it 'returns false for sequential group' do
      expect(station.parallel?).to be false
    end

    it 'returns true for parallel group' do
      station.group_id = 255
      expect(station.parallel?).to be true
    end
  end

  describe '#to_h and .from_h' do
    it 'round-trips station data' do
      station.name = 'Back Yard'
      station.master1_bound = true
      station.ignore_sensor1 = true
      station.group_id = 2

      hash = station.to_h
      restored = described_class.from_h(hash)

      expect(restored.name).to eq('Back Yard')
      expect(restored.master1_bound).to be true
      expect(restored.ignore_sensor1).to be true
      expect(restored.group_id).to eq(2)
    end
  end
end

RSpec.describe OpenSprinkler::Stations::GPIOStationData do
  subject(:data) { described_class.new(pin: 17, active_high: false) }

  it 'stores pin and active state' do
    expect(data.pin).to eq(17)
    expect(data.active_high).to be false
  end

  it 'converts to hash' do
    expect(data.to_h).to eq({ 'pin' => 17, 'active_high' => false })
  end
end

RSpec.describe OpenSprinkler::Stations::HTTPStationData do
  subject(:data) do
    described_class.new(
      host: 'example.com',
      port: 8080,
      on_command: '/turn/on',
      off_command: '/turn/off'
    )
  end

  it 'stores HTTP endpoint data' do
    expect(data.host).to eq('example.com')
    expect(data.port).to eq(8080)
    expect(data.on_command).to eq('/turn/on')
    expect(data.off_command).to eq('/turn/off')
  end
end
