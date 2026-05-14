import json
import sys
import tempfile
import time
import traceback
from uuid import UUID

from libpebble2.protocol.logs import AppLogMessage, LogDumpShipping, LogMessage, RequestLogs
from libpebble2.services.appmessage import AppMessageService, CString, Int32, Uint32
from pypkjs import javascript
from pypkjs.runner import PebbleManager, Runner
from pypkjs.runner.websocket import run_tool, WebsocketRunner


DEBUG_LOG_PATH = "/home/ape/projects/elm-pebble/.cursor/debug-edf96a.log"
MAX_EARLY_APPMESSAGES = 20


def agent_log(run_id, hypothesis_id, location, message, data=None):
    payload = {
        "sessionId": "edf96a",
        "runId": run_id,
        "hypothesisId": hypothesis_id,
        "location": location,
        "message": message,
        "data": data or {},
        "timestamp": int(time.time() * 1000),
    }
    try:
        with open(DEBUG_LOG_PATH, "a", encoding="utf-8") as f:
            f.write(json.dumps(payload, sort_keys=True) + "\n")
    except Exception:
        pass


def patch_early_appmessage_replay():
    original_broadcast_event = AppMessageService._broadcast_event
    original_register_handler = AppMessageService.register_handler

    def has_handlers(service, event):
        handler = getattr(service, "_EventSourceMixin__handler", None)
        handlers = getattr(handler, "_handlers", {}) if handler is not None else {}
        return bool(handlers.get(event))

    def broadcast_event(service, event, *args):
        if event == "appmessage" and not has_handlers(service, event):
            pending = getattr(service, "_elm_pebble_pending_appmessages", [])
            pending.append(args)
            service._elm_pebble_pending_appmessages = pending[-MAX_EARLY_APPMESSAGES:]

        return original_broadcast_event(service, event, *args)

    def register_handler(service, event, handler):
        handle = original_register_handler(service, event, handler)

        if event == "appmessage":
            pending = getattr(service, "_elm_pebble_pending_appmessages", [])
            service._elm_pebble_pending_appmessages = []
            for args in pending:
                handler(*args)

        return handle

    AppMessageService._broadcast_event = broadcast_event
    AppMessageService.register_handler = register_handler


patch_early_appmessage_replay()


def patch_companion_cache_install():
    original_on_message = WebsocketRunner.on_message

    def on_message(runner, ws, message):
        if not isinstance(message, (bytearray, bytes)) or len(message) == 0 or message[0] != 0x04:
            return original_on_message(runner, ws, message)

        if runner.requires_auth and not ws.authed:
            return

        with tempfile.NamedTemporaryFile() as f:
            f.write(bytes(message[1:]))
            f.flush()

            try:
                runner.load_pbws([f.name], cache=True)
                ws.send(bytearray([0x05, 0x00, 0x00, 0x00, 0x00]))
            except Exception as exc:
                runner.log_output("Companion cache refresh failed: %s: %s" % (type(exc).__name__, exc))
                ws.send(bytearray([0x05, 0x00, 0x00, 0x00, 0x01]))

    WebsocketRunner.on_message = on_message


patch_companion_cache_install()


def patch_debug_appmessage_send():
    original_on_message = WebsocketRunner.on_message

    def appmessage_value(entry):
        value_type = entry.get("type")
        value = entry.get("value")

        if value_type == "string":
            return CString(str(value or ""))
        if value_type == "int":
            return Int32(int(value or 0))
        return Uint32(int(value or 0))

    def on_message(runner, ws, message):
        if not isinstance(message, (bytearray, bytes)) or len(message) == 0 or message[0] != 0x0D:
            return original_on_message(runner, ws, message)

        if runner.requires_auth and not ws.authed:
            return

        try:
            payload = json.loads(bytes(message[1:]).decode("utf-8"))
            app_uuid = UUID(payload["uuid"])
            dictionary = {
                int(entry["key"]): appmessage_value(entry)
                for entry in payload.get("entries", [])
            }
            runner.appmessage.send_message(app_uuid, dictionary)
            ws.send(bytearray([0x0D, 0x00]))
        except Exception as exc:
            runner.log_output("Debug AppMessage send failed: %s: %s" % (type(exc).__name__, exc))
            ws.send(bytearray([0x0D, 0x01]))

    WebsocketRunner.on_message = on_message


patch_debug_appmessage_send()


def patch_runner_lifecycle_logging():
    original_register_endpoints = PebbleManager.register_endpoints
    original_handle_start = Runner.handle_start
    original_handle_stop = Runner.handle_stop
    original_start_js = Runner.start_js
    original_stop_js = Runner.stop_js
    original_run = javascript.runtime.JSRuntime.run

    def register_endpoints(manager):
        result = original_register_endpoints(manager)

        def handle_app_log(packet):
            # region agent log
            agent_log("initial", "H38", "embedded_pypkjs.py:logs:app_log", "pypkjs received AppLogMessage", {
                "uuid": str(packet.uuid),
                "level": int(packet.level),
                "line": int(packet.line_number),
                "filename": str(packet.filename),
                "message": str(packet.message),
            })
            # endregion

        def handle_log_dump(packet):
            payload = packet.data
            data = {"command": int(packet.command), "payload_type": type(payload).__name__}
            if isinstance(payload, LogMessage):
                data.update({
                    "level": int(payload.level),
                    "line": int(payload.line),
                    "filename": str(payload.filename),
                    "message": str(payload.message),
                    "cookie": int(payload.cookie),
                })
            elif hasattr(payload, "cookie"):
                data["cookie"] = int(payload.cookie)
            # region agent log
            agent_log("initial", "H38,H39", "embedded_pypkjs.py:logs:dump", "pypkjs received log dump packet", data)
            # endregion

        try:
            manager.pebble.register_endpoint(AppLogMessage, handle_app_log)
            manager.pebble.register_endpoint(LogDumpShipping, handle_log_dump)
        except Exception as exc:
            # region agent log
            agent_log("initial", "H38", "embedded_pypkjs.py:logs:register_error", "pypkjs failed to register log endpoints", {
                "error_type": type(exc).__name__,
                "error": str(exc),
            })
            # endregion

        return result

    def request_log_dump(runner, reason):
        try:
            cookie = int(time.time() * 1000) & 0xFFFFFFFF
            runner.pebble.pebble.send_packet(LogDumpShipping(data=RequestLogs(generation=0, cookie=cookie)))
            # region agent log
            agent_log("initial", "H39", "embedded_pypkjs.py:logs:request_dump", "pypkjs requested log dump", {
                "reason": reason,
                "cookie": cookie,
            })
            # endregion
        except Exception as exc:
            # region agent log
            agent_log("initial", "H39", "embedded_pypkjs.py:logs:request_error", "pypkjs log dump request failed", {
                "reason": reason,
                "error_type": type(exc).__name__,
                "error": str(exc),
            })
            # endregion

    def handle_start(runner, uuid):
        pbw = runner.pbws.get(uuid)
        # region agent log
        agent_log("initial", "H34,H35", "embedded_pypkjs.py:runner:handle_start", "pypkjs received app start", {
            "uuid": str(uuid),
            "known": pbw is not None,
            "has_js": bool(pbw and pbw.src is not None),
            "loaded_apps": [str(app_uuid) for app_uuid in runner.pbws.keys()],
        })
        # endregion
        return original_handle_start(runner, uuid)

    def handle_stop(runner, uuid):
        if str(uuid) in [str(app_uuid) for app_uuid in runner.pbws.keys()]:
            request_log_dump(runner, "known_app_stop")
        # region agent log
        agent_log("initial", "H35,H37", "embedded_pypkjs.py:runner:handle_stop", "pypkjs received app stop", {
            "uuid": str(uuid),
            "running_uuid": str(runner.running_uuid) if runner.running_uuid else None,
            "has_js_runtime": runner.js is not None,
        })
        # endregion
        return original_handle_stop(runner, uuid)

    def start_js(runner, pbw):
        # region agent log
        agent_log("initial", "H34,H35", "embedded_pypkjs.py:runner:start_js", "pypkjs starting js runtime", {
            "uuid": str(pbw.uuid),
            "has_js": pbw.src is not None,
            "js_bytes": len(pbw.src) if pbw.src is not None else 0,
        })
        # endregion
        return original_start_js(runner, pbw)

    def stop_js(runner):
        # region agent log
        agent_log("initial", "H37", "embedded_pypkjs.py:runner:stop_js", "pypkjs stopping js runtime", {
            "running_uuid": str(runner.running_uuid) if runner.running_uuid else None,
            "has_js_runtime": runner.js is not None,
        })
        # endregion
        return original_stop_js(runner)

    def run_js(runtime, source):
        # region agent log
        agent_log("initial", "H35,H36", "embedded_pypkjs.py:js:run_start", "pypkjs js runtime run started", {
            "source_bytes": len(source) if source is not None else 0,
        })
        # endregion
        try:
            result = original_run(runtime, source)
            # region agent log
            agent_log("initial", "H35,H36", "embedded_pypkjs.py:js:run_exit", "pypkjs js runtime run exited", {
                "result": repr(result),
            })
            # endregion
            return result
        except Exception as exc:
            # region agent log
            agent_log("initial", "H35", "embedded_pypkjs.py:js:run_exception", "pypkjs js runtime raised", {
                "error_type": type(exc).__name__,
                "error": str(exc),
                "traceback": traceback.format_exc(limit=8),
            })
            # endregion
            raise

    PebbleManager.register_endpoints = register_endpoints
    Runner.handle_start = handle_start
    Runner.handle_stop = handle_stop
    Runner.start_js = start_js
    Runner.stop_js = stop_js
    javascript.runtime.JSRuntime.run = run_js


patch_runner_lifecycle_logging()


if __name__ == "__main__":
    sys.exit(run_tool())
