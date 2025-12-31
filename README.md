# OpenSprinkler Ruby

A Ruby implementation of the OpenSprinkler irrigation controller firmware, designed for Raspberry Pi (OSPi) hardware.

## Overview

This project reimplements the [OpenSprinkler firmware](https://github.com/OpenSprinkler/OpenSprinkler-Firmware) in Ruby, providing:

- Full API compatibility with the official OpenSprinkler UI (https://ui.opensprinkler.com)
- Support for OSPi (OpenSprinkler Pi) hardware via GPIO
- Program scheduling with weather adjustment
- Rain delay and sensor support
- InfluxDB integration for logging
- YAML-based configuration (no binary files)

## Requirements

- Ruby 3.2+
- Raspberry Pi with OSPi board (for production)
- Bundler

## Installation

```bash
git clone https://github.com/yourusername/opensprinkler-ruby.git
cd opensprinkler-ruby
bundle install

# For Raspberry Pi with GPIO support:
bundle install --with=pi
```

## Quick Start

### Development/Demo Mode

Run without hardware (mock GPIO):

```bash
./bin/opensprinkler -H mock -d ./data -p 8080
```

Then open https://ui.opensprinkler.com and connect to `http://localhost:8080`.

### Production (Raspberry Pi)

```bash
sudo ./bin/opensprinkler -H ospi -d /var/lib/opensprinkler -p 8080
```

## Command Line Options

```
Usage: opensprinkler [options]
    -p, --port PORT          HTTP port (default: 8080)
    -d, --data-dir DIR       Data directory (default: /var/lib/opensprinkler)
    -c, --config FILE        Configuration file
    -H, --hardware TYPE      Hardware type (auto, ospi, demo, mock)
    -f, --foreground         Run in foreground (don't daemonize)
    -v, --version            Show version
    -h, --help               Show this help
```

### Hardware Types

| Type | Description |
|------|-------------|
| `auto` | Auto-detect (OSPi if GPIO available, otherwise mock) |
| `ospi` | OpenSprinkler Pi hardware |
| `demo` | Demo mode with simulated stations |
| `mock` | Mock hardware for testing |

## Migrating from OpenSprinkler Firmware

If you're migrating from the C++ OpenSprinkler firmware, use the migration tool to convert your binary data files to YAML format.

### Locate Your Data Files

The C++ firmware stores data in binary `.dat` files, typically in:
- Raspberry Pi: `/home/pi/OpenSprinkler/data/` or `/var/lib/opensprinkler/`
- The files are: `iopts.dat`, `sopts.dat`, `stns.dat`, `prog.dat`, `nvcon.dat`

### Run the Migration

```bash
# Stop the old firmware first
sudo systemctl stop opensprinkler

# Run migration
./bin/migrate_data /path/to/old/data ./data

# Example:
./bin/migrate_data /home/pi/OpenSprinkler/data ./data
```

### Migration Output

The tool converts:

| Source File | Destination | Contents |
|-------------|-------------|----------|
| `iopts.dat` | `iopts.yml` | Integer options (water level, timezone, etc.) |
| `sopts.dat` | `sopts.yml` | String options (location, weather key, etc.) |
| `stns.dat` | `stations.yml` | Station names and attributes |
| `prog.dat` | `programs.yml` | Watering programs (partial - see note) |
| `nvcon.dat` | `nvdata.yml` | Runtime data (sunrise/sunset times) |

**Note:** Program migration is partial. Complex programs may need manual setup via the UI after migration.

### Post-Migration

1. Review the generated YAML files in `./data/`
2. Start the Ruby version: `./bin/opensprinkler -d ./data`
3. Verify settings in the UI
4. Re-create any programs that didn't migrate correctly

## systemd Service

Install as a system service:

```bash
# Create user
sudo useradd -r -s /bin/false opensprinkler
sudo usermod -aG gpio opensprinkler

# Create directories
sudo mkdir -p /opt/opensprinkler /var/lib/opensprinkler
sudo cp -r . /opt/opensprinkler/
sudo chown -R opensprinkler:gpio /opt/opensprinkler /var/lib/opensprinkler

# Install service
sudo cp systemd/opensprinkler.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable opensprinkler
sudo systemctl start opensprinkler

# Check status
sudo systemctl status opensprinkler
sudo journalctl -u opensprinkler -f
```

## Configuration Files

All configuration is stored in YAML format in the data directory:

```
/var/lib/opensprinkler/
├── options.yml      # Controller options
├── stations.yml     # Station configuration
├── programs.yml     # Watering programs
├── influxdb.yml     # InfluxDB config (optional)
└── logs/            # Watering logs by date
    ├── 20250101.json
    └── ...
```

### InfluxDB Integration

To log valve states to InfluxDB, create `influxdb.yml`:

```yaml
enabled: true
host: 192.168.1.100
port: 8086
database: opensprinkler
```

## API Endpoints

The server implements the full OpenSprinkler HTTP API:

### Read Endpoints
- `GET /jc` - Controller status
- `GET /jo` - Options
- `GET /jp` - Programs
- `GET /js` - Station status
- `GET /jn` - Station names
- `GET /je` - Station special data
- `GET /jl` - Logs
- `GET /ja` - All data combined

### Write Endpoints
- `GET /cv` - Change values (enable, rain delay, etc.)
- `GET /co` - Change options
- `GET /cp` - Create/modify program
- `GET /dp` - Delete program
- `GET /cs` - Change station settings
- `GET /cm` - Manual station control
- `GET /cr` - Run once program
- `GET /pq` - Pause/resume queue
- `GET /dl` - Delete logs

All endpoints require the `pw` parameter (MD5 hash of password, default: `opendoor` = `a6d82bced638de3def1e9bbb4983225c`).

## Development

### Running Tests

```bash
bundle exec rspec
```

### Code Style

```bash
bundle exec rubocop
```

### Project Structure

```
lib/opensprinkler/
├── controller.rb           # Main controller logic
├── options.rb              # Integer/string options
├── constants.rb            # Protocol constants
├── log_store.rb            # File-based logging
├── influxdb_client.rb      # InfluxDB integration
├── hardware/
│   ├── gpio.rb             # GPIO abstraction
│   ├── shift_register.rb   # 74HC595 control
│   └── sensors.rb          # Rain/flow sensors
├── stations/
│   ├── station.rb          # Station model
│   └── station_store.rb    # Station collection
├── scheduling/
│   ├── program.rb          # Program model
│   ├── program_store.rb    # Program collection
│   ├── scheduler.rb        # Schedule execution
│   └── runtime_queue.rb    # Active watering queue
└── web/
    └── app.rb              # Roda HTTP API
```

## Compatibility

- **Firmware Version:** Reports as 2.2.1.4 (compatible with official UI)
- **Hardware:** OSPi (OpenSprinkler Pi) with 74HC595 shift registers
- **UI:** Works with https://ui.opensprinkler.com

## License

MIT License - See LICENSE file for details.

## Acknowledgments

Based on the [OpenSprinkler Firmware](https://github.com/OpenSprinkler/OpenSprinkler-Firmware) by Ray Wang.
