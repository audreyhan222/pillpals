import json, os, time, uuid

LOG_PATH = "/Users/audre/code/personal/lahacks2/pillpal/.cursor/debug-ca992b.log"
SESSION_ID = "ca992b"


def log(hypothesis_id: str, location: str, message: str, data: dict | None = None, run_id: str = "pre-fix"):
    os.makedirs(os.path.dirname(LOG_PATH), exist_ok=True)
    payload = {
        "sessionId": SESSION_ID,
        "id": f"log_{int(time.time() * 1000)}_{uuid.uuid4().hex[:8]}",
        "timestamp": int(time.time() * 1000),
        "location": location,
        "message": message,
        "data": data or {},
        "runId": run_id,
        "hypothesisId": hypothesis_id,
    }
    with open(LOG_PATH, "a", encoding="utf-8") as f:
        f.write(json.dumps(payload, separators=(",", ":")) + "\n")


if __name__ == "__main__":
    # Minimal CLI usage:
    # python tooling/debug_logger.py H1 "file:line" "message" '{"k":"v"}'
    import sys

    h = sys.argv[1] if len(sys.argv) > 1 else "H?"
    loc = sys.argv[2] if len(sys.argv) > 2 else "tooling/debug_logger.py:0"
    msg = sys.argv[3] if len(sys.argv) > 3 else "log"
    data = {}
    if len(sys.argv) > 4:
        try:
            data = json.loads(sys.argv[4])
        except Exception:
            data = {"raw": sys.argv[4]}
    log(h, loc, msg, data)
