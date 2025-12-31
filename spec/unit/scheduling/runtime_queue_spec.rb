# frozen_string_literal: true

require 'spec_helper'
require 'opensprinkler/scheduling/runtime_queue'

RSpec.describe OpenSprinkler::Scheduling::RuntimeQueue do
  subject(:queue) { described_class.new }

  describe '#enqueue' do
    it 'adds item to queue' do
      item = queue.enqueue(
        station_id: 0,
        program_id: 1,
        start_time: 1000,
        duration: 300
      )

      expect(queue.size).to eq(1)
      expect(item.station_id).to eq(0)
    end

    it 'sets dequeue_time to end_time by default' do
      item = queue.enqueue(
        station_id: 0,
        program_id: 1,
        start_time: 1000,
        duration: 300
      )

      expect(item.dequeue_time).to eq(1300)
    end

    it 'prevents duplicate station entries' do
      queue.enqueue(station_id: 0, program_id: 1, start_time: 1000, duration: 300)
      result = queue.enqueue(station_id: 0, program_id: 2, start_time: 2000, duration: 300)

      expect(result).to be_nil
      expect(queue.size).to eq(1)
    end
  end

  describe '#dequeue' do
    before do
      queue.enqueue(station_id: 0, program_id: 1, start_time: 1000, duration: 300)
      queue.enqueue(station_id: 1, program_id: 1, start_time: 1000, duration: 300)
      queue.enqueue(station_id: 2, program_id: 1, start_time: 1000, duration: 300)
    end

    it 'removes item by index' do
      queue.dequeue(1)
      expect(queue.size).to eq(2)
      expect(queue.station_queued?(1)).to be false
    end

    it 'maintains station_qid mapping after dequeue' do
      queue.dequeue(0)

      # Station 2's item moved to index 0
      expect(queue.find_by_station(2)).not_to be_nil
      expect(queue.find_by_station(1)).not_to be_nil
    end
  end

  describe '#dequeue_station' do
    it 'removes item by station ID' do
      queue.enqueue(station_id: 5, program_id: 1, start_time: 1000, duration: 300)

      queue.dequeue_station(5)

      expect(queue.station_queued?(5)).to be false
      expect(queue.size).to eq(0)
    end
  end

  describe '#running_items' do
    before do
      queue.enqueue(station_id: 0, program_id: 1, start_time: 1000, duration: 300)
      queue.enqueue(station_id: 1, program_id: 1, start_time: 1500, duration: 300)
    end

    it 'returns items currently running' do
      running = queue.running_items(1100)
      expect(running.map(&:station_id)).to eq([0])
    end

    it 'returns empty when nothing running' do
      running = queue.running_items(500)
      expect(running).to be_empty
    end

    it 'returns multiple when overlapping' do
      queue.enqueue(station_id: 2, program_id: 1, start_time: 1050, duration: 100)
      running = queue.running_items(1100)
      expect(running.map(&:station_id)).to contain_exactly(0, 2)
    end
  end

  describe '#active_station_ids' do
    before do
      queue.enqueue(station_id: 0, program_id: 1, start_time: 1000, duration: 300)
      queue.enqueue(station_id: 3, program_id: 1, start_time: 1000, duration: 300)
    end

    it 'returns station IDs that should be on' do
      ids = queue.active_station_ids(1100)
      expect(ids).to contain_exactly(0, 3)
    end
  end

  describe '#apply_pause and #apply_resume' do
    before do
      queue.enqueue(station_id: 0, program_id: 1, start_time: 1000, duration: 300)
      queue.enqueue(station_id: 1, program_id: 1, start_time: 2000, duration: 300)
    end

    it 'adjusts times for currently running items' do
      queue.apply_pause(1100, 600) # Pause at 1100 for 600 seconds

      item = queue.find_by_station(0)
      expect(item.start_time).to eq(1700)  # 1100 + 600
      expect(item.duration).to eq(200)     # 300 - (1100 - 1000)
    end

    it 'pushes back scheduled items' do
      queue.apply_pause(1100, 600)

      item = queue.find_by_station(1)
      expect(item.start_time).to eq(2600)  # 2000 + 600
    end

    it 'resume pulls times back' do
      queue.apply_pause(1100, 600)
      queue.apply_resume(600)

      item = queue.find_by_station(1)
      # NOTE: resume adds 1 second adjustment
      expect(item.start_time).to eq(2001) # 2600 - 600 + 1
    end
  end
end

RSpec.describe OpenSprinkler::Scheduling::QueueItem do
  let(:item) do
    described_class.new(
      start_time: 1000,
      duration: 300,
      station_id: 0,
      program_id: 1,
      dequeue_time: 1300
    )
  end

  describe '#running?' do
    it 'returns true during run window' do
      expect(item.running?(1000)).to be true
      expect(item.running?(1150)).to be true
      expect(item.running?(1299)).to be true
    end

    it 'returns false before start' do
      expect(item.running?(999)).to be false
    end

    it 'returns false after end' do
      expect(item.running?(1300)).to be false
    end
  end

  describe '#finished?' do
    it 'returns true after duration' do
      expect(item.finished?(1300)).to be true
      expect(item.finished?(2000)).to be true
    end

    it 'returns false before end' do
      expect(item.finished?(1299)).to be false
    end
  end

  describe '#end_time' do
    it 'returns start_time + duration' do
      expect(item.end_time).to eq(1300)
    end
  end
end
