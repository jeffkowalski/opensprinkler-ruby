# frozen_string_literal: true

# OpenSprinkler Constants
# Ported from defines.h in C++ firmware
# https://github.com/OpenSprinkler/OpenSprinkler-Firmware

module OpenSprinkler
  module Constants
    # Firmware version
    FW_VERSION = 221 # 2.2.1
    FW_MINOR = 4

    # Hardware version bases
    module HardwareVersion
      OS_BASE   = 0x00  # OpenSprinkler
      OSPI_BASE = 0x40  # OpenSprinkler Pi
      SIM_BASE  = 0xC0  # Simulation
    end

    # Hardware types
    module HardwareType
      AC      = 0xAC  # 24VAC with triacs
      DC      = 0xDC  # DC powered with MOSFETs
      LATCH   = 0x1A  # DC latching solenoids
      UNKNOWN = 0xFF
    end

    # Station types
    module StationType
      STANDARD   = 0x00  # Standard solenoid
      RF         = 0x01  # Radio frequency
      REMOTE_IP  = 0x02  # Remote OpenSprinkler by IP
      GPIO       = 0x03  # Direct GPIO
      HTTP       = 0x04  # HTTP station
      HTTPS      = 0x05  # HTTPS station
      REMOTE_OTC = 0x06  # Remote via OpenThings Cloud
      OTHER      = 0xFF
    end

    # Sensor types
    module SensorType
      NONE    = 0x00
      RAIN    = 0x01  # Rain sensor
      FLOW    = 0x02  # Flow sensor
      SOIL    = 0x03  # Soil moisture
      PSWITCH = 0xF0  # Program switch
      OTHER   = 0xFF
    end

    # Notification flags
    module Notify
      PROGRAM_SCHED  = 0x0001
      SENSOR1        = 0x0002
      FLOWSENSOR     = 0x0004
      WEATHER_UPDATE = 0x0008
      REBOOT         = 0x0010
      STATION_OFF    = 0x0020
      SENSOR2        = 0x0040
      RAINDELAY      = 0x0080
      STATION_ON     = 0x0100
      FLOW_ALERT     = 0x0200
      CURR_ALERT     = 0x0400
    end

    # Queue insertion modes
    module QueueOption
      APPEND       = 0
      INSERT_FRONT = 1
      REPLACE      = 2
    end

    # Current alert types
    module CurrentAlert
      UNDER        = 0  # Undercurrent when running
      OVER_STATION = 1  # Overcurrent on station start
      OVER_SYSTEM  = 2  # Overcurrent while running
    end

    # HTTP request results
    module HttpResult
      SUCCESS = 0
      NOT_RECEIVED  = -1
      CONNECT_ERR   = -2
      TIMEOUT       = -3
      EMPTY_RETURN  = -4
    end

    # Reboot causes
    module RebootCause
      NONE         = 0
      RESET        = 1
      BUTTON       = 2
      RSTAP        = 3
      TIMER        = 4
      WEB          = 5
      WIFIDONE     = 6
      FWUPDATE     = 7
      WEATHER_FAIL = 8
      NETWORK_FAIL = 9
      NTP          = 10
      PROGRAM      = 11
      POWERON      = 99
    end

    # Weather adjustment methods
    module WeatherMethod
      MANUAL        = 0
      ZIMMERMAN     = 1
      AUTORAINDELAY = 2
      ETO           = 3
      MONTHLY       = 4
    end

    # Master zones
    module Master
      ZONE_1 = 0
      ZONE_2 = 1
      NUM_ZONES = 2
    end

    # Sequential groups
    NUM_SEQ_GROUPS    = 4
    PARALLEL_GROUP_ID = 255

    # Flat constants for commonly used sensor types
    SENSOR_TYPE_NONE  = SensorType::NONE
    SENSOR_TYPE_RAIN  = SensorType::RAIN
    SENSOR_TYPE_FLOW  = SensorType::FLOW
    SENSOR_TYPE_SOIL  = SensorType::SOIL

    # Log data types
    module LogData
      STATION    = 0x00
      SENSOR1    = 0x01
      RAINDELAY  = 0x02
      WATERLEVEL = 0x03
      FLOWSENSE  = 0x04
      SENSOR2    = 0x05
      CURRENT    = 0x80
    end

    # Zone/board limits (Linux allows more than Arduino)
    MAX_EXT_BOARDS   = 24
    MAX_NUM_BOARDS   = 1 + MAX_EXT_BOARDS
    MAX_NUM_STATIONS = MAX_NUM_BOARDS * 8
    STATION_NAME_SIZE = 32
    MAX_SOPTS_SIZE   = 320
    TMP_BUFFER_SIZE  = 320
    STATION_SPECIAL_DATA_SIZE = TMP_BUFFER_SIZE - STATION_NAME_SIZE - 12

    # Flow sensor
    FLOWCOUNT_RT_WINDOW = 1000

    # OSPi GPIO pin assignments (BCM numbering)
    module Pin
      SR_LATCH    = 22  # Shift register latch
      SR_DATA     = 27  # Shift register data
      SR_DATA_ALT = 21  # Alt data pin (RPi 1 rev 1)
      SR_CLOCK    = 4   # Shift register clock
      SR_OE       = 17  # Shift register output enable

      SENSOR1     = 14  # Sensor 1 input
      SENSOR2     = 23  # Sensor 2 input
      RFTX        = 15  # RF transmitter

      BUTTON_1    = 24
      BUTTON_2    = 18
      BUTTON_3    = 10

      # Free GPIO pins available for GPIO stations
      FREE_LIST = [5, 6, 7, 8, 9, 11, 12, 13, 16, 19, 20, 21, 23, 25, 26].freeze
    end

    # Flat constants for commonly used pins
    PIN_SR_LATCH = Pin::SR_LATCH
    PIN_SR_DATA  = Pin::SR_DATA
    PIN_SR_CLOCK = Pin::SR_CLOCK
    PIN_SR_OE    = Pin::SR_OE
    PIN_SENSOR1  = Pin::SENSOR1
    PIN_SENSOR2  = Pin::SENSOR2

    # Integer options indices (matching IOPT_* enum)
    module IntOption
      FW_VERSION         = 0   # ro
      TIMEZONE           = 1
      USE_NTP            = 2
      USE_DHCP           = 3
      STATIC_IP1         = 4
      STATIC_IP2         = 5
      STATIC_IP3         = 6
      STATIC_IP4         = 7
      GATEWAY_IP1        = 8
      GATEWAY_IP2        = 9
      GATEWAY_IP3        = 10
      GATEWAY_IP4        = 11
      HTTPPORT_0         = 12
      HTTPPORT_1         = 13
      HW_VERSION         = 14  # ro
      EXT_BOARDS         = 15
      SEQUENTIAL_RETIRED = 16  # ro
      STATION_DELAY_TIME = 17
      MASTER_STATION     = 18
      MASTER_ON_ADJ      = 19
      MASTER_OFF_ADJ     = 20
      URS_RETIRED        = 21  # ro
      RSO_RETIRED        = 22  # ro
      WATER_PERCENTAGE   = 23
      DEVICE_ENABLE      = 24
      IGNORE_PASSWORD    = 25
      DEVICE_ID          = 26
      LCD_CONTRAST       = 27
      LCD_BACKLIGHT      = 28
      LCD_DIMMING        = 29
      BOOST_TIME         = 30
      USE_WEATHER        = 31
      NTP_IP1            = 32
      NTP_IP2            = 33
      NTP_IP3            = 34
      NTP_IP4            = 35
      ENABLE_LOGGING     = 36
      MASTER_STATION_2   = 37
      MASTER_ON_ADJ_2    = 38
      MASTER_OFF_ADJ_2   = 39
      FW_MINOR           = 40  # ro
      PULSE_RATE_0       = 41
      PULSE_RATE_1       = 42
      REMOTE_EXT_MODE    = 43
      DNS_IP1            = 44
      DNS_IP2            = 45
      DNS_IP3            = 46
      DNS_IP4            = 47
      SPE_AUTO_REFRESH   = 48
      NOTIF_ENABLE       = 49
      SENSOR1_TYPE       = 50
      SENSOR1_OPTION     = 51
      SENSOR2_TYPE       = 52
      SENSOR2_OPTION     = 53
      SENSOR1_ON_DELAY   = 54
      SENSOR1_OFF_DELAY  = 55
      SENSOR2_ON_DELAY   = 56
      SENSOR2_OFF_DELAY  = 57
      SUBNET_MASK1       = 58
      SUBNET_MASK2       = 59
      SUBNET_MASK3       = 60
      SUBNET_MASK4       = 61
      FORCE_WIRED        = 62
      LATCH_ON_VOLTAGE   = 63
      LATCH_OFF_VOLTAGE  = 64
      NOTIF2_ENABLE      = 65
      I_MIN_THRESHOLD    = 66
      I_MAX_LIMIT        = 67
      TARGET_PD_VOLTAGE  = 68
      RESERVE_7          = 69
      RESERVE_8          = 70
      WIFI_MODE          = 71  # ro
      RESET              = 72  # ro
      NUM_OPTS           = 73
    end

    # String options indices (matching SOPT_* enum)
    module StringOption
      PASSWORD       = 0
      LOCATION       = 1
      JAVASCRIPTURL  = 2
      WEATHERURL     = 3
      WEATHER_OPTS   = 4
      IFTTT_KEY      = 5
      STA_SSID       = 6
      STA_PASS       = 7
      MQTT_OPTS      = 8
      OTC_OPTS       = 9
      DEVICE_NAME    = 10
      STA_BSSID_CHL  = 11
      EMAIL_OPTS     = 12
      NUM_OPTS       = 13
    end

    # Default values
    module Defaults
      PASSWORD       = 'a6d82bced638de3def1e9bbb4983225c' # MD5 of 'opendoor'
      LOCATION       = '42.36,-71.06' # Boston, MA
      JAVASCRIPT_URL = 'https://ui.opensprinkler.com/js'
      WEATHER_URL    = 'weather.opensprinkler.com'
      IFTTT_URL      = 'maker.ifttt.com'
      OTC_SERVER_DEV = 'ws.cloud.openthings.io'
      OTC_PORT_DEV   = 80
      OTC_SERVER_APP = 'cloud.openthings.io'
      OTC_PORT_APP   = 443
      OTC_TOKEN_LENGTH = 32
      DEVICE_NAME = 'My OpenSprinkler'

      UNDERCURRENT_THRESHOLD = 100   # mA
      OVERCURRENT_LIMIT      = 1200  # mA
      OVERCURRENT_INRUSH     = 600   # mA extra margin
      OVERCURRENT_DC_EXTRA   = 1200  # mA extra for DC
      LATCH_BOOST_VOLTAGE    = 9     # volts
      TARGET_PD_VOLTAGE      = 75    # decivolts (7.5V)
    end

    # HTTP API result codes (from opensprinkler_server.cpp)
    module ApiResult
      OK             = 0x00
      SUCCESS        = 0x01
      UNAUTHORIZED   = 0x02
      MISMATCH       = 0x03
      DATA_MISSING   = 0x10
      DATA_OUTOFBOUND = 0x11
      DATA_FORMATERROR = 0x12
      RFCODE_ERROR   = 0x13
      PAGE_NOT_FOUND = 0x20
      NOT_PERMITTED  = 0x30
      UPLOAD_FAILED  = 0x40
      REDIRECT_HOME  = 0xFF
    end
  end
end
