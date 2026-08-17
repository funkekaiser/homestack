#!/usr/bin/env bash
#
# Canonical-redirect health check for example.com / funkekaiser.com / funke-kaiser.us /
# casabianconstruction.com and their alternate hostnames.
#
# Verifies every alternate host (http + https, with/without www) lands on the
# canonical https:// apex, and that each apex itself answers 200. Pushes an
# aggregate up/down result to an Uptime Kuma "Push" monitor.
#
# Setup (one-time):
#   1. In Uptime Kuma (https://uptime.example.com) add a new monitor, type "Push".
#   2. Copy its Push URL (looks like https://uptime.example.com/api/push/<token>).
#   3. Put it in the repo .env as:  KUMA_PUSH_URL=https://uptime.example.com/api/push/<token>
#   4. Set the monitor's "Heartbeat Interval" to match the cron cadence below
#      (e.g. 300s for an every-5-minutes cron) plus some slack.
#
# Run standalone (prints a report, exits non-zero on any failure):
#   ./kuma/scripts/check-canonical-redirects.sh

set -uo pipefail

# Load KUMA_PUSH_URL from the repo .env if present (script lives in kuma/scripts/).
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
[[ -f "$REPO_ROOT/.env" ]] && set -a && . "$REPO_ROOT/.env" && set +a
KUMA_PUSH_URL="${KUMA_PUSH_URL:-}"

fails=()

check() {
  local src="$1" expected="$2"
  local scheme url out code final hops verdict
  for scheme in http https; do
    url="$scheme://$src"
    out=$(curl -sSL -o /dev/null -w '%{http_code} %{url_effective} %{num_redirects}' \
      --max-time 15 "$url" 2>/dev/null)
    code=$(awk '{print $1}' <<<"$out")
    final=$(awk '{print $2}' <<<"$out")
    hops=$(awk '{print $3}' <<<"$out")

    if [[ "$final" == https://* && "$final" == "$expected"* ]]; then
      verdict="OK"
    else
      verdict="CHECK"
      fails+=("$scheme://$src -> ${final:-<no response>} [${code:-000}]")
    fi
    printf '%-6s %-28s -> %-34s [%s, %s hops] %s\n' \
      "$scheme" "$src" "${final:-<no response>}" "${code:-000}" "$hops" "$verdict"
  done
}

apex() {
  local host="$1" code
  code=$(curl -sSL -o /dev/null -w '%{http_code}' --max-time 15 "https://$host" 2>/dev/null)
  printf '%-29s -> %s\n' "$host" "${code:-000}"
  [[ "$code" == 200 ]] || fails+=("apex $host -> ${code:-000} (expected 200)")
}

echo "== canonical: https://example.com =="
check "www.jofk.dev" "https://example.com"
check "jofk.dev"     "https://example.com"
check "www.jofk.io"  "https://example.com"
check "jofk.io"      "https://example.com"
check "www.example.com"  "https://example.com"
echo

echo "== canonical: https://funkekaiser.com =="
check "www.funkekaiser.com" "https://funkekaiser.com"
check "funkekaiser.com"     "https://funkekaiser.com"
check "www.funke-kaiser.at" "https://funkekaiser.com"
check "funke-kaiser.at"     "https://funkekaiser.com"
echo

echo "== canonical: https://funke-kaiser.us =="
check "www.funke-kaiser.us" "https://funke-kaiser.us"
check "funke-kaiser.us"     "https://funke-kaiser.us"
echo

echo "== canonical: https://casabianconstruction.com =="
check "www.casabianconstruction.com" "https://casabianconstruction.com"
check "casabianconstruction.com"     "https://casabianconstruction.com"
echo

echo "== apex reachability (should be 200) =="
apex example.com
apex funkekaiser.com
apex funke-kaiser.us
apex casabianconstruction.com

if [[ ${#fails[@]} -eq 0 ]]; then
  status="up"
  msg="all redirects canonical"
else
  status="down"
  msg="${#fails[@]} issue(s): $(IFS='; '; echo "${fails[*]}")"
fi
echo
echo "== verdict: $status -- $msg =="

if [[ -n "$KUMA_PUSH_URL" ]]; then
  if curl -fsS -G "$KUMA_PUSH_URL" \
      --data-urlencode "status=$status" \
      --data-urlencode "msg=$msg" \
      --max-time 15 -o /dev/null; then
    echo "pushed to Uptime Kuma: $status"
  else
    echo "WARNING: push to Uptime Kuma failed" >&2
  fi
else
  echo "(KUMA_PUSH_URL not set -- skipping push; report only)" >&2
fi

[[ "$status" == "up" ]]
