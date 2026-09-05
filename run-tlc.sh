#!/usr/bin/env bash
# Exhaustive TLC run of the bundled RoshanferTest configuration.
# Records command, full log, GNU time, and a reviewer-facing summary.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

TLA2TOOLS_VERSION="1.7.4"
TLA2TOOLS_URL="https://github.com/tlaplus/tlaplus/releases/download/v${TLA2TOOLS_VERSION}/tla2tools.jar"
TLA2TOOLS_JAR="${ROOT}/tla2tools.jar"
SPEC="RoshanferTest.tla"
CONFIG="RoshanferTest.cfg"
RESULTS="${ROOT}/results"
META_DIR="${ROOT}/.states"
OUT_FILE="${RESULTS}/tlc-output.txt"
TIME_FILE="${RESULTS}/tlc-time.txt"
CMD_FILE="${RESULTS}/tlc-command.txt"
SUMMARY_FILE="${RESULTS}/summary.txt"

HEAP="${HEAP:-32G}"
DIRECT_MEM="${DIRECT_MEM:-64G}"
FPMEM="${FPMEM:-0.5}"
WORKERS="${WORKERS:-auto}"

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "error: required command not found: $1" >&2
        exit 1
    }
}

need_cmd java
need_cmd python3
if ! command -v /usr/bin/time >/dev/null 2>&1; then
    echo "error: /usr/bin/time is required" >&2
    exit 1
fi

if [[ ! -f "$TLA2TOOLS_JAR" ]]; then
    echo "Downloading tla2tools.jar ${TLA2TOOLS_VERSION}..."
    if command -v curl >/dev/null 2>&1; then
        curl -fL --retry 3 -o "$TLA2TOOLS_JAR" "$TLA2TOOLS_URL"
    elif command -v wget >/dev/null 2>&1; then
        wget -O "$TLA2TOOLS_JAR" "$TLA2TOOLS_URL"
    else
        echo "error: need curl or wget to download tla2tools.jar" >&2
        exit 1
    fi
fi

mkdir -p "$RESULTS" "$META_DIR"

JAVA_BIN="$(command -v java)"
NPROC="$(nproc)"
JAVA_VERSION="$(java -version 2>&1 | tr '\n' ' ')"
HOST="$(hostname)"
START_ISO="$(date -Is)"

JAVA_ARGS=(
    -XX:+UseParallelGC
    -Xmx"${HEAP}"
    -XX:MaxDirectMemorySize="${DIRECT_MEM}"
    -Dtlc2.tool.fp.FPSet.impl=tlc2.tool.fp.OffHeapDiskFPSet
    -Dtlc2.tool.ModelChecker.BAQueue=true
)

TLC_ARGS=(
    -workers "$WORKERS"
    -lncheck final
    -checkpoint 0
    -cleanup
    -fpmem "$FPMEM"
    -metadir "$META_DIR"
    -config "$CONFIG"
    "$SPEC"
)

{
    echo "# Exact TLC invocation"
    echo "date:        ${START_ISO}"
    echo "host:        ${HOST}"
    echo "nproc:       ${NPROC}"
    echo "java:        ${JAVA_BIN}"
    echo "java_version:${JAVA_VERSION}"
    echo "tla2tools:   ${TLA2TOOLS_JAR} (${TLA2TOOLS_VERSION})"
    echo "cwd:         ${ROOT}"
    echo
    printf '%q ' /usr/bin/time -v -o "$TIME_FILE" "$JAVA_BIN"
    printf '%q ' "${JAVA_ARGS[@]}"
    printf '%q ' -jar "$TLA2TOOLS_JAR"
    printf '%q ' "${TLC_ARGS[@]}"
    echo
} > "$CMD_FILE"

echo "Running TLC with ${WORKERS} workers (nproc=${NPROC}), heap=${HEAP}, direct=${DIRECT_MEM}"
echo "Log: $OUT_FILE"

set +e
/usr/bin/time -v -o "$TIME_FILE" \
    "$JAVA_BIN" "${JAVA_ARGS[@]}" -jar "$TLA2TOOLS_JAR" "${TLC_ARGS[@]}" \
    2>&1 | tee "$OUT_FILE"
TLC_STATUS=${PIPESTATUS[0]}
set -e
END_ISO="$(date -Is)"

python3 - "$OUT_FILE" "$TIME_FILE" "$CMD_FILE" "$SUMMARY_FILE" "$TLC_STATUS" "$END_ISO" "$NPROC" "$HOST" <<'PY'
import re, sys, pathlib

out_path, time_path, cmd_path, summary_path, status, end_iso, nproc, host = sys.argv[1:9]
status = int(status)
out = pathlib.Path(out_path).read_text(errors="replace")
time_txt = pathlib.Path(time_path).read_text(errors="replace") if pathlib.Path(time_path).exists() else ""
cmd = pathlib.Path(cmd_path).read_text(errors="replace")

def first(pat, text, default="(not reported)"):
    m = re.search(pat, text, re.MULTILINE | re.IGNORECASE)
    return m.group(1).strip() if m else default

generated = first(r"([\d,]+)\s+states generated", out)
distinct = first(r"([\d,]+)\s+distinct states found", out)
queue = first(r"([\d,]+)\s+states left on queue", out)
depth = first(r"The depth of the complete state graph search is\s+(\d+)", out)
finished = first(r"Finished in ([^\n]+)", out)
workers = first(r"Running with (\d+) workers", out)
if workers == "(not reported)":
    workers = first(r"Using (\d+) worker", out)
fp_mem = first(r"Fingerprint(?: set)?[^\n]*?([\d.]+\s*(?:MB|GB|KB|bytes)[^\n]*)", out)
no_error = "Model checking completed. No error has been found." in out
error_found = bool(re.search(r"Error:|Invariant.*is violated|Deadlock reached", out))

elapsed = first(r"Elapsed \(wall clock\) time \(h:mm:ss or m:ss\):\s+(\S+)", time_txt)
max_rss_kb = first(r"Maximum resident set size \(kbytes\):\s+(\d+)", time_txt)
user_time = first(r"User time \(seconds\):\s+(\S+)", time_txt)
sys_time = first(r"System time \(seconds\):\s+(\S+)", time_txt)

rss_human = "(not reported)"
if max_rss_kb.isdigit():
    kb = int(max_rss_kb)
    if kb >= 1024 * 1024:
        rss_human = f"{kb / (1024 * 1024):.2f} GiB ({kb} kB)"
    elif kb >= 1024:
        rss_human = f"{kb / 1024:.2f} MiB ({kb} kB)"
    else:
        rss_human = f"{kb} kB"

result_line = (
    "Model checking completed. No error has been found."
    if no_error and status == 0
    else f"TLC exited with status {status}" + ("; error found in log" if error_found else "")
)

summary = f"""Roshanfer TLC verification summary
===================================

Result: {result_line}
Host: {host}
Workers: {workers} (nproc={nproc})
Finished at: {end_iso}

Checked topology and bounds
---------------------------
Configuration: RoshanferTest.tla / RoshanferTest.cfg
Services: 5 (Frontend=S1 plus S2..S5)
APIs / frontend endpoints: 2
EndpointLimits: all endpoints 1
GlobalLimits: S1,S2,S3 = -1 (no global limit); S4,S5 = 1 (leaves)
EndpointWeights: S4 uses 2:1; others 1
Call graph (ServerDownstreams):
  S1.E1 (API 1): one stage, dynamic choice {{S2.E1, S5.E1}}
  S1.E2 (API 2): one stage, {{S3.E2}}
  S2.E1: sequential stages {{S4.E1}} then {{S3.E1}}
  S2.E2: leaf
  S3.E1: leaf
  S3.E2: one stage, dynamic choice {{S4.E2, S2.E2}}
  S4.E1, S4.E2, S5.E1: leaves
Admitted messages (NumberOfMessages = TotalEndpointPathLimit(1, api)):
  API 1: 5
  API 2: 4
Properties: invariants Conservation, ABound, NsBound; liveness AllProcessed

TLC statistics
--------------
States generated:     {generated}
Distinct states:      {distinct}
States left on queue: {queue}
Search depth:         {depth}
TLC runtime:          {finished}
Wall-clock (time -v): {elapsed}
User time (s):        {user_time}
System time (s):      {sys_time}
Max RSS:              {rss_human}
Fingerprint memory:   {fp_mem}

Exact command
-------------
{cmd.strip()}

Full TLC transcript: {out_path}
GNU time output:     {time_path}
"""
pathlib.Path(summary_path).write_text(summary)
print(summary)
sys.exit(status)
PY
