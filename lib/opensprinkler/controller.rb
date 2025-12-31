# frozen_string_literal: true

require_relative 'constants'
require_relative 'options'
require_relative 'hardware/gpio'
require_relative 'hardware/shift_register'
require_relative 'hardware/sensors'
require_relative 'stations/station_store'
require_relative 'scheduling/program_store'
require_relative 'scheduling/scheduler'

module OpenSprinkler
  # Main controller that coordinates all OpenSprinkler components
  #
  # The controller runs the main loop every second:
  # - Polls sensors (rain, soil)
  # - Checks rain delay status
  # - Schedules programs (once per minute)
  # - Processes queue and activates/deactivates stations
  # - Controls master station timing
  class Controller
    include Constants

    attr_reader :gpio, :shift_register, :sensors, :options, :stations
    attr_reader :program_store, :scheduler

    # Controller status
    attr_accessor :rain_delay_stop_time, :pause_state, :pause_timer
    attr_accessor :master1_station, :master2_station
    attr_accessor :master1_on_adj, :master1_off_adj
    attr_accessor :master2_on_adj, :master2_off_adj

    def initialize(options:, gpio: nil, data_dir: nil)
      @options = options
      @data_dir = data_dir || '/var/opensprinkler'

      # Initialize GPIO (auto-detect if not provided)
      @gpio = gpio || OpenSprinkler.create_gpio(:auto)

      # Initialize hardware
      @shift_register = Hardware::ShiftRegister.new(gpio: @gpio)
      @sensors = Hardware::Sensors.new(gpio: @gpio)

      # Initialize stations
      num_stations = @options.int.num_stations
      @stations = Stations::StationStore.new(num_stations: num_stations)
      @stations.file_path = File.join(@data_dir, 'stations.yml')
      @stations.load if File.exist?(@stations.file_path)

      # Initialize programs
      @program_store = Scheduling::ProgramStore.new(
        file_path: File.join(@data_dir, 'programs.yml')
      )
      @program_store.load

      # Initialize scheduler
      @scheduler = Scheduling::Scheduler.new(stations: @stations)
      @scheduler.water_percentage = @options.int[:water_percentage]

      # Controller state
      @rain_delay_stop_time = 0
      @rain_delayed = false
      @old_rain_delayed = false
      @rain_delay_on_lasttime = 0

      @pause_state = false
      @pause_timer = 0

      # Master station configuration
      @master1_station = @options.int[:master_station]
      @master2_station = @options.int[:master_station_2]
      @master1_on_adj = @options.int[:master_on_adj]
      @master1_off_adj = @options.int[:master_off_adj]
      @master2_on_adj = @options.int[:master_on_adj_2]
      @master2_off_adj = @options.int[:master_off_adj_2]
      @master1_last_on = 0
      @master2_last_on = 0

      # Configure sensors from options
      configure_sensors

      # Time tracking
      @last_second = 0
      @last_minute = -1

      # Running state
      @running = false
      @running_stations = []
    end

    # Configure sensors from options
    def configure_sensors
      @sensors.configure(
        sensor_num: 1,
        type: @options.int[:sensor1_type],
        option: @options.int[:sensor1_option],
        on_delay: @options.int[:sensor1_on_delay],
        off_delay: @options.int[:sensor1_off_delay]
      )

      @sensors.configure(
        sensor_num: 2,
        type: @options.int[:sensor2_type],
        option: @options.int[:sensor2_option],
        on_delay: @options.int[:sensor2_on_delay],
        off_delay: @options.int[:sensor2_off_delay]
      )
    end

    # Start the main loop
    def start
      @running = true
      run_loop
    end

    # Stop the main loop
    def stop
      @running = false
    end

    # Run one iteration of the control loop
    # @param current_time [Time] Current time (for testing)
    def tick(current_time = Time.now)
      current_ts = current_time.to_i

      # Only run once per second
      return if current_ts == @last_second

      @last_second = current_ts

      # Check rain delay status
      check_rain_delay(current_ts)

      # Poll sensors
      sensor_changes = @sensors.poll(current_ts)
      handle_sensor_changes(sensor_changes, current_ts)

      # Check programs (once per minute)
      current_minute = current_time.min + (current_time.hour * 60)
      if current_minute != @last_minute
        @last_minute = current_minute
        check_programs(current_time)
      end

      # Handle pause countdown
      if @pause_state
        if @pause_timer > 0
          @pause_timer -= 1
        else
          # Pause expired
          clear_pause
        end
      end

      # Process queue - determine which stations should be on
      if @pause_state
        # During pause, all stations should be off
        @running_stations = []
      else
        @running_stations = @scheduler.process_queue(current_time)
      end

      # Apply station bits
      apply_station_state(current_time)

      # Update sequential stop times
      update_sequential_stop_times(current_ts)
    end

    # Main run loop
    def run_loop
      while @running
        tick
        sleep 0.1  # Small sleep to prevent CPU spinning
      end
    ensure
      # Turn off all stations on exit
      @shift_register.clear
      @shift_register.apply(enabled: true)
    end

    # ========== Rain Delay ==========

    def check_rain_delay(current_ts)
      if @rain_delayed
        if current_ts >= @rain_delay_stop_time
          raindelay_stop
        end
      else
        if @rain_delay_stop_time > current_ts
          raindelay_start(current_ts)
        end
      end

      # Track state changes for logging
      if @old_rain_delayed != @rain_delayed
        @old_rain_delayed = @rain_delayed
        # TODO: Write log and send notification
      end
    end

    def raindelay_start(current_ts)
      @rain_delayed = true
      @rain_delay_on_lasttime = current_ts
    end

    def raindelay_stop
      @rain_delayed = false
    end

    def rain_delayed?
      @rain_delayed
    end

    # Set rain delay in hours
    def set_rain_delay(hours, current_time = Time.now)
      if hours > 0
        @rain_delay_stop_time = current_time.to_i + (hours * 3600)
      else
        @rain_delay_stop_time = 0
        raindelay_stop
      end
    end

    # Get remaining rain delay in hours
    def rain_delay_remaining(current_time = Time.now)
      return 0 unless @rain_delayed

      remaining = @rain_delay_stop_time - current_time.to_i
      remaining > 0 ? (remaining / 3600.0).ceil : 0
    end

    # ========== Pause ==========

    def pause(duration_seconds)
      @pause_state = true
      @pause_timer = duration_seconds
      @scheduler.pause(Time.now, duration_seconds)
    end

    def resume
      pause_duration = @pause_timer
      @pause_state = false
      @pause_timer = 0
      @scheduler.resume(pause_duration)
    end

    def clear_pause
      @pause_state = false
      @pause_timer = 0
    end

    # ========== Programs ==========

    def check_programs(current_time)
      # Update scheduler settings from options
      @scheduler.water_percentage = @options.int[:water_percentage]

      # Calculate sunrise/sunset if needed
      update_sun_times(current_time)

      @program_store.each do |program|
        match_count = program.check_match(
          current_time,
          sunrise_time: @scheduler.sunrise_time,
          sunset_time: @scheduler.sunset_time
        )

        next unless match_count

        # Check if watering is allowed
        next if should_skip_watering?

        # Schedule the program
        @scheduler.schedule_program(program, current_time)
      end
    end

    def should_skip_watering?
      return true if rain_delayed?
      return true if @sensors.rain_sensed? && !@options.int[:ignore_rain].zero?

      # Check soil sensor with per-station ignore
      # (handled at station level in schedule_program)

      false
    end

    # ========== Station Control ==========

    def apply_station_state(current_time)
      current_ts = current_time.to_i

      # Apply regular station bits
      @running_stations.each do |station_id|
        next if station_id == @master1_station - 1
        next if station_id == @master2_station - 1

        @shift_register.set_station_bit(station_id, 1)
      end

      # Clear stations that should not be on
      @stations.each_with_index do |_station, station_id|
        next if station_id == @master1_station - 1
        next if station_id == @master2_station - 1

        unless @running_stations.include?(station_id)
          @shift_register.set_station_bit(station_id, 0)
        end
      end

      # Handle master stations
      handle_master_stations(current_time)

      # Apply to hardware
      @shift_register.apply(enabled: !@options.int[:device_enable].zero?)
    end

    def handle_master_stations(current_time)
      # Master 1
      if @master1_station > 0
        should_be_on = @scheduler.master_should_be_on?(
          current_time,
          master_id: 0,
          master_station: @master1_station,
          on_adjustment: @master1_on_adj,
          off_adjustment: @master1_off_adj
        )

        @shift_register.set_station_bit(@master1_station - 1, should_be_on ? 1 : 0)

        # Track state for notifications
        track_master_state(0, should_be_on, current_time.to_i)
      end

      # Master 2
      if @master2_station > 0
        should_be_on = @scheduler.master_should_be_on?(
          current_time,
          master_id: 1,
          master_station: @master2_station,
          on_adjustment: @master2_on_adj,
          off_adjustment: @master2_off_adj
        )

        @shift_register.set_station_bit(@master2_station - 1, should_be_on ? 1 : 0)
        track_master_state(1, should_be_on, current_time.to_i)
      end
    end

    def track_master_state(master_id, is_on, current_ts)
      last_on = master_id == 0 ? @master1_last_on : @master2_last_on

      if last_on == 0 && is_on
        # Master just turned on
        if master_id == 0
          @master1_last_on = current_ts
        else
          @master2_last_on = current_ts
        end
        # TODO: Send notification
      elsif last_on > 0 && !is_on
        # Master just turned off
        if master_id == 0
          @master1_last_on = 0
        else
          @master2_last_on = 0
        end
        # TODO: Send notification with duration
      end
    end

    def update_sequential_stop_times(current_ts)
      @scheduler.queue.each do |item|
        end_time = item.start_time + item.duration
        next unless end_time > current_ts

        station = @stations[item.station_id]
        next unless station

        group_id = station.group_id
        next if group_id == PARALLEL_GROUP_ID

        group_idx = group_id < NUM_SEQ_GROUPS ? group_id : 0
        if end_time > @scheduler.last_seq_stop_times[group_idx]
          @scheduler.last_seq_stop_times[group_idx] = end_time
        end
      end
    end

    # ========== Manual Control ==========

    def manual_start_station(station_id, duration, current_time = Time.now)
      @scheduler.manual_run(
        station_id: station_id,
        duration: duration,
        current_time: current_time
      )
    end

    def manual_stop_station(station_id)
      @scheduler.queue.dequeue_station(station_id)
    end

    def stop_all_stations(current_time = Time.now)
      @scheduler.stop_all(current_time)
      @shift_register.clear
      @shift_register.apply(enabled: true)
    end

    # Run-once program
    def run_once(durations, use_weather: false, current_time: Time.now)
      @scheduler.run_once(
        durations: durations,
        current_time: current_time,
        use_weather: use_weather
      )
    end

    # ========== Sun Times ==========

    def update_sun_times(current_time)
      # TODO: Calculate actual sunrise/sunset from latitude/longitude
      # For now use hardcoded defaults (sunrise/sunset times aren't stored in options)
      @scheduler.sunrise_time ||= 360   # 6:00 AM
      @scheduler.sunset_time ||= 1080   # 6:00 PM
    end

    # ========== Sensor Changes ==========

    def handle_sensor_changes(changes, current_ts)
      if changes[:sensor1_changed]
        # TODO: Write log entry
        # TODO: Send notification
      end

      if changes[:sensor2_changed]
        # TODO: Write log entry
        # TODO: Send notification
      end
    end

    # ========== Status ==========

    def status
      {
        enabled: @options.int[:device_enable] != 0,
        rain_delayed: @rain_delayed,
        rain_delay_remaining: rain_delay_remaining,
        sensors: @sensors.status,
        paused: @pause_state,
        pause_remaining: @pause_timer,
        program_busy: !@scheduler.queue.empty?,
        running_stations: @running_stations
      }
    end

    # Get status for /jc API endpoint
    def controller_status(current_time = Time.now)
      sn = @stations.count.times.map do |i|
        @running_stations.include?(i) ? 1 : 0
      end

      ps = @scheduler.station_program_status(current_time)

      {
        'devt' => current_time.to_i,
        'nbrd' => @options.int.num_boards,
        'en' => @options.int[:device_enable],
        'rd' => @rain_delayed ? 1 : 0,
        'rs' => @sensors.rain_sensed? ? 1 : 0,
        'rdst' => @rain_delay_stop_time,
        'loc' => @options.string ? @options.string[:location] : '0,0',
        'sbits' => station_bits_array,
        'ps' => ps,
        'lrun' => last_run_info,
        'sn1' => @sensors.sensor1.active ? 1 : 0,
        'sn2' => @sensors.sensor2.active ? 1 : 0,
        'pq' => @pause_state ? 1 : 0,
        'pt' => @pause_timer
      }
    end

    def station_bits_array
      # Return array of bytes representing station bits per board
      Array.new(@options.int.num_boards) do |board|
        byte = 0
        8.times do |bit|
          station_id = board * 8 + bit
          if @running_stations.include?(station_id)
            byte |= (1 << bit)
          end
        end
        byte
      end
    end

    def last_run_info
      # TODO: Track last run info
      [0, 0, 0, 0]  # [station, program, duration, end_time]
    end
  end
end
