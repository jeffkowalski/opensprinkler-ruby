# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'opensprinkler/log_store'

RSpec.describe OpenSprinkler::LogStore do
  let(:log_dir) { Dir.mktmpdir }
  let(:store) { described_class.new(log_dir: log_dir) }

  after do
    FileUtils.rm_rf(log_dir)
  end

  describe '#initialize' do
    it 'creates log directory' do
      expect(Dir.exist?(log_dir)).to be true
    end
  end

  describe '#log_run' do
    it 'logs a watering run' do
      end_time = Time.now
      store.log_run(
        station_id: 0,
        program_id: 1,
        duration: 300,
        end_time: end_time,
        record_type: described_class::RECORD_PROGRAM
      )

      entries = store.get_entries(start_time: end_time.to_i - 1, end_time: end_time.to_i + 1)
      expect(entries.length).to eq(1)
      expect(entries[0][0]).to eq(1)  # program_id
      expect(entries[0][1]).to eq(0)  # station_id
      expect(entries[0][2]).to eq(300) # duration
      expect(entries[0][4]).to eq(0)  # record_type
    end

    it 'logs manual runs' do
      end_time = Time.now
      store.log_run(
        station_id: 2,
        program_id: 99,
        duration: 60,
        end_time: end_time,
        record_type: described_class::RECORD_MANUAL
      )

      entries = store.get_entries(start_time: end_time.to_i - 1, end_time: end_time.to_i + 1)
      expect(entries[0][4]).to eq(1)  # RECORD_MANUAL
    end
  end

  describe '#log_sensor' do
    it 'logs sensor activation' do
      timestamp = Time.now
      store.log_sensor(sensor_num: 1, active: true, timestamp: timestamp)

      entries = store.get_entries(start_time: timestamp.to_i - 1, end_time: timestamp.to_i + 1)
      expect(entries.length).to eq(1)
      expect(entries[0][1]).to eq(200)  # sensor 1 = station_id 200
      expect(entries[0][2]).to eq(1)    # active = 1
      expect(entries[0][4]).to eq(3)    # RECORD_SENSOR
    end

    it 'logs sensor deactivation' do
      timestamp = Time.now
      store.log_sensor(sensor_num: 2, active: false, timestamp: timestamp)

      entries = store.get_entries(start_time: timestamp.to_i - 1, end_time: timestamp.to_i + 1)
      expect(entries[0][1]).to eq(201)  # sensor 2 = station_id 201
      expect(entries[0][2]).to eq(0)    # inactive = 0
    end
  end

  describe '#get_entries' do
    it 'filters by date range' do
      day1 = Time.new(2024, 1, 1, 12, 0, 0)
      day2 = Time.new(2024, 1, 2, 12, 0, 0)
      day3 = Time.new(2024, 1, 3, 12, 0, 0)

      store.log_run(station_id: 0, program_id: 1, duration: 60, end_time: day1)
      store.log_run(station_id: 1, program_id: 1, duration: 60, end_time: day2)
      store.log_run(station_id: 2, program_id: 1, duration: 60, end_time: day3)

      # Get only day 2
      entries = store.get_entries(start_time: day2.to_i - 3600, end_time: day2.to_i + 3600)
      expect(entries.length).to eq(1)
      expect(entries[0][1]).to eq(1) # station_id
    end

    it 'returns entries sorted by timestamp' do
      now = Time.now.to_i
      store.log_run(station_id: 2, program_id: 1, duration: 60, end_time: Time.at(now + 100))
      store.log_run(station_id: 0, program_id: 1, duration: 60, end_time: Time.at(now))
      store.log_run(station_id: 1, program_id: 1, duration: 60, end_time: Time.at(now + 50))

      entries = store.get_entries(start_time: now - 1, end_time: now + 200)
      expect(entries.map { |e| e[1] }).to eq([0, 1, 2]) # sorted by time
    end
  end

  describe '#delete_before' do
    it 'deletes old log files' do
      old_time = Time.new(2024, 1, 1, 12, 0, 0)
      new_time = Time.new(2024, 1, 10, 12, 0, 0)

      store.log_run(station_id: 0, program_id: 1, duration: 60, end_time: old_time)
      store.log_run(station_id: 1, program_id: 1, duration: 60, end_time: new_time)

      # Delete logs before Jan 5
      deleted = store.delete_before(Time.new(2024, 1, 5))
      expect(deleted).to eq(1)

      # Old entry should be gone
      entries = store.get_entries(start_time: old_time.to_i - 3600, end_time: new_time.to_i + 3600)
      expect(entries.length).to eq(1)
      expect(entries[0][1]).to eq(1)
    end
  end

  describe '#clear' do
    it 'deletes all log files' do
      store.log_run(station_id: 0, program_id: 1, duration: 60, end_time: Time.now)
      store.log_run(station_id: 1, program_id: 1, duration: 60, end_time: Time.now + 86_400)

      store.clear

      entries = store.get_entries(start_time: 0, end_time: Time.now.to_i + 200_000)
      expect(entries).to be_empty
    end
  end

  describe '#total_size' do
    it 'returns total log size' do
      store.log_run(station_id: 0, program_id: 1, duration: 60, end_time: Time.now)

      expect(store.total_size).to be > 0
    end
  end
end
