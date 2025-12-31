# frozen_string_literal: true

require_relative '../constants'
require_relative 'runtime_queue'
require_relative 'program'

module OpenSprinkler
  module Scheduling
    # Main scheduling engine
    #
    # Responsibilities:
    # - Check programs for matches each minute
    # - Schedule station runs with proper timing
    # - Handle sequential groups (stations in same group run one after another)
    # - Handle master station timing adjustments
    class Scheduler
      include Constants

      # Queue options
      QUEUE_APPEND       = 0
      QUEUE_INSERT_FRONT = 1
      QUEUE_REPLACE      = 2

      attr_reader :queue, :programs, :last_seq_stop_times
      attr_accessor :sunrise_time, :sunset_time, :water_percentage

      def initialize(stations:)
        @stations = stations
        @queue = RuntimeQueue.new
        @programs = []
        @last_seq_stop_times = Array.new(NUM_SEQ_GROUPS, 0)
        @sunrise_time = 360   # 6:00 AM default
        @sunset_time = 1080   # 6:00 PM default
        @water_percentage = 100
        @last_minute_checked = -1
      end

      # Load programs from array of hashes
      def load_programs(program_data)
        @programs = program_data.map.with_index do |data, idx|
          Program.from_h(data.merge('id' => idx))
        end
      end

      # Add a program
      def add_program(program)
        program.id = @programs.size
        @programs << program
        program
      end

      # Check all programs and schedule matching ones
      # Called once per minute
      # @param current_time [Time] Current time
      # @param queue_option [Integer] How to handle existing queue
      def check_programs(current_time, queue_option: QUEUE_APPEND)
        current_minute = current_time.min + (current_time.hour * 60)

        # Only check once per minute
        return if current_minute == @last_minute_checked

        @last_minute_checked = current_minute

        programs_to_delete = []

        @programs.each_with_index do |program, idx|
          match_count = program.check_match(
            current_time,
            sunrise_time: @sunrise_time,
            sunset_time: @sunset_time
          )

          next unless match_count

          # Schedule all active stations from this program
          schedule_program(program, current_time, queue_option: queue_option)

          # Mark single-run programs for deletion after last match
          if program.type == Program::TYPE_SINGLE_RUN
            programs_to_delete << idx
          end
        end

        # Delete single-run programs (in reverse order to preserve indices)
        programs_to_delete.reverse_each do |idx|
          @programs.delete_at(idx)
        end
      end

      # Schedule all stations from a program
      def schedule_program(program, current_time, queue_option: QUEUE_APPEND)
        if queue_option == QUEUE_REPLACE
          @queue.clear
          reset_sequential_times
        end

        program.active_stations.each do |station_id|
          next if station_id >= @stations.count
          next if @stations[station_id].disabled

          duration = program.duration_for(station_id, water_percentage: @water_percentage)
          next if duration == 0

          schedule_station(
            station_id: station_id,
            duration: duration,
            program_id: program.id + 1,  # API uses 1-based program IDs
            current_time: current_time,
            queue_option: queue_option
          )
        end
      end

      # Schedule a single station run
      def schedule_station(station_id:, duration:, program_id:, current_time:, queue_option: QUEUE_APPEND)
        return if @queue.station_queued?(station_id)

        station = @stations[station_id]
        return if station.disabled

        group_id = station.group_id

        # Calculate start time based on sequential group
        if group_id == PARALLEL_GROUP_ID
          # Parallel station starts immediately
          start_time = current_time.to_i
        else
          # Sequential station starts after last in group
          group_idx = group_id < NUM_SEQ_GROUPS ? group_id : 0
          last_stop = @last_seq_stop_times[group_idx]

          if last_stop > current_time.to_i
            start_time = last_stop
          else
            start_time = current_time.to_i
          end

          # Update last stop time for this group
          @last_seq_stop_times[group_idx] = start_time + duration
        end

        # Calculate dequeue time (may be extended for master off adjustment)
        dequeue_time = start_time + duration

        if queue_option == QUEUE_INSERT_FRONT
          # Insert at front by making start time immediate
          start_time = current_time.to_i
          dequeue_time = start_time + duration
        end

        @queue.enqueue(
          station_id: station_id,
          program_id: program_id,
          start_time: start_time,
          duration: duration,
          dequeue_time: dequeue_time
        )
      end

      # Manual station control
      def manual_run(station_id:, duration:, current_time:, queue_option: QUEUE_APPEND)
        schedule_station(
          station_id: station_id,
          duration: duration,
          program_id: RuntimeQueue::PROGRAM_MANUAL,
          current_time: current_time,
          queue_option: queue_option
        )
      end

      # Run-once program (manual program with multiple stations)
      def run_once(durations:, current_time:, queue_option: QUEUE_REPLACE, use_weather: false)
        if queue_option == QUEUE_REPLACE
          @queue.clear
          reset_sequential_times
        end

        wp = use_weather ? @water_percentage : 100

        durations.each_with_index do |duration, station_id|
          next if duration == 0
          next if station_id >= @stations.count
          next if @stations[station_id].disabled

          adjusted_duration = use_weather ? (duration * wp / 100) : duration

          schedule_station(
            station_id: station_id,
            duration: adjusted_duration,
            program_id: RuntimeQueue::PROGRAM_RUN_ONCE,
            current_time: current_time,
            queue_option: queue_option
          )
        end
      end

      # Process the queue - determine which stations should be on
      # @param current_time [Time] Current time
      # @return [Array<Integer>] Station IDs that should be on
      def process_queue(current_time)
        current_ts = current_time.to_i

        # Dequeue finished items
        @queue.dequeueable_items(current_ts).each do |item|
          @queue.dequeue_station(item.station_id)
        end

        # Return stations that should be running
        @queue.active_station_ids(current_ts)
      end

      # Calculate master station state
      # @param current_time [Time] Current time
      # @param master_id [Integer] Master station index (0 = master 1, 1 = master 2)
      # @param on_adjustment [Integer] Seconds to delay master on
      # @param off_adjustment [Integer] Seconds to extend master off
      # @return [Boolean] Whether master should be on
      def master_should_be_on?(current_time, master_id:, master_station:, on_adjustment:, off_adjustment:)
        return false if master_station == 0  # No master configured

        current_ts = current_time.to_i

        @queue.each do |item|
          station = @stations[item.station_id]
          next unless station

          # Check if this station is bound to this master
          bound = master_id == 0 ? station.master1_bound : station.master2_bound
          next unless bound

          # Check if station is within master window
          # Master turns on: station_start - on_adjustment
          # Master turns off: station_end + off_adjustment
          master_on_time = item.start_time - on_adjustment
          master_off_time = item.end_time + off_adjustment

          if current_ts >= master_on_time && current_ts < master_off_time
            return true
          end
        end

        false
      end

      # Reset sequential stop times
      def reset_sequential_times
        @last_seq_stop_times.fill(0)
      end

      # Stop all running stations
      def stop_all(current_time)
        @queue.clear
        reset_sequential_times
      end

      # Pause all stations
      def pause(current_time, duration)
        @queue.apply_pause(current_time.to_i, duration)
      end

      # Resume from pause
      def resume(pause_duration)
        @queue.apply_resume(pause_duration)
      end

      # Get program status for each station (for /jc API)
      # Returns array of [program_id, remaining_time, start_time, original_duration]
      def station_program_status(current_time)
        current_ts = current_time.to_i

        Array.new(@stations.count) do |station_id|
          item = @queue.find_by_station(station_id)
          if item
            remaining = [item.end_time - current_ts, 0].max
            [item.program_id, remaining, item.start_time, item.duration]
          else
            [0, 0, 0, 0]
          end
        end
      end
    end
  end
end
