# frozen_string_literal: true

require 'yaml'
require_relative 'constants'

module OpenSprinkler
  # Integer options - corresponds to iopts[] in C++ firmware
  # These control firmware behavior and hardware settings
  class IntegerOptions
    include Constants

    # Option metadata: name, default value, read-only flag, description
    DEFINITIONS = {
      fw_version: { index: 0, default: FW_VERSION, readonly: true, desc: 'Firmware version' },
      timezone: { index: 1, default: 28, desc: 'Timezone offset (hours*4+48, so 28 = GMT-5)' },
      use_ntp: { index: 2, default: 1, desc: 'NTP sync enabled' },
      use_dhcp: { index: 3, default: 1, desc: 'DHCP enabled' },
      static_ip1: { index: 4,  default: 0, desc: 'Static IP byte 1' },
      static_ip2: { index: 5,  default: 0, desc: 'Static IP byte 2' },
      static_ip3: { index: 6,  default: 0, desc: 'Static IP byte 3' },
      static_ip4: { index: 7,  default: 0, desc: 'Static IP byte 4' },
      gateway_ip1: { index: 8,  default: 0, desc: 'Gateway IP byte 1' },
      gateway_ip2: { index: 9,  default: 0, desc: 'Gateway IP byte 2' },
      gateway_ip3: { index: 10, default: 0, desc: 'Gateway IP byte 3' },
      gateway_ip4: { index: 11, default: 0, desc: 'Gateway IP byte 4' },
      httpport_0: { index: 12, default: 144, desc: 'HTTP port low byte (144 + 31<<8 = 8080)' },
      httpport_1: { index: 13, default: 31, desc: 'HTTP port high byte' },
      hw_version: { index: 14, default: HardwareVersion::OSPI_BASE, readonly: true, desc: 'Hardware version' },
      ext_boards: { index: 15, default: 0, desc: 'Number of expansion boards' },
      sequential_retired: { index: 16, default: 1, readonly: true, desc: 'Sequential (retired)' },
      station_delay_time: { index: 17, default: 120, desc: 'Station delay (seconds + 120, so 120 = 0)' },
      master_station: { index: 18, default: 0, desc: 'Master station 1 index (0 = none)' },
      master_on_adj: { index: 19, default: 120, desc: 'Master 1 on adjust (seconds + 120)' },
      master_off_adj: { index: 20, default: 120, desc: 'Master 1 off adjust (seconds + 120)' },
      urs_retired: { index: 21, default: 0, readonly: true, desc: 'URS (retired)' },
      rso_retired: { index: 22, default: 0, readonly: true, desc: 'RSO (retired)' },
      water_percentage: { index: 23, default: 100, desc: 'Water level percentage (0-250)' },
      device_enable: { index: 24, default: 1, desc: 'Device enabled' },
      ignore_password: { index: 25, default: 0, desc: 'Ignore password (demo mode)' },
      device_id: { index: 26, default: 0, desc: 'Device ID' },
      lcd_contrast: { index: 27, default: 150, desc: 'LCD contrast' },
      lcd_backlight: { index: 28, default: 100, desc: 'LCD backlight' },
      lcd_dimming: { index: 29, default: 15, desc: 'LCD dimming' },
      boost_time: { index: 30, default: 80, desc: 'Boost time (ms)' },
      use_weather: { index: 31, default: 0, desc: 'Weather algorithm (0=manual)' },
      ntp_ip1: { index: 32, default: 0, desc: 'NTP server IP byte 1' },
      ntp_ip2: { index: 33, default: 0, desc: 'NTP server IP byte 2' },
      ntp_ip3: { index: 34, default: 0, desc: 'NTP server IP byte 3' },
      ntp_ip4: { index: 35, default: 0, desc: 'NTP server IP byte 4' },
      enable_logging: { index: 36, default: 1, desc: 'Logging enabled' },
      master_station_2: { index: 37, default: 0, desc: 'Master station 2 index (0 = none)' },
      master_on_adj_2: { index: 38, default: 120, desc: 'Master 2 on adjust' },
      master_off_adj_2: { index: 39, default: 120, desc: 'Master 2 off adjust' },
      fw_minor: { index: 40, default: FW_MINOR, readonly: true, desc: 'Firmware minor version' },
      pulse_rate_0: { index: 41, default: 100, desc: 'Flow pulse rate low byte (100x)' },
      pulse_rate_1: { index: 42, default: 0, desc: 'Flow pulse rate high byte' },
      remote_ext_mode: { index: 43, default: 0, desc: 'Remote extension mode' },
      dns_ip1: { index: 44, default: 8, desc: 'DNS server IP byte 1' },
      dns_ip2: { index: 45, default: 8, desc: 'DNS server IP byte 2' },
      dns_ip3: { index: 46, default: 8, desc: 'DNS server IP byte 3' },
      dns_ip4: { index: 47, default: 8, desc: 'DNS server IP byte 4' },
      spe_auto_refresh: { index: 48, default: 0, desc: 'Special station auto refresh' },
      notif_enable: { index: 49, default: 0, desc: 'Notification enable bits' },
      sensor1_type: { index: 50, default: 0, desc: 'Sensor 1 type' },
      sensor1_option: { index: 51, default: 1, desc: 'Sensor 1 option (0=NC, 1=NO)' },
      sensor2_type: { index: 52, default: 0, desc: 'Sensor 2 type' },
      sensor2_option: { index: 53, default: 1, desc: 'Sensor 2 option (0=NC, 1=NO)' },
      sensor1_on_delay: { index: 54, default: 0, desc: 'Sensor 1 on delay (minutes)' },
      sensor1_off_delay: { index: 55, default: 0, desc: 'Sensor 1 off delay (minutes)' },
      sensor2_on_delay: { index: 56, default: 0, desc: 'Sensor 2 on delay (minutes)' },
      sensor2_off_delay: { index: 57, default: 0, desc: 'Sensor 2 off delay (minutes)' },
      subnet_mask1: { index: 58, default: 255, desc: 'Subnet mask byte 1' },
      subnet_mask2: { index: 59, default: 255, desc: 'Subnet mask byte 2' },
      subnet_mask3: { index: 60, default: 255, desc: 'Subnet mask byte 3' },
      subnet_mask4: { index: 61, default: 0, desc: 'Subnet mask byte 4' },
      force_wired: { index: 62, default: 1, desc: 'Force wired connection' },
      latch_on_voltage: { index: 63, default: 0, desc: 'Latch on voltage' },
      latch_off_voltage: { index: 64, default: 0, desc: 'Latch off voltage' },
      notif2_enable: { index: 65, default: 0, desc: 'Notification enable bits 2' },
      i_min_threshold: { index: 66, default: 10, desc: 'Min current threshold (mA/10)' },
      i_max_limit: { index: 67, default: 0, desc: 'Max current limit (mA/10, 0=default)' },
      target_pd_voltage: { index: 68, default: 75, desc: 'Target PD voltage (decivolts)' },
      reserve_7: { index: 69, default: 0, desc: 'Reserved' },
      reserve_8: { index: 70, default: 0, desc: 'Reserved' },
      wifi_mode: { index: 71, default: 0xA9, readonly: true, desc: 'WiFi mode' },
      reset: { index: 72, default: 0, readonly: true, desc: 'Reset flag' }
    }.freeze

    attr_reader :values, :file_path

    def initialize(file_path: nil)
      @file_path = file_path
      @values = {}
      reset_to_defaults
    end

    # Reset all options to defaults
    def reset_to_defaults
      DEFINITIONS.each do |name, meta|
        @values[name] = meta[:default]
      end
    end

    # Get option value by name
    def [](name)
      name = name.to_sym
      raise ArgumentError, "Unknown option: #{name}" unless DEFINITIONS.key?(name)

      @values[name]
    end

    # Set option value by name
    def []=(name, value)
      name = name.to_sym
      meta = DEFINITIONS[name]
      raise ArgumentError, "Unknown option: #{name}" unless meta
      raise ArgumentError, "Option #{name} is read-only" if meta[:readonly]

      @values[name] = value.to_i & 0xFF # Clamp to byte
    end

    # Get option by index (for API compatibility)
    def get_by_index(index)
      name = index_to_name(index)
      @values[name]
    end

    # Set option by index (for API compatibility)
    def set_by_index(index, value)
      name = index_to_name(index)
      meta = DEFINITIONS[name]
      return if meta[:readonly]

      @values[name] = value.to_i & 0xFF
    end

    # Load from YAML file
    def load
      return unless @file_path && File.exist?(@file_path)

      data = YAML.load_file(@file_path, permitted_classes: [Symbol])
      data.each do |key, value|
        name = key.to_sym
        next unless DEFINITIONS.key?(name)
        next if DEFINITIONS[name][:readonly]

        @values[name] = value.to_i & 0xFF
      end
    end

    # Save to YAML file
    def save
      return unless @file_path

      # Only save non-readonly, non-default values
      data = {}
      DEFINITIONS.each do |name, meta|
        next if meta[:readonly]

        data[name.to_s] = @values[name]
      end

      File.write(@file_path, data.to_yaml)
    end

    # Convert to hash for JSON API
    def to_h
      @values.dup
    end

    # HTTP port (combines two bytes)
    def http_port
      (@values[:httpport_1] << 8) + @values[:httpport_0]
    end

    def http_port=(port)
      @values[:httpport_0] = port & 0xFF
      @values[:httpport_1] = (port >> 8) & 0xFF
    end

    # Timezone in hours (converts from encoded format)
    def timezone_hours
      (@values[:timezone] - 48) / 4.0
    end

    def timezone_hours=(hours)
      @values[:timezone] = ((hours * 4) + 48).to_i
    end

    # Station delay in seconds (converts from encoded format)
    def station_delay_seconds
      @values[:station_delay_time] - 120
    end

    def station_delay_seconds=(seconds)
      @values[:station_delay_time] = seconds + 120
    end

    # Number of boards (main + expansion)
    def num_boards
      1 + @values[:ext_boards]
    end

    # Number of stations
    def num_stations
      num_boards * 8
    end

    private

    def index_to_name(index)
      DEFINITIONS.each do |name, meta|
        return name if meta[:index] == index
      end
      raise ArgumentError, "Unknown option index: #{index}"
    end
  end

  # String options - corresponds to sopts[] in C++ firmware
  class StringOptions
    include Constants

    DEFINITIONS = {
      password: { index: 0, default: Defaults::PASSWORD, desc: 'MD5 password hash' },
      location: { index: 1, default: Defaults::LOCATION, desc: 'Location (lat,lon)' },
      javascript_url: { index: 2, default: Defaults::JAVASCRIPT_URL, desc: 'JavaScript URL' },
      weather_url: { index: 3, default: Defaults::WEATHER_URL, desc: 'Weather server URL' },
      weather_opts: { index: 4, default: '', desc: 'Weather options JSON' },
      ifttt_key: { index: 5, default: '', desc: 'IFTTT webhook key' },
      sta_ssid: { index: 6, default: '', desc: 'WiFi SSID' },
      sta_pass: { index: 7, default: '', desc: 'WiFi password' },
      mqtt_opts: { index: 8, default: '', desc: 'MQTT options JSON' },
      otc_opts: { index: 9, default: '', desc: 'OTC options JSON' },
      device_name: { index: 10, default: Defaults::DEVICE_NAME, desc: 'Device name' },
      sta_bssid_chl: { index: 11, default: '', desc: 'WiFi BSSID/channel' },
      email_opts: { index: 12, default: '', desc: 'Email options JSON' }
    }.freeze

    attr_reader :values, :file_path

    def initialize(file_path: nil)
      @file_path = file_path
      @values = {}
      reset_to_defaults
    end

    def reset_to_defaults
      DEFINITIONS.each do |name, meta|
        @values[name] = meta[:default]
      end
    end

    def [](name)
      name = name.to_sym
      raise ArgumentError, "Unknown option: #{name}" unless DEFINITIONS.key?(name)

      @values[name]
    end

    def []=(name, value)
      name = name.to_sym
      raise ArgumentError, "Unknown option: #{name}" unless DEFINITIONS.key?(name)

      @values[name] = value.to_s[0, Constants::MAX_SOPTS_SIZE]
    end

    def get_by_index(index)
      name = index_to_name(index)
      @values[name]
    end

    def set_by_index(index, value)
      name = index_to_name(index)
      @values[name] = value.to_s[0, Constants::MAX_SOPTS_SIZE]
    end

    def load
      return unless @file_path && File.exist?(@file_path)

      data = YAML.load_file(@file_path, permitted_classes: [Symbol])
      data.each do |key, value|
        name = key.to_sym
        next unless DEFINITIONS.key?(name)

        @values[name] = value.to_s
      end
    end

    def save
      return unless @file_path

      data = {}
      DEFINITIONS.each_key do |name|
        data[name.to_s] = @values[name]
      end

      File.write(@file_path, data.to_yaml)
    end

    def to_h
      @values.dup
    end

    # Verify password (MD5 hash comparison)
    def verify_password(pw_hash)
      pw_hash == @values[:password]
    end

    private

    def index_to_name(index)
      DEFINITIONS.each do |name, meta|
        return name if meta[:index] == index
      end
      raise ArgumentError, "Unknown option index: #{index}"
    end
  end
end
