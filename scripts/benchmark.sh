#!/bin/bash
set -uo pipefail
cd "$(dirname "$0")/.."

# benchmark.sh — measure what macOS system monitors actually cost you.
#
# Samples the cumulative CPU time and resident memory of one or more menu bar
# system monitors over a fixed window, and reports how much CPU each one
# consumed. Published alongside the results so anyone can reproduce them.
#
#   scripts/benchmark.sh                          # 15 min, 10s samples
#   scripts/benchmark.sh -d 30 -i 5 -l "idle"     # 30 min, 5s samples, labelled
#   scripts/benchmark.sh -d 5 -l "popover-open"
#
# Flags:
#   -d MINUTES   total run time            (default 15)
#   -i SECONDS   sampling interval         (default 10)
#   -l LABEL     scenario label for the CSV (default "unlabelled")
#   -o FILE      output CSV path           (default benchmark-<label>-<date>.csv)
#
# METHOD — why it is done this way
#
#   * `ps -o %cpu` is NOT used. That column is the average since the process
#     launched, not current usage, so sampling it repeatedly measures the wrong
#     thing. Instead we read cumulative CPU time (`ps -o cputime`) and take the
#     delta between samples: (Δcpu_time / Δwall_time) × 100 = %CPU for that
#     interval. This is exact and independent of how long the app has been up.
#
#   * ALL processes belonging to an app are summed, not just the main one.
#     Some monitors run separate helpers or daemons; measuring only the visible
#     process would understate them badly. The matched processes are printed at
#     the start of every run so the numbers can be audited.
#
#   * The headline metric is CPU-seconds consumed per hour of running. It is
#     absolute, intuitive, and maps directly to battery drain — unlike a
#     percentage, which hides how long the app was busy.
#
# FAIRNESS — read before publishing any comparison
#
#   Configure every app the same way before running: same refresh interval and
#   a comparable set of displayed metrics. An app polling once a second will
#   always lose to one polling every three seconds, and that says nothing about
#   how well it is written. Run the suite twice and publish both:
#     1. normalised — identical refresh intervals and metrics
#     2. as-shipped — every app on its own defaults (what users actually get)
#
#   Record app versions and machine details with the results. Publish runs that
#   are unfavourable too; a benchmark that only ever flatters its author is
#   worth nothing.

DURATION_MIN=15
INTERVAL_SEC=10
LABEL="unlabelled"
OUT=""

while getopts "d:i:l:o:h" opt; do
    case "$opt" in
        d) DURATION_MIN="$OPTARG" ;;
        i) INTERVAL_SEC="$OPTARG" ;;
        l) LABEL="$OPTARG" ;;
        o) OUT="$OPTARG" ;;
        h) sed -n '3,30p' "$0"; exit 0 ;;
        *) echo "See: $0 -h" >&2; exit 1 ;;
    esac
done

[ -z "$OUT" ] && OUT="benchmark-${LABEL}-$(date +%Y%m%d-%H%M).csv"

# Apps to measure: "Display name|pgrep -f pattern".
# The pattern must be specific enough not to match unrelated processes, and
# broad enough to catch helper processes belonging to the same app.
APPS=(
    "Performance Monitor|Performance Monitor.app/Contents/MacOS/Performance Monitor"
    "Performance Monitor Beta|Performance Monitor Beta.app"
    "Stats|Stats.app/Contents/MacOS"
    "iStat Menus|iStat"
    "MenuMeters|MenuMeters"
    "Activity Monitor|Activity Monitor.app"
)

# Convert ps cputime ([DD-]HH:MM:SS[.ss] or MM:SS.ss) to seconds.
cputime_to_seconds() {
    awk '{
        t = $0
        days = 0
        if (index(t, "-") > 0) { split(t, d, "-"); days = d[1]; t = d[2] }
        n = split(t, p, ":")
        if (n == 3)      { secs = p[1]*3600 + p[2]*60 + p[3] }
        else if (n == 2) { secs = p[1]*60 + p[2] }
        else             { secs = p[1] }
        printf "%.2f", days*86400 + secs
    }'
}

# Total cumulative CPU seconds and RSS (MB) across every process of one app.
# Echoes "cpu_seconds rss_mb process_count".
sample_app() {
    local pattern="$1"
    local pids
    pids=$(pgrep -f "$pattern" 2>/dev/null || true)
    if [ -z "$pids" ]; then echo "0 0 0"; return; fi

    local total_cpu=0 total_rss=0 count=0
    for pid in $pids; do
        local line
        line=$(ps -o cputime=,rss= -p "$pid" 2>/dev/null) || continue
        [ -z "$line" ] && continue
        local ct rss secs
        ct=$(echo "$line" | awk '{print $1}')
        rss=$(echo "$line" | awk '{print $2}')
        secs=$(echo "$ct" | cputime_to_seconds)
        total_cpu=$(awk -v a="$total_cpu" -v b="$secs" 'BEGIN{printf "%.2f", a+b}')
        total_rss=$(awk -v a="$total_rss" -v b="$rss" 'BEGIN{printf "%.1f", a + b/1024}')
        count=$((count + 1))
    done
    echo "$total_cpu $total_rss $count"
}

echo "=== System monitor benchmark ==="
echo "Machine:  $(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo unknown)"
echo "macOS:    $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
echo "Date:     $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "Scenario: ${LABEL}"
echo "Duration: ${DURATION_MIN} min, sampling every ${INTERVAL_SEC}s"
echo ""

# Show exactly which processes are being measured — this is what makes the
# numbers auditable. Anything not running is reported and skipped.
RUNNING=()
echo "Processes matched:"
for entry in "${APPS[@]}"; do
    name="${entry%%|*}"; pattern="${entry##*|}"
    pids=$(pgrep -f "$pattern" 2>/dev/null || true)
    if [ -z "$pids" ]; then
        printf "  %-22s not running — skipped\n" "$name"
        continue
    fi
    RUNNING+=("$entry")
    printf "  %-22s" "$name"
    first=true
    for pid in $pids; do
        comm=$(ps -o comm= -p "$pid" 2>/dev/null | xargs basename 2>/dev/null)
        if $first; then printf "pid %s (%s)\n" "$pid" "$comm"; first=false
        else printf "  %-22s pid %s (%s)\n" "" "$pid" "$comm"; fi
    done
done
echo ""

if [ ${#RUNNING[@]} -eq 0 ]; then
    echo "ERROR: none of the apps are running. Launch them first." >&2
    exit 1
fi

echo "timestamp,scenario,app,cpu_seconds_cumulative,rss_mb,process_count" > "$OUT"

SAMPLES=$(( DURATION_MIN * 60 / INTERVAL_SEC ))
[ "$SAMPLES" -lt 2 ] && SAMPLES=2

echo "Running ${SAMPLES} samples — leave the machine alone until it finishes."
echo ""

for ((s = 0; s < SAMPLES; s++)); do
    ts=$(date '+%Y-%m-%dT%H:%M:%S')
    for entry in "${RUNNING[@]}"; do
        name="${entry%%|*}"; pattern="${entry##*|}"
        read -r cpu rss count <<< "$(sample_app "$pattern")"
        echo "${ts},${LABEL},${name},${cpu},${rss},${count}" >> "$OUT"
    done
    printf "\r  sample %d/%d" "$((s + 1))" "$SAMPLES"
    [ "$s" -lt "$((SAMPLES - 1))" ] && sleep "$INTERVAL_SEC"
done
printf "\r%*s\r" 40 ""

# Summary: CPU seconds consumed over the window, extrapolated per hour, plus
# mean %CPU and mean memory. Uses first/last cumulative values per app.
echo "=== Results (scenario: ${LABEL}) ==="
printf "%-22s %12s %14s %10s %10s\n" "App" "CPU-sec" "CPU-sec/hour" "mean %CPU" "mem (MB)"
printf "%-22s %12s %14s %10s %10s\n" "----------------------" "------------" "--------------" "----------" "----------"

for entry in "${RUNNING[@]}"; do
    name="${entry%%|*}"
    awk -F, -v app="$name" -v interval="$INTERVAL_SEC" '
        $3 == app {
            if (first == "") { first = $4; t0 = NR }
            last = $4
            rss_sum += $5; n++
        }
        END {
            if (n < 2) { printf "%-22s %12s %14s %10s %10s\n", app, "n/a", "n/a", "n/a", "n/a"; exit }
            elapsed = (n - 1) * interval
            used = last - first
            if (used < 0) used = 0                     # process restarted mid-run
            per_hour = elapsed > 0 ? used * 3600 / elapsed : 0
            pct = elapsed > 0 ? used * 100 / elapsed : 0
            printf "%-22s %12.1f %14.1f %10.2f %10.1f\n", app, used, per_hour, pct, rss_sum / n
        }
    ' "$OUT"
done

echo ""
echo "Raw samples: ${OUT}"
echo "Reminder: record each app's version and refresh-interval setting alongside"
echo "these numbers, and run the suite a second time on as-shipped defaults."
