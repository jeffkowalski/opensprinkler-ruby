# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'opensprinkler/controller'
require 'opensprinkler/options'

RSpec.describe OpenSprinkler::Controller do
  let(:int_options) { OpenSprinkler::IntegerOptions.new }
  let(:string_options) { OpenSprinkler::StringOptions.new }
  let(:options) do
    double('Options', int: int_options, string: string_options)
  end
  let(:gpio) { OpenSprinkler::Hardware::MockGPIO.new }
  let(:data_dir) { Dir.mktmpdir }
  subject(:controller) do
    described_class.new(options: options, gpio: gpio, data_dir: data_dir)
  end

  after do
    FileUtils.rm_rf(data_dir) if data_dir && File.exist?(data_dir)
  end

  describe '#initialize' do
    it 'creates all components' do
      expect(controller.gpio).to eq(gpio)
      expect(controller.shift_register).to be_a(OpenSprinkler::Hardware::ShiftRegister)
      expect(controller.sensors).to be_a(OpenSprinkler::Hardware::Sensors)
      expect(controller.stations).to be_a(OpenSprinkler::Stations::StationStore)
      expect(controller.scheduler).to be_a(OpenSprinkler::Scheduling::Scheduler)
    end

    it 'configures sensors from options' do
      int_options[:sensor1_type] = OpenSprinkler::Constants::SENSOR_TYPE_RAIN
      int_options[:sensor1_option] = 1

      ctrl = described_class.new(options: options, gpio: gpio, data_dir: data_dir)

      expect(ctrl.sensors.sensor1.type).to eq(OpenSprinkler::Constants::SENSOR_TYPE_RAIN)
      expect(ctrl.sensors.sensor1.option).to eq(1)
    end
  end

  describe '#tick' do
    it 'runs control loop once per second' do
      time1 = Time.new(2025, 1, 6, 8, 0, 0)
      time2 = Time.new(2025, 1, 6, 8, 0, 0) + 0.5  # Same second

      controller.tick(time1)
      expect(gpio.log).not_to be_empty

      gpio.clear_log
      controller.tick(time2)
      expect(gpio.log).to be_empty  # No action for same second
    end
  end

  describe '#set_rain_delay' do
    it 'sets rain delay in hours' do
      current_time = Time.new(2025, 1, 6, 8, 0, 0)

      controller.set_rain_delay(24, current_time)

      expect(controller.rain_delay_stop_time).to eq(current_time.to_i + 86400)
    end

    it 'clears rain delay when set to 0' do
      current_time = Time.new(2025, 1, 6, 8, 0, 0)

      controller.set_rain_delay(24, current_time)
      controller.tick(current_time)  # Activate rain delay
      expect(controller.rain_delayed?).to be true

      controller.set_rain_delay(0, current_time)
      expect(controller.rain_delayed?).to be false
    end
  end

  describe '#rain_delay_remaining' do
    it 'returns remaining hours' do
      current_time = Time.new(2025, 1, 6, 8, 0, 0)

      controller.set_rain_delay(24, current_time)
      controller.tick(current_time)

      # Check 12 hours later
      expect(controller.rain_delay_remaining(current_time + 43200)).to eq(12)
    end
  end

  describe 'rain delay in control loop' do
    it 'activates rain delay when stop time is in future' do
      current_time = Time.new(2025, 1, 6, 8, 0, 0)

      controller.rain_delay_stop_time = current_time.to_i + 3600

      controller.tick(current_time)

      expect(controller.rain_delayed?).to be true
    end

    it 'deactivates rain delay when time expires' do
      current_time = Time.new(2025, 1, 6, 8, 0, 0)

      controller.set_rain_delay(1, current_time)
      controller.tick(current_time)
      expect(controller.rain_delayed?).to be true

      # 2 hours later
      later_time = current_time + 7200
      controller.tick(later_time)
      expect(controller.rain_delayed?).to be false
    end
  end

  describe '#pause and #resume' do
    it 'pauses watering' do
      controller.pause(300)

      expect(controller.pause_state).to be true
      expect(controller.pause_timer).to eq(300)
    end

    it 'resumes watering' do
      controller.pause(300)
      controller.resume

      expect(controller.pause_state).to be false
      expect(controller.pause_timer).to eq(0)
    end

    it 'counts down pause timer each second' do
      current_time = Time.new(2025, 1, 6, 8, 0, 0)

      controller.pause(10)
      controller.tick(current_time)

      expect(controller.pause_timer).to eq(9)

      controller.tick(current_time + 1)
      expect(controller.pause_timer).to eq(8)
    end

    it 'clears pause when timer reaches 0' do
      current_time = Time.new(2025, 1, 6, 8, 0, 0)

      controller.pause(2)
      controller.tick(current_time)
      controller.tick(current_time + 1)
      controller.tick(current_time + 2)

      expect(controller.pause_state).to be false
    end
  end

  describe '#manual_start_station' do
    it 'schedules a station for immediate run' do
      current_time = Time.new(2025, 1, 6, 8, 0, 0)

      controller.manual_start_station(0, 300, current_time)

      expect(controller.scheduler.queue.size).to eq(1)
      expect(controller.scheduler.queue.station_queued?(0)).to be true
    end
  end

  describe '#manual_stop_station' do
    it 'removes station from queue' do
      current_time = Time.new(2025, 1, 6, 8, 0, 0)

      controller.manual_start_station(0, 300, current_time)
      expect(controller.scheduler.queue.station_queued?(0)).to be true

      controller.manual_stop_station(0)
      expect(controller.scheduler.queue.station_queued?(0)).to be false
    end
  end

  describe '#stop_all_stations' do
    it 'clears queue and shift register' do
      current_time = Time.new(2025, 1, 6, 8, 0, 0)

      controller.manual_start_station(0, 300, current_time)
      controller.manual_start_station(1, 300, current_time)

      controller.stop_all_stations(current_time)

      expect(controller.scheduler.queue.empty?).to be true
    end
  end

  describe '#run_once' do
    it 'schedules multiple stations' do
      current_time = Time.new(2025, 1, 6, 8, 0, 0)

      controller.run_once([300, 0, 600, 0, 0, 0, 0, 0], current_time: current_time)

      expect(controller.scheduler.queue.station_queued?(0)).to be true
      expect(controller.scheduler.queue.station_queued?(2)).to be true
    end
  end

  describe '#controller_status' do
    it 'returns status hash for API' do
      current_time = Time.new(2025, 1, 6, 8, 0, 0)

      status = controller.controller_status(current_time)

      expect(status['devt']).to eq(current_time.to_i)
      expect(status['nbrd']).to be_a(Integer)
      expect(status['sbits']).to be_a(Array)
      expect(status['ps']).to be_a(Array)
    end
  end

  describe '#status' do
    it 'returns controller status' do
      status = controller.status

      expect(status).to have_key(:enabled)
      expect(status).to have_key(:rain_delayed)
      expect(status).to have_key(:sensors)
      expect(status).to have_key(:paused)
    end
  end
end
