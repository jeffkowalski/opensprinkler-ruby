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

- Ruby 3.1+ (the OSPi target runs Ruby 4.0.1 via rbenv — see [Installing Ruby via rbenv](#installing-ruby-via-rbenv-raspberry-pi))
- Raspberry Pi with OSPi board (for production)
- Bundler
- `liblgpio` system library on the Pi (for the `lgpio` gem's native extension)

## Installation

```bash
git clone https://github.com/jeffkowalski/opensprinkler-ruby.git
cd opensprinkler-ruby
bundle install

# For Raspberry Pi with GPIO support:
bundle install --with=pi
```

### Installing Ruby via rbenv (Raspberry Pi)

The OSPi target does not ship a new enough Ruby, so build it with [rbenv](https://github.com/rbenv/rbenv) + [ruby-build](https://github.com/rbenv/ruby-build). **The board is RAM-constrained (see [Target Device & Limitations](#target-device--limitations)), so compile single-threaded** — a parallel build exhausts memory and hard-crashes the Pi:

```bash
# rbenv + ruby-build (one-time)
git clone https://github.com/rbenv/rbenv.git ~/.rbenv
git clone https://github.com/rbenv/ruby-build.git ~/.rbenv/plugins/ruby-build
# add to your shell profile (~/.bashrc):
#   export PATH="$HOME/.rbenv/bin:$HOME/.rbenv/shims:$PATH"
#   eval "$(rbenv init - bash)"

# Build Ruby with a single make job so it doesn't OOM the Pi (this is slow):
MAKE_OPTS="-j1" rbenv install 4.0.1
rbenv global 4.0.1
ruby -v   # => ruby 4.0.1
```

> rbenv is **not** on the PATH of non-login/non-interactive shells (systemd units, `ssh host 'cmd'`). Load it explicitly when needed:
> `export PATH="$HOME/.rbenv/bin:$HOME/.rbenv/shims:$PATH"; eval "$(rbenv init - bash)"`.
> The provided systemd unit sets `RBENV_ROOT`/`PATH` itself.

### Installing gems on the OSPi

`liblgpio` must be present (it is if the C++ firmware ran — that firmware links the same `lg` library). Compile native extensions single-threaded so the build can't OOM the board:

```bash
bundle config set --local with pi      # include the lgpio gem
bundle config set --local jobs 1       # one gem at a time
MAKEFLAGS="-j1" bundle install         # one make job per gem
```

**If a build is interrupted (e.g. the Pi crashes mid-compile),** the gem store can be left with truncated `.gem`/`.gemspec` files, and a later `bundle install` fails with `Gem::Package::FormatError: package metadata is missing` or warns `... isn't a Gem::Specification (NilClass instead)`. Recover by clearing the (re-downloadable) cache and the zero-byte spec stubs, then reinstalling:

```bash
GEMDIR="$(ruby -e 'print Gem.dir')"
rm -f "$GEMDIR"/cache/*.gem
find "$GEMDIR"/specifications -name '*.gemspec' -size -1k -delete
MAKEFLAGS="-j1" bundle install
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
    -V, --verbose            Verbose request logging
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

## Target Device & Limitations

The reference deployment runs on a **Raspberry Pi Zero 2 W** driving the OSPi controller board. It is intentionally modest:

| Property | Value |
|----------|-------|
| SoC | Broadcom BCM2837 (quad-core Cortex-A53, ARMv8) |
| RAM | 512 MB (no swap by default) |
| GPIO chip | `/dev/gpiochip0` (the `bcm2712`/Pi 5 `gpiochip4` path is auto-detected but not used here) |
| Network | Wi-Fi only (2.4 GHz) |
| OS | Raspberry Pi OS (Debian Bookworm), 64-bit |

Practical consequences:

- **Low RAM** — compiling Ruby or native gems with default parallelism exhausts memory and **hard-crashes/reboots the board**. Always build single-threaded (`MAKE_OPTS="-j1"`, `MAKEFLAGS="-j1"`, `bundle config set --local jobs 1`); native builds take minutes per gem.
- **Wi-Fi only** — it can briefly drop off the network under heavy load or after a crash, then self-recovers in a few minutes. "Reachable by ping" does not mean "shell is responsive yet" while it is still recovering.
- **GPIO access** — `/dev/gpiochip0` is `root:gpio`, mode `0660`. A non-root service user must be in the `gpio` group; the logind ACL that grants interactive SSH sessions does **not** apply to background services, so group membership is required.

## Cutover from the C++ firmware

The C++ OpenSprinkler firmware and this Ruby firmware **cannot run at the same time** — they claim the same GPIO lines (shift-register pins 4/17/22/27) and bind the same port (8080). Cut over deliberately.

### 1. Back up configuration (while the old firmware still runs)

There is no binary-to-YAML file converter; migrate via the UI's JSON backup:

1. Open https://ui.opensprinkler.com and connect to the running controller (`http://<pi>:8080`).
2. **Edit Options → Backup** to download a backup JSON file.

### 2. Stop and disable the old firmware

On this device the C++ firmware runs as the systemd unit **`OpenSprinkler.service`** (capitalized — not `opensprinkler`):

```bash
sudo systemctl stop OpenSprinkler
sudo systemctl disable OpenSprinkler            # don't let it restart on boot
gpioinfo | grep -E 'line +(4|17|22|27):'        # lines should now read "unused"
```

### 3. Start the Ruby firmware and restore data

Verify it directly first (foreground):

```bash
bundle exec ruby bin/opensprinkler -H ospi -d data -p 8080
```

…or install it as a service (see [systemd Service](#systemd-service)). Then reopen the UI, connect to the new server, and use **Edit Options → Restore** to upload the backup JSON. Confirm options, stations, and programs are correct.

### 4. Rollback

The old firmware directory is left in place, so reverting is just swapping the services back:

```bash
sudo systemctl disable --now opensprinkler-home   # stop AND prevent restart on boot
sudo systemctl enable --now OpenSprinkler
```

> Use `disable --now`, not just `stop`: with `Restart=always` and the unit enabled, a plain
> `stop` would let it restart on the next boot. Disabling breaks any boot-time restart loop.

## Deployment status & known issues

**As of 2026-06-18 the production OSPi runs the C++ firmware (`OpenSprinkler.service`).** The Ruby
firmware is staged and validated but **not yet in production** due to an unresolved stability issue.

Cutover pre-staging works end to end with zero downtime: backups, exporting the C++ config, importing
it into a mock Ruby instance (`-H mock -p 8081`), and verifying config parity (station names,
attributes, programs, options) and the unit suite. The Ruby firmware also runs fine **in mock mode**.

The blocker: when the `opensprinkler-home` service starts with **real hardware** (`-H ospi`, port
8080) on the Pi Zero 2 W, the board has gone **unreachable/rebooted** — observed twice. Root cause is
**not yet determined**. A user-space service should not reboot Linux, so the leading suspects are
**undervoltage** (a current spike at Ruby/Puma startup browning out a marginal supply) or independent
board instability (SD/thermal). Note the board also rebooted several times unrelated to the firmware
that day, and a kernel update landed (`6.12.75`→`6.12.93`).

Before retrying the cutover, diagnose on the box (all read-only):

```bash
journalctl -b -1 --no-pager | tail -50          # logs from the boot that crashed
dmesg | grep -i "under-voltage\|oom\|throttl"    # power/memory/thermal events
vcgencmd get_throttled                            # 0x0 = healthy; bit 0/16 = under-voltage now/since boot
```

Rollback is fast and proven (see [Rollback](#4-rollback)); the C++ `*.dat` state is never modified.

## systemd Service

The repo ships `systemd/opensprinkler-home.service`, configured for the reference deployment: it runs as user **`jeff`** (a member of the `gpio` group) from `/home/jeff/opensprinkler-ruby`, invokes the rbenv Ruby via its shims (setting `RBENV_ROOT`/`PATH`), and serves on port 8080. It declares `Conflicts=OpenSprinkler.service`, so starting it makes systemd stop the C++ firmware automatically.

```bash
sudo cp systemd/opensprinkler-home.service /etc/systemd/system/
sudo systemctl daemon-reload

# stop/disable the old C++ firmware first (see Cutover)
sudo systemctl disable --now OpenSprinkler

sudo systemctl enable --now opensprinkler-home
sudo systemctl status opensprinkler-home
sudo journalctl -u opensprinkler-home -f
```

Adjust `User=`, `WorkingDirectory=`, `RBENV_ROOT=`, the `PATH=` shims, and the data dir (`-d data`, relative to `WorkingDirectory`) in the unit if your paths differ. The unit runs as a non-root user and depends on that user being in the `gpio` group (see [Target Device & Limitations](#target-device--limitations)).

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

## Upstream Ancestry

Based on [jeffkowalski/OpenSprinkler-Firmware](https://github.com/jeffkowalski/OpenSprinkler-Firmware) commit [`b427d3d`](https://github.com/jeffkowalski/OpenSprinkler-Firmware/commit/b427d3d) (2025-12-30, "Merge upstream/master, preserve InfluxDB"), which tracks [OpenSprinkler/OpenSprinkler-Firmware](https://github.com/OpenSprinkler/OpenSprinkler-Firmware) commit [`05ad383`](https://github.com/OpenSprinkler/OpenSprinkler-Firmware/commit/05ad383) (2025-11-15, PR #381, firmware 2.2.1.4) plus InfluxDB additions.

## Acknowledgments

Based on the [OpenSprinkler Firmware](https://github.com/OpenSprinkler/OpenSprinkler-Firmware) by Ray Wang.
