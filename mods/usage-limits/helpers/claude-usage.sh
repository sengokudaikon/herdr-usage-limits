#!/bin/sh
# Prints Claude Code's usage (one `control_response` JSON line) and exits.
#
# Runs your own `claude` CLI briefly and sends it the `get_usage` control
# request; the CLI authenticates itself. This script reads no tokens or
# credential files, sends no prompt and starts no turn. `--safe-mode` keeps
# hooks, MCP servers and customizations out of it.
# Approach credit: jmalicki/herdr-mod-ai-usage (MIT).
#
# Exit: 0 = printed the reply, 127 = claude CLI not found, 1 = no reply in 15 s.
# Override the binary with HERDR_USAGE_CLAUDE_BIN.

CLAUDE=$(command -v "${HERDR_USAGE_CLAUDE_BIN:-claude}" 2>/dev/null) || exit 127

REQUEST='{"type":"control_request","request_id":"herdr-usage-limits","request":{"subtype":"get_usage","skip_behaviors":true}}'

dir=$(mktemp -d "${TMPDIR:-/tmp}/herdr-claude-usage.XXXXXX") || exit 1
out="$dir/out"
: >"$out"
# A clock, not a count: Git Bash forks slowly, and 75 rounds of 0.2 s ran to 20 s there.
end=$(($(date +%s) + 15))

# The request goes in through a pipe that stays open until the reply is out
# (at most 15 s), so the CLI then sees end of input and exits by itself.
# A pipe, not a FIFO: with Git Bash on Windows, a FIFO reaches claude.exe empty.
# The writer holds none of this script's output, so it can't keep a caller waiting.
{
  printf '%s\n' "$REQUEST"
  while [ "$(date +%s)" -lt "$end" ] && [ -f "$out" ] && ! grep -q '"control_response"' "$out"; do
    sleep 0.2
  done
} 2>/dev/null | "$CLAUDE" -p --safe-mode --no-session-persistence \
  --input-format stream-json --output-format stream-json --verbose \
  >"$out" 2>/dev/null &
pid=$!

while [ "$(date +%s)" -lt "$end" ]; do
  if grep -q '"control_response"' "$out" 2>/dev/null; then break; fi
  kill -0 "$pid" 2>/dev/null || break
  sleep 0.2
done
# Answered: its input closes too, so it gets up to 2 s to exit by itself.
if grep -q '"control_response"' "$out" 2>/dev/null; then
  i=0
  while [ "$i" -lt 10 ] && kill -0 "$pid" 2>/dev/null; do
    sleep 0.2
    i=$((i + 1))
  done
fi
kill "$pid" 2>/dev/null
wait "$pid" 2>/dev/null

status=1
if grep -m1 '"control_response"' "$out"; then status=0; fi
rm -rf "$dir"
exit $status
