# frozen_string_literal: true

require 'spec_helper'
require 'opensprinkler/stations/station_store'
require 'tempfile'

RSpec.describe OpenSprinkler::Stations::StationStore do
  subject(:store) { described_class.new(num_stations: 16) }

  describe '#initialize' do
    it 'creates specified number of stations' do
      expect(store.count).to eq(16)
    end

    it 'assigns default names' do
      expect(store[0].name).to eq('S01')
      expect(store[15].name).to eq('S16')
    end
  end

  describe '#[]' do
    it 'returns station by ID' do
      expect(store[5]).to be_a(OpenSprinkler::Stations::Station)
      expect(store[5].id).to eq(5)
    end
  end

  describe '#resize' do
    it 'adds stations when growing' do
      store.resize(24)
      expect(store.count).to eq(24)
      expect(store[23].name).to eq('S24')
    end

    it 'removes stations when shrinking' do
      store.resize(8)
      expect(store.count).to eq(8)
    end

    it 'preserves existing station data when growing' do
      store[0].name = 'Front Lawn'
      store.resize(24)
      expect(store[0].name).to eq('Front Lawn')
    end
  end

  describe '#names' do
    it 'returns array of station names' do
      store[0].name = 'Zone A'
      store[1].name = 'Zone B'

      names = store.names
      expect(names[0]).to eq('Zone A')
      expect(names[1]).to eq('Zone B')
    end
  end

  describe 'attribute bitfields' do
    before do
      store[0].master1_bound = true
      store[2].master1_bound = true
      store[7].master1_bound = true
      store[8].master2_bound = true
    end

    it 'calculates master1 bits per board' do
      expect(store.master1_bits(0)).to eq(0b10000101)  # bits 0, 2, 7
      expect(store.master1_bits(1)).to eq(0b00000000)
    end

    it 'calculates master2 bits per board' do
      expect(store.master2_bits(0)).to eq(0b00000000)
      expect(store.master2_bits(1)).to eq(0b00000001)  # bit 0
    end
  end

  describe '#set_master1_bits' do
    it 'sets station attributes from bitfield' do
      store.set_master1_bits(0, 0b00001010) # bits 1 and 3

      expect(store[0].master1_bound).to be false
      expect(store[1].master1_bound).to be true
      expect(store[2].master1_bound).to be false
      expect(store[3].master1_bound).to be true
    end
  end

  describe '#group_ids' do
    it 'returns array of group IDs' do
      store[0].group_id = 0
      store[1].group_id = 1
      store[2].group_id = 255

      ids = store.group_ids
      expect(ids[0]).to eq(0)
      expect(ids[1]).to eq(1)
      expect(ids[2]).to eq(255)
    end
  end

  describe 'persistence' do
    let(:tmpfile) { Tempfile.new(['stations', '.yml']) }
    let(:store_with_file) { described_class.new(file_path: tmpfile.path, num_stations: 8) }

    after { tmpfile.unlink }

    it 'saves and loads station data' do
      store_with_file[0].name = 'Front Yard'
      store_with_file[0].master1_bound = true
      store_with_file[0].group_id = 2
      store_with_file.save

      new_store = described_class.new(file_path: tmpfile.path, num_stations: 8)
      new_store.load

      expect(new_store[0].name).to eq('Front Yard')
      expect(new_store[0].master1_bound).to be true
      expect(new_store[0].group_id).to eq(2)
    end
  end

  describe '#special_stations' do
    it 'returns hash of special stations for API' do
      store[2].type = OpenSprinkler::Constants::StationType::GPIO
      store[2].special_data = OpenSprinkler::Stations::GPIOStationData.new(
        pin: 17,
        active_high: true
      )

      result = store.special_stations
      expect(result).to have_key('2')
      expect(result['2']['st']).to eq(OpenSprinkler::Constants::StationType::GPIO)
    end
  end
end
