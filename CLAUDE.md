# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Ruby reimplementation of the OpenSprinkler irrigation controller firmware for Raspberry Pi (OSPi) hardware. Reports as firmware 2.2.1.4 for compatibility with the official UI at https://ui.opensprinkler.com. All config is YAML-based (no binary files).

## Commands

```bash
bundle exec rspec                    # run all tests
bundle exec rspec spec/unit/foo_spec.rb  # run single test file
bundle exec rubocop                  # lint
bundle install                       # install deps (add --with=pi for GPIO)

# run locally in mock mode
./bin/opensprinkler -H mock -d ./data -p 8080
```

## Architecture

**Tick-based main loop** (`bin/opensprinkler`): Controller.tick() runs every 100ms via Puma. Not event-driven.

**Layers:**
- **Hardware** (`hardware/`) — GPIO abstraction with three backends: real lgpio (Pi), DemoGPIO (simulated), MockGPIO (tests). Shift register (`74HC595`) drives valve stations.
- **Scheduling** (`scheduling/`) — Program matching, runtime queue with station sequencing. Program types: weekly, single_run, monthly, interval.
- **Stations** (`stations/`) — Zone models with master station binding. Up to 192+ zones via expansion boards.
- **Options** (`options.rb`) — `IntegerOptions` (73 indexed, byte-clamped to `& 0xFF`) and `StringOptions` (13 named). Some are read-only. Mirrors C++ firmware byte arrays.
- **Web API** (`web/app.rb`) — Roda with JSON plugin. All endpoints require `pw` param (MD5 hash, default password: `opendoor`). Read endpoints (`/jc`, `/jo`, `/jp`, `/js`, `/jn`, `/je`, `/jl`, `/ja`) and write endpoints (`/cv`, `/co`, `/cp`, `/dp`, `/cs`, `/cm`, `/cr`, `/pq`, `/dl`).
- **Logging** — `LogStore` writes JSON logs by date. Optional `InfluxDBClient` for valve state telemetry.

**Namespace:** `OpenSprinkler::*`. Constants mixed in via `include Constants`.

**Persistence:** YAML files in data dir (default `/var/lib/opensprinkler/`): `options.yml`, `stations.yml`, `programs.yml`, `influxdb.yml`. Logs in `logs/YYYYMMDD.json`. No auto-save; explicit `save` calls.

**Key coordination file:** `controller.rb` — holds all mutable state, orchestrates sensors, rain delay, scheduling, queue processing, and master station timing.

## Testing Patterns

- RSpec 3.13 with Rack::Test for API specs
- MockGPIO with action log for hardware verification
- Time injection via method parameters (`current_time = Time.now`)
- Temporary directories with `after` cleanup for file I/O tests
- Tests in `spec/unit/`; `spec/integration/` reserved but empty

## Style

RuboCop with relaxed metrics: line length 320, method length 100, class length 600, ABC size 85. Ruby 3.2 target. See `.rubocop.yml` for full config.
