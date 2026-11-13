#!/usr/bin/env python3
"""Fail-open test telemetry reporter for VictoriaMetrics and Loki.

Ships test metrics (duration, status, runs) to VictoriaMetrics via Prometheus line
protocol and execution logs to Loki. Fails open on any network or server error so
builds and tests never fail due to monitoring outages.
"""

import argparse
import http.client
import json
import os
import socket
import subprocess
import sys
import time
import urllib.parse

DEFAULT_VM_URL = os.environ.get(
    "VICTORIAMETRICS_URL",
    os.environ.get("VM_URL", "http://10.85.47.116:8428"),
)
DEFAULT_LOKI_URL = os.environ.get("LOKI_URL", "http://10.85.47.116:3100")
HTTP_TIMEOUT_SECONDS = 3.0


def detect_repo() -> str:
    """Detect current repo name from git/jj directory."""
    cwd = os.getcwd()
    for segment in reversed(cwd.split(os.sep)):
        if segment and not segment.endswith(".ws"):
            return segment
    return "unknown"


def post_http(url: str, data: bytes, content_type: str) -> bool:
    """Send POST request fail-open to HTTP or HTTPS endpoint."""
    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme not in ("http", "https"):
        return False

    path = parsed.path or "/"
    if parsed.query:
        path = f"{path}?{parsed.query}"

    try:
        if parsed.scheme == "https":
            conn = http.client.HTTPSConnection(
                parsed.netloc, timeout=HTTP_TIMEOUT_SECONDS
            )
        else:
            conn = http.client.HTTPConnection(
                parsed.netloc, timeout=HTTP_TIMEOUT_SECONDS
            )

        headers = {"Content-Type": content_type}
        conn.request("POST", path, body=data, headers=headers)
        resp = conn.getresponse()
        conn.close()
        return 200 <= resp.status < 300
    except (TimeoutError, ConnectionError, OSError):
        return False


def send_victoriametrics(
    vm_url: str,
    test: str,
    repo: str,
    suite: str,
    status: str,
    duration: float,
    host: str,
) -> bool:
    """Send test metrics to VictoriaMetrics via Prometheus line protocol."""
    ts_ms = int(time.time() * 1000)
    val_status = 1 if status == "pass" else 0
    lines = [
        f'fleet_test_status{{test="{test}",repo="{repo}",suite="{suite}",host="{host}"}} {val_status} {ts_ms}',
        f'fleet_test_duration_seconds{{test="{test}",repo="{repo}",suite="{suite}",host="{host}"}} {duration:.3f} {ts_ms}',
        f'fleet_test_runs_total{{test="{test}",repo="{repo}",suite="{suite}",host="{host}",status="{status}"}} 1 {ts_ms}',
    ]
    payload = "\n".join(lines).encode("utf-8")
    url = f"{vm_url.rstrip('/')}/api/v1/import/prometheus"
    return post_http(url, payload, "text/plain")


def send_loki(
    loki_url: str,
    test: str,
    repo: str,
    status: str,
    host: str,
    log_lines: list[str],
) -> bool:
    """Push test logs to Loki."""
    if not log_lines:
        return True
    ts_ns = str(time.time_ns())
    # Keep stream payload within manageable batch limits (last 500 lines).
    trimmed = log_lines[-500:]
    values = [[ts_ns, line] for line in trimmed]
    payload = json.dumps(
        {
            "streams": [
                {
                    "stream": {
                        "job": "fleet-tests",
                        "repo": repo,
                        "test": test,
                        "status": status,
                        "host": host,
                    },
                    "values": values,
                }
            ]
        }
    ).encode("utf-8")
    url = f"{loki_url.rstrip('/')}/loki/api/v1/push"
    return post_http(url, payload, "application/json")


def run_command(cmd: list[str]) -> tuple[int, float, list[str]]:
    """Run wrapped command, measure duration, and collect combined stdout/stderr."""
    start = time.perf_counter()
    lines: list[str] = []
    # Stream output to terminal in real time while buffering for Loki.
    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )
    if proc.stdout:
        for line in proc.stdout:
            sys.stdout.write(line)
            sys.stdout.flush()
            lines.append(line.rstrip("\n"))
    proc.wait()
    duration = time.perf_counter() - start
    return proc.returncode, duration, lines


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Ship fail-open test metrics & logs to VictoriaMetrics and Loki."
    )
    parser.add_argument(
        "--test", required=True, help="Test name (e.g. caddy, mobile-link)"
    )
    parser.add_argument("--repo", default=detect_repo(), help="Target repo name")
    parser.add_argument(
        "--suite", default="integration", help="Suite (integration or unit)"
    )
    parser.add_argument(
        "--status", choices=["pass", "fail"], help="Status if not wrapping a command"
    )
    parser.add_argument(
        "--duration", type=float, default=0.0, help="Duration in seconds if manual"
    )
    parser.add_argument(
        "--vm-url", default=DEFAULT_VM_URL, help="VictoriaMetrics base URL"
    )
    parser.add_argument("--loki-url", default=DEFAULT_LOKI_URL, help="Loki base URL")
    parser.add_argument(
        "cmd", nargs="*", help="Optional command to execute and monitor"
    )

    args = parser.parse_args()
    host = socket.gethostname()
    log_lines: list[str] = []
    exit_code = 0

    if args.cmd:
        code, duration, log_lines = run_command(args.cmd)
        status = "pass" if code == 0 else "fail"
        exit_code = code
    else:
        status = args.status or "pass"
        duration = args.duration

    # Ship metrics and logs fail-open.
    send_victoriametrics(
        args.vm_url, args.test, args.repo, args.suite, status, duration, host
    )
    send_loki(args.loki_url, args.test, args.repo, status, host, log_lines)

    return exit_code


if __name__ == "__main__":
    sys.exit(main())
