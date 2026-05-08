import sys

from libpebble2.services.appmessage import AppMessageService
from pypkjs.runner.websocket import run_tool


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

if __name__ == "__main__":
    sys.exit(run_tool())
