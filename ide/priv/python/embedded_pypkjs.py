import json
import sys
from uuid import UUID

from libpebble2.services.appmessage import AppMessageService, CString, Int32, Uint32
from pypkjs.runner.websocket import run_tool, WebsocketRunner


MAX_EARLY_APPMESSAGES = 20


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

if __name__ == "__main__":
    sys.exit(run_tool())
