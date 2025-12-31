# frozen_string_literal: true

require 'spec_helper'
require 'opensprinkler/scheduling/program'

RSpec.describe OpenSprinkler::Scheduling::Program do
  subject(:program) { described_class.new(id: 0) }

  describe '#initialize' do
    it 'sets default values' do
      expect(program.enabled).to be false
      expect(program.type).to eq(described_class::TYPE_WEEKLY)
      expect(program.starttimes).to eq([0, 0, 0, 0])
    end
  end

  describe '#decode_starttime' do
    let(:sunrise) { 360 }  # 6:00 AM
    let(:sunset) { 1080 }  # 6:00 PM

    it 'decodes standard time' do
      # 480 = 8:00 AM
      result = program.decode_starttime(480, sunrise_time: sunrise, sunset_time: sunset)
      expect(result).to eq(480)
    end

    it 'decodes sunrise relative time with positive offset' do
      # Bit 14 set (sunrise) + 30 minutes offset
      encoded = (1 << 14) | 30
      result = program.decode_starttime(encoded, sunrise_time: sunrise, sunset_time: sunset)
      expect(result).to eq(390) # 6:00 + 0:30 = 6:30 AM
    end

    it 'decodes sunrise relative time with negative offset' do
      # Bit 14 set (sunrise) + bit 12 set (negative) + 30 minutes
      encoded = (1 << 14) | (1 << 12) | 30
      result = program.decode_starttime(encoded, sunrise_time: sunrise, sunset_time: sunset)
      expect(result).to eq(330) # 6:00 - 0:30 = 5:30 AM
    end

    it 'decodes sunset relative time' do
      # Bit 13 set (sunset) + 60 minutes offset
      encoded = (1 << 13) | 60
      result = program.decode_starttime(encoded, sunrise_time: sunrise, sunset_time: sunset)
      expect(result).to eq(1140) # 6:00 PM + 1:00 = 7:00 PM
    end

    it 'clamps negative results to 0' do
      # Sunrise at 6:00 minus 400 minutes
      encoded = (1 << 14) | (1 << 12) | 400
      result = program.decode_starttime(encoded, sunrise_time: sunrise, sunset_time: sunset)
      expect(result).to eq(0)
    end

    it 'returns nil for disabled times' do
      # Bit 15 set = disabled
      encoded = (1 << 15)
      result = program.decode_starttime(encoded, sunrise_time: sunrise, sunset_time: sunset)
      expect(result).to be_nil
    end
  end

  describe '#check_match' do
    let(:sunrise) { 360 }
    let(:sunset) { 1080 }

    context 'with weekly program' do
      before do
        program.enabled = true
        program.type = described_class::TYPE_WEEKLY
        program.days = [0b0000101, 0] # Monday and Wednesday (bits 0 and 2)
        program.starttimes = [480, 0, 0, 0] # 8:00 AM, repeating
        program.starttime_type = :repeating
      end

      it 'matches on scheduled day and time' do
        # Monday at 8:00 AM
        time = Time.new(2025, 1, 6, 8, 0, 0) # Monday
        result = program.check_match(time, sunrise_time: sunrise, sunset_time: sunset)
        expect(result).to eq(1)
      end

      it 'does not match on wrong day' do
        # Tuesday at 8:00 AM
        time = Time.new(2025, 1, 7, 8, 0, 0) # Tuesday
        result = program.check_match(time, sunrise_time: sunrise, sunset_time: sunset)
        expect(result).to be_nil
      end

      it 'does not match on wrong time' do
        # Monday at 9:00 AM
        time = Time.new(2025, 1, 6, 9, 0, 0)
        result = program.check_match(time, sunrise_time: sunrise, sunset_time: sunset)
        expect(result).to be_nil
      end

      it 'does not match when disabled' do
        program.enabled = false
        time = Time.new(2025, 1, 6, 8, 0, 0)
        result = program.check_match(time, sunrise_time: sunrise, sunset_time: sunset)
        expect(result).to be_nil
      end
    end

    context 'with repeating start times' do
      before do
        program.enabled = true
        program.type = described_class::TYPE_WEEKLY
        program.days = [0b1111111, 0] # Every day
        program.starttimes = [360, 3, 120, 0] # Start 6:00, repeat 3 times, every 2 hours
        program.starttime_type = :repeating
      end

      it 'matches first run' do
        time = Time.new(2025, 1, 6, 6, 0, 0)
        result = program.check_match(time, sunrise_time: sunrise, sunset_time: sunset)
        expect(result).to eq(1)
      end

      it 'matches second run' do
        time = Time.new(2025, 1, 6, 8, 0, 0) # 6:00 + 2:00
        result = program.check_match(time, sunrise_time: sunrise, sunset_time: sunset)
        expect(result).to eq(2)
      end

      it 'matches third run' do
        time = Time.new(2025, 1, 6, 10, 0, 0)  # 6:00 + 4:00
        result = program.check_match(time, sunrise_time: sunrise, sunset_time: sunset)
        expect(result).to eq(3)
      end

      it 'does not match beyond repeat count' do
        time = Time.new(2025, 1, 6, 14, 0, 0)  # 6:00 + 8:00 = 4th interval
        result = program.check_match(time, sunrise_time: sunrise, sunset_time: sunset)
        expect(result).to be_nil
      end
    end

    context 'with fixed start times' do
      before do
        program.enabled = true
        program.type = described_class::TYPE_WEEKLY
        program.days = [0b1111111, 0]
        program.starttimes = [360, 480, 720, 0x8000] # 6:00, 8:00, 12:00, disabled
        program.starttime_type = :fixed
      end

      it 'matches each fixed time' do
        expect(program.check_match(Time.new(2025, 1, 6, 6, 0), sunrise_time: sunrise, sunset_time: sunset)).to eq(1)
        expect(program.check_match(Time.new(2025, 1, 6, 8, 0), sunrise_time: sunrise, sunset_time: sunset)).to eq(2)
        expect(program.check_match(Time.new(2025, 1, 6, 12, 0), sunrise_time: sunrise, sunset_time: sunset)).to eq(3)
      end

      it 'skips disabled times' do
        # 4th time is disabled
        expect(program.check_match(Time.new(2025, 1, 6, 0, 0), sunrise_time: sunrise, sunset_time: sunset)).to be_nil
      end
    end

    context 'with interval program' do
      before do
        program.enabled = true
        program.type = described_class::TYPE_INTERVAL
        program.days = [0, 3] # Remainder 0, interval 3 days
        program.starttimes = [480, 0, 0, 0] # 8:00 AM
        program.starttime_type = :repeating
      end

      it 'matches on interval days' do
        # Find a day where epoch_day % 3 == 0
        # Jan 1, 1970 was day 0, so we need day divisible by 3
        # Jan 4, 2025 should be about day 20092
        base_time = Time.new(2025, 1, 1, 8, 0, 0)
        epoch_day = base_time.to_i / 86_400

        # Find next day where epoch_day % 3 == 0
        offset = (3 - (epoch_day % 3)) % 3
        matching_time = base_time + (offset * 86_400)

        result = program.check_match(matching_time, sunrise_time: sunrise, sunset_time: sunset)
        expect(result).to eq(1)
      end
    end

    context 'with odd day restriction' do
      before do
        program.enabled = true
        program.type = described_class::TYPE_WEEKLY
        program.days = [0b1111111, 0]
        program.oddeven = described_class::ODDEVEN_ODD
        program.starttimes = [480, 0, 0, 0]
        program.starttime_type = :repeating
      end

      it 'matches on odd days' do
        time = Time.new(2025, 1, 1, 8, 0, 0)  # Jan 1 = odd
        result = program.check_match(time, sunrise_time: sunrise, sunset_time: sunset)
        expect(result).to eq(1)
      end

      it 'does not match on even days' do
        time = Time.new(2025, 1, 2, 8, 0, 0)  # Jan 2 = even
        result = program.check_match(time, sunrise_time: sunrise, sunset_time: sunset)
        expect(result).to be_nil
      end

      it 'does not match on 31st' do
        time = Time.new(2025, 1, 31, 8, 0, 0)
        result = program.check_match(time, sunrise_time: sunrise, sunset_time: sunset)
        expect(result).to be_nil
      end
    end
  end

  describe '#active_stations' do
    it 'returns stations with non-zero duration' do
      program.durations = [300, 0, 600, 0, 0, 0, 0, 0]
      expect(program.active_stations).to eq([0, 2])
    end
  end

  describe '#duration_for' do
    before do
      program.durations = [600, 0, 0, 0, 0, 0, 0, 0]
    end

    it 'returns raw duration when weather disabled' do
      program.use_weather = false
      expect(program.duration_for(0, water_percentage: 50)).to eq(600)
    end

    it 'adjusts duration when weather enabled' do
      program.use_weather = true
      expect(program.duration_for(0, water_percentage: 50)).to eq(300)
    end

    it 'returns 0 for very low adjustments' do
      program.use_weather = true
      program.durations[0] = 10
      expect(program.duration_for(0, water_percentage: 10)).to eq(0)
    end
  end

  describe '#to_h and .from_h' do
    it 'round-trips program data' do
      program.name = 'Morning Watering'
      program.enabled = true
      program.type = described_class::TYPE_WEEKLY
      program.days = [0b0101010, 0]
      program.starttimes = [480, 2, 180, 0]
      program.durations[0] = 600
      program.durations[1] = 300

      hash = program.to_h
      restored = described_class.from_h(hash)

      expect(restored.name).to eq('Morning Watering')
      expect(restored.enabled).to be true
      expect(restored.days).to eq([0b0101010, 0])
      expect(restored.durations[0]).to eq(600)
    end
  end
end
