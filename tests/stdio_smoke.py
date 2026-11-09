"""Bounded NDJSON MCP smoke against an isolated gateway child (no services)."""
import json
import pathlib
import subprocess
import sys
import tempfile


def main():
    binary = str(pathlib.Path(sys.argv[1]).resolve())
    requests = [
        {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
            "protocolVersion": "2024-11-05", "capabilities": {},
            "clientInfo": {"name": "isolated-smoke", "version": "1"}}},
        {"jsonrpc": "2.0", "method": "notifications/initialized"},
        {"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}},
        {"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {
            "name": "sys__ping", "arguments": {}}},
        {"jsonrpc": "2.0", "id": 4, "method": "tools/call", "params": {
            "name": "sys__status", "arguments": {}}},
    ]
    with tempfile.TemporaryDirectory(prefix="gateway-smoke-") as directory:
        result = subprocess.run(
            [binary, "-c", str(pathlib.Path(directory) / "absent.env")],
            input="".join(json.dumps(r) + "\n" for r in requests),
            capture_output=True, text=True, timeout=5, cwd=directory, env={})
    assert result.returncode == 0, result.stderr
    replies = [json.loads(line) for line in result.stdout.splitlines()]
    assert [r["id"] for r in replies] == [1, 2, 3, 4], replies
    assert all(r["jsonrpc"] == "2.0" and "error" not in r for r in replies), replies
    initialize, listing, ping, status = [r["result"] for r in replies]
    assert initialize["protocolVersion"] == "2024-11-05", initialize
    assert initialize["serverInfo"]["version"] == "1.3.1", initialize
    assert {t["name"] for t in listing["tools"]} == {"sys__ping", "sys__status"}, listing
    assert ping["content"] == [{"type": "text", "text": "pong"}], ping
    assert not ping.get("isError", False), ping
    assert "0.17.1" in status["content"][0]["text"], status
    print(json.dumps({"transport": "stdio", "replies": replies,
                      "notification_replies": 0, "child_exit": result.returncode}))


if __name__ == "__main__":
    main()
