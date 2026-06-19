# Cutover Runbook: C++ → Ruby OpenSprinkler

Migrating the live OSPi controller from the C++ OpenSprinkler firmware to this Ruby
implementation, preserving all state and with a tested rollback path.

- **Host:** `jeff@192.168.7.200` (Raspberry Pi Zero 2 W, passwordless sudo)
- **Conflict:** both firmwares bind port 8080 and claim GPIO lines 4/17/22/27 — only one runs at a time
- **C++ service:** `OpenSprinkler.service` (runs as root from `/home/jeff/OpenSprinkler-Firmware`)
- **Ruby service:** `opensprinkler-home.service` (runs as `jeff` from `/home/jeff/opensprinkler-ruby`; `Conflicts=OpenSprinkler.service`)

## Guiding principles

- **Nothing destructive is deleted.** C++ state and the Ruby `data/` dir are backed up before any
  change; rollback is just swapping the services back.
- **Minimize downtime.** The import is pre-staged and validated in *mock* mode (port 8081) while the
  C++ firmware keeps watering. The actual window is only stop-C → start-Ruby → verify.
- **Evidence before claims.** Every phase has a checkpoint; live config is diffed before/after.

## Decisions to confirm before starting

1. **Window timing** — pick a slot with no program about to start (list upcoming start times from
   `/jp` first). Avoid running mid-cycle.
2. **Valve-actuation test** — real single-zone on/off test (opens a valve; confirm water-supply
   state) vs. *safe-only* (no valve energized).
3. **Password** — the default (`opendoor` → `a6d82bced638de3def1e9bbb4983225c`) currently works on
   the live server; confirm it has not been changed.

Reference facts (verified): controller is enabled with 4 expansion boards (32 stations); the Ruby
`data/` on the Pi holds stale March config, so a fresh export→import is genuinely required; the
C++ state lives in root-owned binaries `iopts.dat`, `sopts.dat`, `stns.dat`, `prog.dat`,
`nvcon.dat`, `done.dat`.

## Tools

The validation steps below use [`jq`](https://jqlang.github.io/jq/) to diff JSON config. It is a
great helper and not installed by default — add it on the controller (one-time):

```bash
sudo apt-get update && sudo apt-get install -y jq
```

If you prefer not to install it, the same comparisons can be done with Ruby (already present for the
firmware), e.g.:

```bash
ruby -rjson -e 'a=JSON.parse(File.read(ARGV[0]))["snames"]; \
                b=JSON.parse(File.read(ARGV[1]))["snames"]; \
                puts(a==b ? "names: IDENTICAL" : "names: DIFFER")' c-jn.json ruby-jn.json
```

---

## Phase 0 — Preserve current state (automated; C++ still running; no impact)

```bash
TS=$(date +%Y%m%d-%H%M%S); B=~/cutover-backup-$TS; mkdir -p $B
# C++ firmware binary state (root-owned)
sudo tar czf $B/c-firmware-state.tgz -C /home/jeff/OpenSprinkler-Firmware \
    iopts.dat sopts.dat stns.dat prog.dat nvcon.dat done.dat
# Ruby data dir (stale config — preserve so the Ruby side can also be reverted)
tar czf $B/ruby-data.tgz -C /home/jeff/opensprinkler-ruby data
# systemd + GPIO snapshot
{ systemctl is-active OpenSprinkler; systemctl is-enabled OpenSprinkler;
  gpioinfo | grep -E 'line +(4|17|22|27):'; } > $B/state-before.txt
```

**Checkpoint:** three artifacts in `$B`; `state-before.txt` shows `active`/`enabled` and lines `[used]`.

## Phase 1 — Export config from the C++ server (automated; read-only)

```bash
P=a6d82bced638de3def1e9bbb4983225c   # default pw hash; update if changed
for ep in ja jo jp jn je js jc jl; do
  curl -s --max-time 8 "http://127.0.0.1:8080/$ep?pw=$P" > $B/c-$ep.json
done
```

Also capture the canonical UI export (manual): open <https://ui.opensprinkler.com>, connect to
`http://192.168.7.200:8080`, then **Edit Options → Export Configuration** → save as
`$B/c-export-$TS.json`.

**Checkpoint:** `c-ja.json` parses; `c-jc.json` shows `"nbrd":4,"en":1`; UI export downloaded.

## Phase 2 — Pre-stage import into Ruby (mock, port 8081; still no downtime)

Proves the import works and produces the real `data/` the service will use, while C++ keeps running.

```bash
cd /home/jeff/opensprinkler-ruby && eval "$(rbenv init - bash)"
cp -r data data.prestage.bak                                   # extra safety
bundle exec ruby bin/opensprinkler -H mock -d data -p 8081 &   # mock: no GPIO, no 8080
```

Point the UI at `http://192.168.7.200:8081` → **Import Configuration** → upload `c-export-$TS.json`
(this drives Ruby's `/co`, `/cs`, `/cp` writes, rewriting `data/*.yml`).

Automated validation against the mock instance:

```bash
for ep in jo jp jn je js; do curl -s "http://127.0.0.1:8081/$ep?pw=$P" > $B/ruby-$ep.json; done
diff <(jq -S '.snames' $B/c-jn.json) <(jq -S '.snames' $B/ruby-jn.json)   # station names
diff <(jq -S '.pd'     $B/c-jp.json) <(jq -S '.pd'     $B/ruby-jp.json)   # programs
# options: spot-check key indices (nbrd, station/master delays, etc.) between c-jo and ruby-jo
bundle exec rspec        # expect only the known pre-existing app_spec.rb:245 failure
kill %1                  # stop the mock instance
```

**Checkpoint:** station names + programs match C++; `data/*.yml` now reflects current config; tests
green except the known failure. **If the import is wrong, abort here — zero impact, C++ still serving.**

## Phase 3 — Cutover window (brief downtime begins)

```bash
sudo systemctl stop OpenSprinkler && sudo systemctl disable OpenSprinkler
gpioinfo | grep -E 'line +(4|17|22|27):'      # expect "unused"
ss -tln | grep :8080 || echo "8080 free"
sudo cp systemd/opensprinkler-home.service /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now opensprinkler-home
```

**Checkpoint:** `opensprinkler-home` is `active`; `journalctl -u opensprinkler-home` shows clean GPIO
setup with **no "GPIO init failed / Running without hardware" fallback**; `gpioinfo` lines are
`[used]` again; `ss` shows 8080 listening.

## Phase 4 — Post-cutover automated tests

```bash
P=a6d82bced638de3def1e9bbb4983225c
for ep in jc jo jp jn je js ja; do curl -s "http://127.0.0.1:8080/$ep?pw=$P" > $B/post-$ep.json; done
curl -s -o /dev/null -w "%{http_code}\n" http://192.168.7.200:8080/    # external reachability
# config parity: Ruby-live vs C++ baseline
diff <(jq -S '.snames' $B/c-jn.json) <(jq -S '.snames' $B/post-jn.json)
diff <(jq -S '.pd'     $B/c-jp.json) <(jq -S '.pd'     $B/post-jp.json)
jq '{fwv,nbrd,en}' $B/post-jc.json                                     # expect fwv 2.2.1.4-equiv, nbrd 4, en 1
```

Optional hardware test (gated on the valve-test decision): use `/cm` to energize one station,
confirm via `gpioinfo` and `/js`, then turn it off — water-supply state per the chosen option.

## Phase 5 — Manual confirmation (UI)

- Open <https://ui.opensprinkler.com> → `http://192.168.7.200:8080`: confirm it connects and shows
  the correct station names, programs, options, rain-delay state, and logs.
- Toggle a zone on/off (safe-only: watch `/js` + `gpioinfo` rather than water); set then clear a
  rain delay; confirm the enable/disable toggle.
- Watch one scheduled or `/cr` run-once cycle in `journalctl -u opensprinkler-home -f` end-to-end
  (queue → station on → master timing → off).

## Success criteria (all must hold)

- Service is `active` and survives `systemctl restart` / a reboot.
- GPIO is claimed by the Ruby process (no MockGPIO fallback in the log).
- Config parity vs the C++ export (station names, programs, option values).
- UI is fully functional.
- One watering cycle observed correct end-to-end.

## Rollback (if any criterion fails)

```bash
sudo systemctl disable --now opensprinkler-home
# only if the Ruby data looks corrupted:
#   tar xzf $B/ruby-data.tgz -C /home/jeff/opensprinkler-ruby
sudo systemctl enable --now OpenSprinkler        # C++ state was never modified → original behavior
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8080/
```

Fast and safe because the C++ `*.dat` files are never modified and the Ruby `data/` is backed up.

## Finalize (after a soak period)

Keep `OpenSprinkler.service` disabled (not deleted), and retain the `$B` backups and
`/home/jeff/OpenSprinkler-Firmware` as the rollback path until confident in the Ruby firmware.
