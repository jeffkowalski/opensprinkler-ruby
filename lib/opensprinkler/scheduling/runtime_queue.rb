# frozen_string_literal: true

require_relative '../constants'

module OpenSprinkler
  module Scheduling
    # Represents a single item in the runtime queue
    QueueItem = Struct.new(
      :start_time,    # Time when station should start
      :duration,      # Duration in seconds
      :station_id,    # Station index (0-based)
      :program_id,    # Program that scheduled this (99 = manual, 254 = run-once)
      :dequeue_time,  # Time when item can be removed (may be > start_time + duration for master off adjustment)
      keyword_init: true
    ) do
      # Check if this item is currently running
      def running?(current_time)
        current_time >= start_time && current_time < start_time + duration
      end

      # Check if this item has finished
      def finished?(current_time)
        current_time >= start_time + duration
      end

      # Check if this item can be dequeued
      def can_dequeue?(current_time)
        current_time >= dequeue_time
      end

      # Time when this item finishes running
      def end_time
        start_time + duration
      end
    end

    # Runtime queue for managing scheduled station runs
    #
    # This is a simple array-based queue where:
    # - Items are added when programs trigger or manual runs are requested
    # - Items are removed when they complete (after dequeue_time)
    # - Each station can only have one queue entry at a time
    class RuntimeQueue
      include Constants

      # Special program IDs
      PROGRAM_MANUAL   = 99   # Manual station run
      PROGRAM_RUN_ONCE = 254  # Run-once program

      attr_reader :items

      def initialize
        @items = []
        @station_qid = {} # Maps station_id -> queue index
      end

      # Number of items in queue
      def size
        @items.size
      end

      # Check if queue is empty
      def empty?
        @items.empty?
      end

      # Add an item to the queue
      # @return [QueueItem, nil] The added item, or nil if queue is full
      def enqueue(station_id:, program_id:, start_time:, duration:, dequeue_time: nil)
        return nil if @items.size >= MAX_NUM_STATIONS
        return nil if @station_qid.key?(station_id) # Station already queued

        dequeue_time ||= start_time + duration

        item = QueueItem.new(
          start_time: start_time,
          duration: duration,
          station_id: station_id,
          program_id: program_id,
          dequeue_time: dequeue_time
        )

        @items << item
        @station_qid[station_id] = @items.size - 1
        item
      end

      # Remove an item from the queue by index
      def dequeue(index)
        return if index >= @items.size

        removed = @items[index]
        @station_qid.delete(removed.station_id)

        # If not the last item, move the last item to fill the gap
        if index < @items.size - 1
          @items[index] = @items.pop
          @station_qid[@items[index].station_id] = index
        else
          @items.pop
        end

        removed
      end

      # Remove item for a specific station
      def dequeue_station(station_id)
        index = @station_qid[station_id]
        return unless index

        dequeue(index)
      end

      # Find queue item for a station
      def find_by_station(station_id)
        index = @station_qid[station_id]
        return nil unless index

        @items[index]
      end

      # Check if a station is queued
      def station_queued?(station_id)
        @station_qid.key?(station_id)
      end

      # Get all items that should be running at given time
      def running_items(current_time)
        @items.select { |item| item.running?(current_time) }
      end

      # Get all items that can be dequeued at given time
      def dequeueable_items(current_time)
        @items.select { |item| item.can_dequeue?(current_time) }
      end

      # Clear all items
      def clear
        @items.clear
        @station_qid.clear
      end

      # Iterate over all items
      def each(&block)
        @items.each(&block)
      end

      include Enumerable

      # Apply pause: stop running stations and push back times
      def apply_pause(current_time, pause_duration)
        @items.each do |item|
          if current_time >= item.end_time
            # Already finished, nothing to adjust
            next
          elsif current_time >= item.start_time
            # Currently running - adjust remaining time
            remaining = item.duration - (current_time - item.start_time)
            item.duration = remaining
            item.start_time = current_time + pause_duration
          else
            # Not started yet - just push back
            item.start_time += pause_duration
          end

          item.dequeue_time += pause_duration
        end
      end

      # Resume from pause: pull times back
      def apply_resume(pause_duration)
        @items.each do |item|
          item.start_time -= pause_duration
          item.dequeue_time -= pause_duration
          # Add small adjustment for scheduler
          item.start_time += 1
          item.dequeue_time += 1
        end
      end

      # Get stations that should be on at given time
      def active_station_ids(current_time)
        running_items(current_time).map(&:station_id)
      end

      # Convert to array of hashes (for API)
      def to_a
        @items.map do |item|
          {
            'st' => item.start_time.to_i,
            'dur' => item.duration,
            'sid' => item.station_id,
            'pid' => item.program_id,
            'dqt' => item.dequeue_time.to_i
          }
        end
      end
    end
  end
end
