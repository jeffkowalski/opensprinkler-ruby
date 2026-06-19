#!/bin/bash
# Convenience launcher for the OSPi (Raspberry Pi) deployment.
# rbenv is not on the PATH of non-login shells, so load it explicitly before
# invoking bundle/ruby (mirrors what systemd/opensprinkler-home.service does).
set -euo pipefail

export RBENV_ROOT=/home/jeff/.rbenv
export PATH="$RBENV_ROOT/bin:$RBENV_ROOT/shims:$PATH"
eval "$(rbenv init - bash)"

cd /home/jeff/opensprinkler-ruby
exec bundle exec ruby bin/opensprinkler -d data -p 8080 -H ospi
