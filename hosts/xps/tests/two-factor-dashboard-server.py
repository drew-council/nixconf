"""Synthetic-only harness: native dashboard/session/RPC, real browser fill JS.

Browser supervisor boundary is redirected to the isolated fixture CDP target;
no vault, model, production browser, credentials, or chat prompts are used.
"""

import json
import os
import threading
import time
from pathlib import Path

from hermes_cli import web_server
from tools import browser_vault_tool
from tui_gateway import server as gateway
from tui_gateway import server_requests
from websockets.sync.client import connect

root = Path(os.environ["FIXTURE_ROOT"])
origin = os.environ["FIXTURE_ORIGIN"]


def evaluate(_task_id, expression):
    with connect(os.environ["FIXTURE_CDP_TARGET"], proxy=None) as ws:
        ws.send(
            json.dumps(
                {
                    "id": 1,
                    "method": "Runtime.evaluate",
                    "params": {
                        "expression": expression,
                        "returnByValue": True,
                    },
                }
            )
        )
        while True:
            frame = json.loads(ws.recv())
            if frame.get("id") == 1:
                assert "exceptionDetails" not in frame.get("result", {})
                return {
                    "success": True,
                    "result": frame["result"]["result"].get("value"),
                }


browser_vault_tool._focus_bound_origin = lambda *args: None
browser_vault_tool._current_page_origin = lambda _task_id: origin
browser_vault_tool._eval_js = evaluate
browser_vault_tool._eval_js_secret = evaluate

# Observe only static contract proof, never save response frames or values.
resolve = server_requests.resolve_response


def observe(frame):
    with gateway._sessions_lock:
        sids = list(gateway._sessions)
    for sid in sids:
        for req in server_requests.open_requests(sid):
            if req["id"] == frame.get("id") and req["method"] == "vault.code":
                result = frame.get("result", {})
                if isinstance(frame.get("id"), str) and set(result) == {
                    "value"
                }:
                    (root / "reply-contract").write_text(
                        "exact-string-id-value-result"
                    )
    return resolve(frame)


server_requests.resolve_response = observe
write = server_requests._write


def observe_emit(frame):
    if frame.get("method") == "vault.code":
        sid = frame["params"]["session_id"]
        peers = gateway._session_live_transports(gateway._sessions[sid])
        # Stdio clients ship with the backend; WS clients must advertise.
        transport = gateway._sessions[sid].get("transport")
        assert transport is not None
        assert not peers or any(
            server_requests.answers_requests(p) for p in peers
        )
        (root / "request-contract").write_text(
            "emitted-after-capability-and-attachment"
        )
    return write(frame)


server_requests._write = observe_emit


def run_fixture(phases=("submit", "cancel", "replay")):
    for phase in phases:
        while not (root / (phase + ".start")).exists():
            time.sleep(0.05)
        while True:
            with gateway._sessions_lock:
                candidates = [
                    (sid, s)
                    for sid, s in gateway._sessions.items()
                    if not s.get("close_on_disconnect")
                ]
            (root / "fixture-stage").write_text(
                "sessions="
                + str(len(gateway._sessions))
                + ";candidates="
                + str(len(candidates))
            )
            if candidates:
                sid, _session = candidates[0]
                if gateway._session_client_answers_requests(sid):
                    break
            time.sleep(0.05)
        # Native callback registration, validation, sinks and routing.
        gateway._wire_callbacks(sid)
        (root / "fixture-stage").write_text("callback-wired")
        result = json.loads(browser_vault_tool.browser_vault_enter_code())
        (root / "fixture-stage").write_text(
            "tool-result:"
            + str(result.get("error_type", result.get("success")))
        )
        if phase.endswith("cancel"):
            assert result.get("error_type") == "code_declined"
        else:
            assert result.get("success") and result.get("filled_fields") == 1
        (root / (phase + ".done")).write_text(
            "code_declined" if phase.endswith("cancel") else "filled_one_field"
        )


if __name__ == "__main__":
    threading.Thread(
        target=run_fixture,
        args=(("ws-submit", "ws-cancel", "ws-replay"),),
        daemon=True,
    ).start()
    web_server.start_server(
        host="127.0.0.1",
        port=int(os.environ["FIXTURE_PORT"]),
        open_browser=False,
    )
else:

    def guarded_fixture():
        try:
            run_fixture()
        except Exception:  # noqa: BLE001 -- record synthetic thread failures
            import traceback

            (root / "fixture-error").write_text(traceback.format_exc())

    threading.Thread(target=guarded_fixture, daemon=True).start()
