# frozen_string_literal: true

require 'spec_helper'
require 'opensprinkler/scheduling/scheduler'
require 'opensprinkler/stations/station_store'

RSpec.describe OpenSprinkler::Scheduling::Scheduler do
  let(:stations) { OpenSprinkler::Stations::StationStore.new(num_stations: 8) }
  subject(:scheduler) { described_class.new(stations: stations) }

  before do
    scheduler.sunrise_time = 360   # 6:00 AM
    scheduler.sunset_time = 1080   # 6:00 PM
    scheduler.water_percentage = 100
  end

  describe '#manual_run' do
    it 'schedules a station for immediate run' do
      current_time = Time.new(2025, 1, 6, 8, 0, 0)

      scheduler.manual_run(
        station_id: 0,
        duration: 300,
        current_time: current_time
      )

      expect(scheduler.queue.size).to eq(1)
      item = scheduler.queue.find_by_station(0)
      expect(item.program_id).to eq(99)  # Manual program ID
      expect(item.duration).to eq(300)
    end

    it 'respects sequential groups' do
      stations[0].group_id = 0
      stations[1].group_id = 0
      current_time = Time.new(2025, 1, 6, 8, 0, 0)

      scheduler.manual_run(station_id: 0, duration: 300, current_time: current_time)
      scheduler.manual_run(station_id: 1, duration: 300, current_time: current_time)

      item0 = scheduler.queue.find_by_station(0)
      item1 = scheduler.queue.find_by_station(1)

      expect(item1.start_time).to eq(item0.start_time + 300)
    end

    it 'runs parallel stations immediately' do
      stations[0].group_id = 255  # Parallel
      stations[1].group_id = 255
      current_time = Time.new(2025, 1, 6, 8, 0, 0)

      scheduler.manual_run(station_id: 0, duration: 300, current_time: current_time)
      scheduler.manual_run(station_id: 1, duration: 300, current_time: current_time)

      item0 = scheduler.queue.find_by_station(0)
      item1 = scheduler.queue.find_by_station(1)

      expect(item1.start_time).to eq(item0.start_time)
    end
  end

  describe '#run_once' do
    it 'schedules multiple stations' do
      current_time = Time.new(2025, 1, 6, 8, 0, 0)

      scheduler.run_once(
        durations: [300, 0, 600, 0, 0, 0, 0, 0],
        current_time: current_time
      )

      expect(scheduler.queue.size).to eq(2)
      expect(scheduler.queue.station_queued?(0)).to be true
      expect(scheduler.queue.station_queued?(2)).to be true
    end

    it 'applies weather adjustment when enabled' do
      scheduler.water_percentage = 50
      current_time = Time.new(2025, 1, 6, 8, 0, 0)

      scheduler.run_once(
        durations: [600, 0, 0, 0, 0, 0, 0, 0],
        current_time: current_time,
        use_weather: true
      )

      item = scheduler.queue.find_by_station(0)
      expect(item.duration).to eq(300)
    end
  end

  describe '#process_queue' do
    it 'returns stations that should be running' do
      current_time = Time.new(2025, 1, 6, 8, 0, 0)

      scheduler.manual_run(station_id: 0, duration: 300, current_time: current_time)
      scheduler.manual_run(station_id: 2, duration: 300, current_time: current_time)

      # Advance time by 1 minute
      running = scheduler.process_queue(current_time + 60)

      expect(running).to contain_exactly(0, 2)
    end

    it 'removes finished items' do
      current_time = Time.new(2025, 1, 6, 8, 0, 0)

      scheduler.manual_run(station_id: 0, duration: 60, current_time: current_time)

      # Process at start - item running
      scheduler.process_queue(current_time + 30)
      expect(scheduler.queue.size).to eq(1)

      # Process after finish - item removed
      scheduler.process_queue(current_time + 120)
      expect(scheduler.queue.size).to eq(0)
    end
  end

  describe '#master_should_be_on?' do
    before do
      stations[0].master1_bound = true
      stations[1].master1_bound = false
    end

    it 'returns true when bound station is running' do
      current_time = Time.new(2025, 1, 6, 8, 0, 0)
      scheduler.manual_run(station_id: 0, duration: 300, current_time: current_time)

      result = scheduler.master_should_be_on?(
        current_time + 60,
        master_id: 0,
        master_station: 1,  # Some master station configured
        on_adjustment: 0,
        off_adjustment: 0
      )

      expect(result).to be true
    end

    it 'returns false when no bound stations running' do
      current_time = Time.new(2025, 1, 6, 8, 0, 0)
      scheduler.manual_run(station_id: 1, duration: 300, current_time: current_time)  # Not bound

      result = scheduler.master_should_be_on?(
        current_time + 60,
        master_id: 0,
        master_station: 1,
        on_adjustment: 0,
        off_adjustment: 0
      )

      expect(result).to be false
    end

    it 'respects on_adjustment' do
      current_time = Time.new(2025, 1, 6, 8, 0, 0)
      scheduler.manual_run(station_id: 0, duration: 300, current_time: current_time)

      # Master should be on 60 seconds before station starts
      result = scheduler.master_should_be_on?(
        current_time - 30,  # 30 seconds before station start
        master_id: 0,
        master_station: 1,
        on_adjustment: 60,  # Master starts 60 sec early
        off_adjustment: 0
      )

      expect(result).to be true
    end

    it 'respects off_adjustment' do
      current_time = Time.new(2025, 1, 6, 8, 0, 0)
      scheduler.manual_run(station_id: 0, duration: 300, current_time: current_time)

      # Master should stay on 60 seconds after station stops
      result = scheduler.master_should_be_on?(
        current_time + 330,  # 30 seconds after station stops
        master_id: 0,
        master_station: 1,
        on_adjustment: 0,
        off_adjustment: 60  # Master stays on 60 sec after
      )

      expect(result).to be true
    end
  end

  describe '#stop_all' do
    it 'clears the queue' do
      current_time = Time.new(2025, 1, 6, 8, 0, 0)
      scheduler.manual_run(station_id: 0, duration: 300, current_time: current_time)
      scheduler.manual_run(station_id: 1, duration: 300, current_time: current_time)

      scheduler.stop_all(current_time)

      expect(scheduler.queue.empty?).to be true
    end
  end

  describe '#station_program_status' do
    it 'returns status for all stations' do
      current_time = Time.new(2025, 1, 6, 8, 0, 0)
      scheduler.manual_run(station_id: 2, duration: 300, current_time: current_time)

      status = scheduler.station_program_status(current_time + 100)

      expect(status[2][0]).to eq(99)  # program_id
      expect(status[2][1]).to eq(200) # remaining time
      expect(status[0]).to eq([0, 0, 0, 0])  # not scheduled
    end
  end
end
