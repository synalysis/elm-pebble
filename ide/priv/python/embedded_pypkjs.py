import json
import io
import os
import struct
import sys
import tempfile
import time
import traceback
import zipfile
from uuid import UUID

from libpebble2.protocol.logs import AppLogMessage, LogDumpShipping, LogMessage, RequestLogs
from libpebble2.services.appmessage import AppMessageService, AppMessageNumber, ByteArray, CString, Int32, Uint32
from pypkjs import javascript
from pypkjs.runner import PebbleManager, Runner
from pypkjs.runner.websocket import run_tool, WebsocketRunner


DEBUG_LOG_PATH = "/home/ape/projects/elm-pebble/.cursor/debug-edf96a.log"
MAX_EARLY_APPMESSAGES = 20
MAX_PENDING_INBOUND_APPMESSAGES = 32
DEBUG_SIMULATOR_KEY_WEATHER_TEMPERATURE_C = 0x454C4D12
DEBUG_SIMULATOR_KEY_WEATHER_CONDITION_WIRE = 0x454C4D13
DEBUG_SIMULATOR_KEY_COMPANION_RESYNC = 0x454C4D14
_inbound_appmessage_original = None
WEATHER_CONDITION_WIRE_CODES = {
    "clear": 1,
    "cloudy": 2,
    "fog": 3,
    "drizzle": 4,
    "rain": 5,
    "snow": 6,
    "showers": 7,
    "storm": 8,
    "unknownweather": 9,
}


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


_pending_companion_js_prefix = None


def weather_trace_enabled():
    return os.environ.get("ELMC_EMULATOR_WEATHER_TRACE", "").lower() in ("1", "true", "yes")


def weather_trace_log(runner, ws, stage, **data):
    if not weather_trace_enabled():
        return

    weather = data.get("weather") if isinstance(data.get("weather"), dict) else None
    temperature_c = None
    condition = None
    if weather:
        temperature_c = weather.get("temperatureC")
        condition = weather.get("condition")
    else:
        temperature_c = data.get("temperatureC")
        condition = data.get("condition")

    parts = ["weather trace [%s]" % stage]
    if temperature_c is not None or condition is not None:
        parts.append("%s°C %s" % (temperature_c if temperature_c is not None else "?", condition or "clear"))
    detail = data.get("detail")
    if detail:
        parts.append(str(detail))
    message = ": ".join(parts[:2]) + ((" (%s)" % detail) if detail else "")
    if runner is not None:
        runner.log_output(message)

    if ws is not None:
        payload = {"stage": stage}
        payload.update(data)
        try:
            encoded = json.dumps(payload, sort_keys=True).encode("utf-8")
            ws.send(bytearray([0x0F]) + encoded)
        except Exception:
            pass


def _companion_settings_apply_source(settings):
    settings_json = json.dumps(settings)
    return (
        "(function(s){"
        "var g=typeof globalThis!=='undefined'?globalThis:this;"
        "g.__elmPebbleCompanionSimulatorSettings=s;"
        "var apply=g.companionApplySimulatorSettings;"
        "if(typeof apply==='function'){apply(s);return;}"
        "if(typeof companionApplySimulatorSettings==='function'){companionApplySimulatorSettings(s);return;}"
        "if(typeof syncCompanionSimulatorSettingsFromGlobal==='function'){syncCompanionSimulatorSettingsFromGlobal();return;}"
        "g.__elmPebblePendingSimulatorSettings=s;"
        "})(" + settings_json + ")"
    )


def apply_settings_to_runner(runner, settings):
    """Apply companion simulator settings on the JS runtime event-loop thread."""
    js = getattr(runner, "js", None)
    if js is None:
        store_pending_simulator_settings(runner, settings)
        return False

    source = _companion_settings_apply_source(settings)

    def do_apply():
        js_now = getattr(runner, "js", None)
        if js_now is None:
            store_pending_simulator_settings(runner, settings)
            return

        context = getattr(js_now, "context", None)
        if context is None or not hasattr(context, "eval"):
            store_pending_simulator_settings(runner, settings)
            return

        try:
            with context:
                context.eval(source)
            remember_simulator_settings(runner, settings)
            pending = getattr(runner, "_elm_pebble_pending_simulator_settings", None)
            if pending == settings:
                del runner._elm_pebble_pending_simulator_settings
        except Exception as exc:
            runner.log_output(
                "Companion simulator settings apply failed: %s: %s"
                % (type(exc).__name__, exc)
            )
            traceback.print_exc()

    js.enqueue(do_apply)
    return True


def store_pending_simulator_settings(runner, settings):
    runner._elm_pebble_pending_simulator_settings = settings
    runner._elm_pebble_last_simulator_settings = settings


def remember_simulator_settings(runner, settings):
    store_pending_simulator_settings(runner, settings)


def prepare_companion_js_prefix(settings):
    global _pending_companion_js_prefix
    _pending_companion_js_prefix = (
        "(function(g,s){"
        "g.__elmPebblePendingSimulatorSettings=s;"
        "g.__elmPebbleCompanionSimulatorSettings=s;"
        "})((typeof globalThis!=='undefined'?globalThis:this),"
        + json.dumps(settings)
        + ");\n"
    )


def decode_companion_cache_install(message):
    body = bytes(message[1:])
    if len(body) >= 5 and body[0] == 0x01:
        settings_len = int.from_bytes(body[1:5], "big")
        end = 5 + settings_len
        if settings_len >= 0 and len(body) >= end:
            settings = None
            try:
                settings = json.loads(body[5:end].decode("utf-8"))
            except Exception:
                settings = None
            return settings, body[end:]
    return None, body


def apply_pending_simulator_settings(runner):
    settings = getattr(runner, "_elm_pebble_pending_simulator_settings", None)
    if not settings:
        return False
    if apply_settings_to_runner(runner, settings):
        schedule_simulator_weather_to_watch(runner, "apply_pending_simulator_settings")
        return True
    return False


def simulator_geolocation_from_settings(settings):
    if not isinstance(settings, dict):
        return None

    lat = settings.get("latitude")
    lon = settings.get("longitude")
    if lat is None or lon is None:
        return None

    try:
        lat_f = float(lat)
        lon_f = float(lon)
    except (TypeError, ValueError):
        return None

    accuracy = settings.get("accuracy")
    if accuracy is None:
        accuracy = settings.get("geolocation_accuracy")
    try:
        accuracy_f = float(accuracy) if accuracy is not None else 1000.0
    except (TypeError, ValueError):
        accuracy_f = 1000.0

    return lon_f, lat_f, accuracy_f


def _simulator_geolocation_coords_for_runner(runner):
    if runner is None:
        return None
    settings = getattr(runner, "_elm_pebble_last_simulator_settings", None)
    if settings is None:
        settings = getattr(runner, "_elm_pebble_pending_simulator_settings", None)
    return simulator_geolocation_from_settings(settings)


def _enqueue_geolocation_success(runtime, success, lon, lat, accuracy):
    """Build STPyV8 position objects on the JS event-loop thread only."""
    from pypkjs.javascript.navigator.geolocation import Coordinates, Position

    def deliver():
        if not callable(success):
            return
        position = Position(
            runtime,
            Coordinates(runtime, lon, lat, accuracy),
            round(time.time() * 1000),
        )
        success(position)

    runtime.enqueue(deliver)


def patch_embedded_geolocation():
    from pypkjs.javascript.navigator.geolocation import Geolocation

    if getattr(Geolocation, "__elm_patched__", False):
        return

    original_get_position = Geolocation._get_position
    original_get_current_position = Geolocation.getCurrentPosition

    def _get_position(self, success, failure):
        coords = _simulator_geolocation_coords_for_runner(
            getattr(self.runtime, "runner", None)
        )
        if coords is not None:
            lon, lat, accuracy = coords
            _enqueue_geolocation_success(self.runtime, success, lon, lat, accuracy)
            return
        return original_get_position(self, success, failure)

    def getCurrentPosition(self, success, failure=None, options=None):
        coords = _simulator_geolocation_coords_for_runner(
            getattr(self.runtime, "runner", None)
        )
        if coords is not None:
            lon, lat, accuracy = coords
            _enqueue_geolocation_success(self.runtime, success, lon, lat, accuracy)
            return 42
        return original_get_current_position(self, success, failure, options)

    _get_position.__elm_patched__ = True
    Geolocation._get_position = _get_position
    Geolocation.getCurrentPosition = getCurrentPosition
    Geolocation.__elm_patched__ = True


def normalize_ws_message(message):
    if isinstance(message, bytearray):
        return message
    if isinstance(message, bytes):
        return bytearray(message)
    return None


_js_lifecycle_lock = None


def _get_js_lifecycle_lock():
    global _js_lifecycle_lock
    if _js_lifecycle_lock is None:
        import gevent.lock

        _js_lifecycle_lock = gevent.lock.RLock()
    return _js_lifecycle_lock


def _phone_pbw_with_js(runner, preferred_uuid=None):
    if preferred_uuid is not None:
        pbw = runner.pbws.get(preferred_uuid)
        if pbw is not None and pbw.src is not None:
            return pbw

    running_uuid = getattr(runner, "running_uuid", None)
    if running_uuid is not None:
        pbw = runner.pbws.get(running_uuid)
        if pbw is not None and pbw.src is not None:
            return pbw

    for pbw in runner.pbws.values():
        if pbw.src is not None:
            return pbw
    return None


def _uuid_from_pbw_bytes(pbw_bytes):
    with zipfile.ZipFile(io.BytesIO(pbw_bytes)) as archive:
        manifest = json.loads(archive.open("appinfo.json").read())
    return UUID(manifest["uuid"])


def runner_has_phone_companion(runner):
    return _phone_pbw_with_js(runner) is not None


def patch_companion_cache_install():
    original_on_message = WebsocketRunner.on_message

    def on_message(runner, ws, message):
        message = normalize_ws_message(message)
        if message is None or len(message) == 0 or message[0] != 0x04:
            return original_on_message(runner, ws, message)

        if runner.requires_auth and not ws.authed:
            return

        embedded_settings, pbw_bytes = decode_companion_cache_install(message)
        settings = embedded_settings
        if settings is None:
            settings = getattr(runner, "_elm_pebble_last_simulator_settings", None)
        if settings is None:
            settings = getattr(runner, "_elm_pebble_pending_simulator_settings", None)
        if settings:
            remember_simulator_settings(runner, settings)
            prepare_companion_js_prefix(settings)

        import gevent

        def go_install():
            import gevent

            ack_ok = bytearray([0x05, 0x00, 0x00, 0x00, 0x00])
            ack_err = bytearray([0x05, 0x00, 0x00, 0x00, 0x01])
            lock = _get_js_lifecycle_lock()

            with lock:
                with tempfile.NamedTemporaryFile() as f:
                    f.write(pbw_bytes)
                    f.flush()

                    try:
                        if getattr(runner, "js", None) is not None:
                            runner.stop_js()
                            gevent.sleep(0.3)

                        runner.log_output(
                            "Companion cache refresh loading PBW (%d bytes)..."
                            % len(pbw_bytes)
                        )
                        preferred_uuid = _uuid_from_pbw_bytes(pbw_bytes)
                        runner.load_pbws([f.name], cache=True, start=False)
                        phone_pbw = _phone_pbw_with_js(runner, preferred_uuid)
                        if phone_pbw is None:
                            raise ValueError("PBW has no pebble-js-app.js (phone companion)")

                        runner.start_js(phone_pbw)
                        apply_pending_simulator_settings(runner)
                        if runner_has_phone_companion(runner):
                            schedule_companion_watch_resync(
                                runner, "companion_cache_refresh"
                            )
                        loaded = [
                            str(app_uuid)
                            for app_uuid, pbw in runner.pbws.items()
                            if pbw.src is not None
                        ]
                        runner.log_output(
                            "Companion cache refreshed; started JS for: %s"
                            % (", ".join(loaded) if loaded else "none")
                        )
                        ws.send(ack_ok)
                        runner.log_output("Companion cache refresh ack sent to IDE")
                    except Exception as exc:
                        runner.log_output(
                            "Companion cache refresh failed: %s: %s"
                            % (type(exc).__name__, exc)
                        )
                        traceback.print_exc()
                        ws.send(ack_err)

        gevent.spawn(go_install)

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
        message = normalize_ws_message(message)
        if message is None or len(message) == 0 or message[0] != 0x0D:
            return original_on_message(runner, ws, message)

        if runner.requires_auth and not ws.authed:
            runner.log_output("Debug AppMessage send skipped: phone bridge not authenticated")
            return

        try:
            payload = json.loads(bytes(message[1:]).decode("utf-8"))
            app_uuid = companion_app_uuid(runner)
            if app_uuid is None and payload.get("uuid"):
                app_uuid = UUID(payload["uuid"])
            if app_uuid is None:
                raise ValueError("No running watch app UUID for debug AppMessage")
            dictionary = {
                int(entry["key"]): appmessage_value(entry)
                for entry in payload.get("entries", [])
            }
            if not dictionary:
                raise ValueError("Debug AppMessage payload has no entries")
            runner.appmessage.send_message(app_uuid, dictionary)
            ws.send(bytearray([0x0D, 0x00]))
        except Exception as exc:
            runner.log_output("Debug AppMessage send failed: %s: %s" % (type(exc).__name__, exc))
            ws.send(bytearray([0x0D, 0x01]))

    WebsocketRunner.on_message = on_message


patch_debug_appmessage_send()


def _plain_wire_value(value):
    import STPyV8 as v8

    if value is None:
        return None
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        return value
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        return value
    if isinstance(value, v8.JSArray):
        return [_plain_wire_value(item) for item in list(value)]
    if isinstance(value, (list, tuple)):
        return [_plain_wire_value(item) for item in value]
    if hasattr(value, "value"):
        try:
            return int(value.value)
        except (TypeError, ValueError):
            pass
    return value


def wire_appmessage_plain_dict(runtime, message):
    """Extract a JSON-safe dict from a JS AppMessage object (stock sendAppMessage shape)."""
    if message is None:
        return None

    if isinstance(message, dict):
        return {str(key): _plain_wire_value(val) for key, val in message.items()}

    plain = {}
    try:
        keys = list(message.keys())
    except Exception:
        keys = []

    for key in keys:
        key_str = str(key)
        try:
            value = message[key_str]
        except (KeyError, TypeError, AttributeError):
            try:
                value = message[key]
            except (KeyError, TypeError, AttributeError):
                continue
        plain[key_str] = _plain_wire_value(value)

    if plain:
        return plain

    if runtime is not None:
        try:
            text = runtime.eval(
                "(function(m){ try { return JSON.stringify(m); } catch (_e) { return ''; } })(message)",
                message=message,
            )
            if isinstance(text, str) and text:
                parsed = json.loads(text)
                if isinstance(parsed, dict) and parsed:
                    return {
                        str(key): _plain_wire_value(val) for key, val in parsed.items()
                    }
        except Exception:
            pass

    return plain


def appmessage_number_value(value):
    if hasattr(value, "value"):
        return int(value.value)
    return int(value)


def weather_condition_wire_code(condition):
    normalized = "".join(ch for ch in str(condition or "clear").lower() if ch.isalnum())
    return WEATHER_CONDITION_WIRE_CODES.get(normalized, WEATHER_CONDITION_WIRE_CODES["clear"])


def simulator_temperature_c(value):
    if value is None or isinstance(value, bool):
        return None

    if isinstance(value, (int, float)):
        return int(round(float(value)))

    if isinstance(value, str):
        stripped = value.strip()
        if not stripped:
            return None
        try:
            return int(round(float(stripped)))
        except ValueError:
            return None

    return None


def simulator_weather_from_settings(settings):
    if not isinstance(settings, dict):
        return None

    weather = settings.get("weather")
    if not isinstance(weather, dict):
        weather = {}

    temperature = weather.get("temperatureC")
    if temperature is None:
        temperature = settings.get("weather_temperatureC")
    condition = weather.get("condition")
    if condition is None:
        condition = settings.get("weather_condition")

    if temperature is None and condition is None:
        return None

    return {
        "temperatureC": temperature,
        "condition": condition or "clear",
        "humidityPercent": weather.get("humidityPercent", settings.get("weather_humidityPercent")),
        "pressureHpa": weather.get("pressureHpa", settings.get("weather_pressureHpa")),
        "windKph": weather.get("windKph", settings.get("weather_windKph")),
        "windDirectionDeg": weather.get("windDirectionDeg", settings.get("weather_windDirectionDeg")),
    }


def companion_app_uuid(runner):
    app_uuid = getattr(runner, "running_uuid", None)
    if app_uuid is not None:
        return app_uuid

    for candidate, pbw in getattr(runner, "pbws", {}).items():
        if pbw.src is not None:
            return candidate

    return None


def simulator_weather_mode_enabled(settings):
    if not isinstance(settings, dict):
        return True
    return settings.get("use_simulator_weather") not in (False, "false")


def send_simulator_weather_to_watch(runner, reason, retry_count=0, ws=None):
    if runner_has_phone_companion(runner):
        weather_trace_log(
            runner,
            ws or getattr(runner, "_elm_pebble_last_ws", None),
            "inject_skipped",
            detail="phone companion handles simulator weather",
            reason=reason,
        )
        return False

    settings = getattr(runner, "_elm_pebble_last_simulator_settings", None)
    if settings is None:
        settings = getattr(runner, "_elm_pebble_pending_simulator_settings", None)
    if not simulator_weather_mode_enabled(settings):
        weather_trace_log(
            runner,
            ws or getattr(runner, "_elm_pebble_last_ws", None),
            "inject_skipped",
            detail="simulator weather disabled; companion uses live weather",
            reason=reason,
        )
        return False
    weather = simulator_weather_from_settings(settings)
    if weather is None:
        weather_trace_log(
            runner,
            ws or getattr(runner, "_elm_pebble_last_ws", None),
            "inject_skipped",
            detail="no weather in settings",
            reason=reason,
        )
        return False

    app_uuid = companion_app_uuid(runner)
    if app_uuid is None:
        weather_trace_log(
            runner,
            ws or getattr(runner, "_elm_pebble_last_ws", None),
            "inject_skipped",
            weather=weather,
            detail="no companion app uuid",
            reason=reason,
        )
        return False

    dictionary = {}
    temperature_c = simulator_temperature_c(weather.get("temperatureC"))
    if temperature_c is not None:
        dictionary[DEBUG_SIMULATOR_KEY_WEATHER_TEMPERATURE_C] = Int32(temperature_c)

    condition = weather.get("condition")
    condition_wire = None
    if condition is not None:
        condition_wire = weather_condition_wire_code(condition)
        dictionary[DEBUG_SIMULATOR_KEY_WEATHER_CONDITION_WIRE] = Int32(condition_wire)

    sent = False
    if dictionary:
        try:
            runner.appmessage.send_message(app_uuid, dictionary)
            sent = True
        except Exception as exc:
            runner.log_output(
                "Simulator weather inject failed: %s: %s" % (type(exc).__name__, exc)
            )
            sent = False

    trace_ws = ws or getattr(runner, "_elm_pebble_last_ws", None)
    if sent:
        weather_trace_log(
            runner,
            trace_ws,
            "inject_sent",
            weather=weather,
            reason=reason,
            conditionWire=condition_wire,
            retryCount=retry_count,
        )
        agent_log(
            "initial",
            "H49",
            "embedded_pypkjs.py:weather:debug_inject",
            "pypkjs sent simulator weather debug AppMessages",
            {
                "reason": reason,
                "temperatureC": temperature_c,
                "temperatureSent": temperature_c is not None,
                "condition": condition,
                "conditionWire": condition_wire,
            },
        )
    elif retry_count < 8:
        weather_trace_log(
            runner,
            trace_ws,
            "inject_retry",
            weather=weather,
            reason=reason,
            retryCount=retry_count + 1,
        )
        import gevent

        delay_seconds = 0.5 * (retry_count + 1)
        gevent.spawn_later(
            delay_seconds,
            send_simulator_weather_to_watch,
            runner,
            reason,
            retry_count + 1,
        )

    return sent


def pending_inbound_appmessages(runner):
    pending = getattr(runner, "_elm_pebble_pending_inbound_appmessages", None)
    if pending is None:
        pending = []
        runner._elm_pebble_pending_inbound_appmessages = pending
    return pending


def pebble_js_runtime(pebble):
    """Return the JSRuntime backing a Pebble JS object (pebble.runtime, not pebble.runtime.js)."""
    runtime = getattr(pebble, "runtime", None)
    if runtime is None or not hasattr(runtime, "enqueue"):
        return None
    return runtime


def companion_js_eval_ready(pebble):
    runtime = pebble_js_runtime(pebble)
    if runtime is None:
        return False

    context = getattr(runtime, "context", None)
    return context is not None and hasattr(context, "eval")


def inbound_plain_dict(dictionary):
    from libpebble2.services.appmessage import ByteArray, CString

    plain = {}
    for key, value in dictionary.items():
        key_int = int(key)
        if isinstance(value, CString):
            plain[key_int] = value.value
        elif isinstance(value, ByteArray):
            plain[key_int] = value.value.decode("utf-8", errors="replace").rstrip("\0")
        elif isinstance(value, (bytes, bytearray)):
            plain[key_int] = bytes(value).decode("utf-8", errors="replace").rstrip("\0")
        elif isinstance(value, str):
            plain[key_int] = value
        else:
            plain[key_int] = appmessage_number_value(value)
    return plain


def _companion_deliver_inbound_js_source(inbound_plain):
    payload_json = json.dumps({str(k): v for k, v in inbound_plain.items()}, sort_keys=True)
    return (
        "(function(p){"
        "var g=typeof globalThis!=='undefined'?globalThis:this;"
        "var fn=g.deliverCompanionWatchInboundFromWire;"
        "if(typeof fn!=='function'&&g.companionGlobalRoot){"
        "fn=g.companionGlobalRoot().deliverCompanionWatchInboundFromWire;"
        "}"
        "if(typeof fn==='function'){fn(p);return;}"
        "console.log('Companion inbound bridge missing deliverCompanionWatchInboundFromWire');"
        "})("
        + payload_json
        + ")"
    )


def deliver_watch_inbound_to_companion_js(pebble, dictionary):
    js = pebble_js_runtime(pebble)
    if js is None:
        return False

    inbound_plain = inbound_plain_dict(dictionary)
    source = _companion_deliver_inbound_js_source(inbound_plain)
    message_tag = inbound_plain.get(10)

    def do_deliver():
        js_now = pebble_js_runtime(pebble)
        if js_now is None:
            return

        context = getattr(js_now, "context", None)
        if context is None or not hasattr(context, "eval"):
            return

        try:
            with context:
                context.eval(source)
            runner = getattr(pebble.runtime, "runner", None)
            if runner is not None:
                runner.log_output(
                    "Companion watch inbound delivered to Elm tag=%s" % message_tag
                )
        except Exception as exc:
            runner = getattr(pebble.runtime, "runner", None)
            if runner is not None:
                runner.log_output(
                    "Companion watch inbound delivery failed tag=%s: %s: %s"
                    % (message_tag, type(exc).__name__, exc)
                )
            traceback.print_exc()

    js.enqueue(do_deliver)
    return True


def flush_pending_inbound_appmessages(runner):
    if not getattr(runner, "js", None):
        return 0

    pending = pending_inbound_appmessages(runner)
    if not pending:
        return 0

    items = list(pending)
    pending.clear()
    replayed = 0

    for pebble, _tid, _uuid, inbound in items:
        if deliver_watch_inbound_to_companion_js(pebble, inbound):
            replayed += 1

    if replayed:
        runner.log_output(
            "Replayed %d inbound AppMessage(s) after companion JS start" % replayed
        )

    return replayed


def send_companion_watch_resync(runner, reason="companion_resync"):
    app_uuid = companion_app_uuid(runner)
    if app_uuid is None:
        return False

    try:
        runner.appmessage.send_message(
            app_uuid, {DEBUG_SIMULATOR_KEY_COMPANION_RESYNC: Int32(1)}
        )
        runner.log_output("Companion watch resync sent (%s)" % reason)
        return True
    except Exception as exc:
        runner.log_output(
            "Companion watch resync failed (%s): %s: %s"
            % (reason, type(exc).__name__, exc)
        )
        return False


def schedule_companion_watch_resync(runner, reason, delays=(2.5,)):
    if getattr(runner, "_elm_companion_resync_scheduled", False):
        return

    runner._elm_companion_resync_scheduled = True
    import gevent

    for delay in delays:

        def fire(delay=delay):
            send_companion_watch_resync(runner, "%s@%.1fs" % (reason, delay))

        gevent.spawn_later(delay, fire)


def _companion_watch_ping_source():
    return (
        "(function(){"
        "var g=typeof globalThis!=='undefined'?globalThis:this;"
        "var fn=g.deliverCompanionWatchPing;"
        "if(typeof fn!=='function'&&g.companionGlobalRoot){"
        "fn=g.companionGlobalRoot().deliverCompanionWatchPing;"
        "}"
        "if(typeof fn==='function'){fn();}"
        "})();"
    )


def deliver_companion_watch_ping(runner, reason="bootstrap"):
    js = getattr(runner, "js", None)
    if js is None:
        return False

    source = _companion_watch_ping_source()

    def do_deliver():
        js_now = getattr(runner, "js", None)
        if js_now is None:
            return

        context = getattr(js_now, "context", None)
        if context is None or not hasattr(context, "eval"):
            return

        try:
            with context:
                context.eval(source)
            runner.log_output("Companion bootstrap watch Ping delivered (%s)" % reason)
        except Exception as exc:
            runner.log_output(
                "Companion bootstrap watch Ping failed (%s): %s: %s"
                % (reason, type(exc).__name__, exc)
            )

    js.enqueue(do_deliver)
    return True


def schedule_companion_watch_ping(runner, reason, delays=(1.0, 2.5)):
    if getattr(runner, "_elm_companion_watch_ping_scheduled", False):
        return

    runner._elm_companion_watch_ping_scheduled = True
    import gevent

    for delay in delays:

        def fire(delay=delay):
            deliver_companion_watch_ping(runner, "%s@%.1fs" % (reason, delay))

        gevent.spawn_later(delay, fire)


def schedule_simulator_weather_to_watch(runner, reason, delay_seconds=0.35, ws=None):
    import gevent

    runner._elm_pebble_weather_inject_reason = reason
    if ws is not None:
        runner._elm_pebble_weather_inject_ws = ws
    existing = getattr(runner, "_elm_pebble_weather_inject_timer", None)
    if existing is not None:
        try:
            existing.kill()
        except Exception:
            pass

    def deliver():
        runner._elm_pebble_weather_inject_timer = None
        pending_reason = getattr(runner, "_elm_pebble_weather_inject_reason", reason)
        pending_ws = getattr(runner, "_elm_pebble_weather_inject_ws", ws)
        send_simulator_weather_to_watch(runner, pending_reason, ws=pending_ws)

    runner._elm_pebble_weather_inject_timer = gevent.spawn_later(delay_seconds, deliver)


def detect_appmessage_key_shift_corruption(dictionary):
    keys = sorted(int(key) for key in dictionary.keys())
    if len(keys) < 2:
        return

    values = [appmessage_number_value(dictionary[key]) for key in keys]
    shifted = all(values[index] == keys[index + 1] for index in range(len(keys) - 1))
    if shifted:
        raise ValueError(
            "AppMessage payload appears corrupted (values match next key ids): "
            + repr(dict(zip(keys, values)))
        )


def build_appmessage_dictionary(plain, app_keys):
    import collections

    import STPyV8 as v8
    from libpebble2.services.appmessage import ByteArray, CString, Int32
    from pypkjs.javascript.pebble import JSRuntimeException

    to_send = {}
    for key, value in plain.items():
        resolved = app_keys[key] if key in app_keys else key
        try:
            to_send[int(resolved)] = value
        except (TypeError, ValueError):
            raise JSRuntimeException("Unknown message key '%s'" % key)

    dictionary = {}
    for key, value in to_send.items():
        if isinstance(value, v8.JSArray):
            value = list(value)
        if isinstance(value, str):
            value = CString(value)
        elif isinstance(value, bool):
            value = Int32(1 if value else 0)
        elif isinstance(value, int):
            value = Int32(value)
        elif isinstance(value, float):
            value = Int32(int(round(value)))
        elif isinstance(value, collections.abc.Sequence):
            data = bytearray()
            for byte in value:
                if isinstance(byte, int) and 0 <= byte <= 255:
                    data.append(byte)
                elif isinstance(byte, str):
                    data.extend(bytearray(byte))
                else:
                    raise JSRuntimeException("Unexpected value in byte array.")
            value = ByteArray(bytes(data))
        elif value is None:
            continue
        else:
            raise JSRuntimeException("Invalid value data type for key %s: %s" % (key, type(value)))
        dictionary[key] = value

    detect_appmessage_key_shift_corruption(dictionary)
    return dictionary


def appmessage_packet_hex(target_app, dictionary, transaction_id):
    from libpebble2.protocol.appmessage import AppMessage, AppMessagePush, AppMessageTuple

    tuples = []
    for key, value in dictionary.items():
        if isinstance(value, AppMessageNumber):
            tuples.append(
                AppMessageTuple(
                    key=int(key),
                    type=value.type,
                    data=struct.pack(
                        AppMessageService._type_mapping[(value.type, value.length)],
                        value.value,
                    ),
                )
            )
        elif isinstance(value, CString):
            tuples.append(
                AppMessageTuple(
                    key=int(key),
                    type=value.type,
                    data=value.value.encode("utf-8") + b"\x00",
                )
            )
        elif isinstance(value, ByteArray):
            tuples.append(
                AppMessageTuple(key=int(key), type=value.type, data=value.value)
            )

    packet = AppMessage(
        transaction_id=transaction_id,
        data=AppMessagePush(uuid=target_app, dictionary=tuples),
    )
    return packet.serialise().hex()


def build_appmessage_tuples(dictionary):
    from libpebble2.protocol.appmessage import AppMessageTuple

    tuples = []
    for key, value in dictionary.items():
        if isinstance(value, AppMessageNumber):
            tuples.append(
                AppMessageTuple(
                    key=int(key),
                    type=value.type,
                    data=struct.pack(
                        AppMessageService._type_mapping[(value.type, value.length)],
                        value.value,
                    ),
                )
            )
        elif isinstance(value, CString):
            tuples.append(
                AppMessageTuple(
                    key=int(key),
                    type=value.type,
                    data=value.value.encode("utf-8") + b"\x00",
                )
            )
        elif isinstance(value, ByteArray):
            tuples.append(
                AppMessageTuple(key=int(key), type=value.type, data=value.value)
            )
    return tuples


def send_single_appmessage_packet(pebble, dictionary, log_payload=None):
    from libpebble2.protocol.appmessage import AppMessagePush

    transaction_id = pebble._appmessage._get_txid()
    if log_payload is not None:
        log_payload["transactionId"] = transaction_id
        log_payload["packetHex"] = appmessage_packet_hex(
            pebble.uuid, dictionary, transaction_id
        )
    message_obj = pebble._appmessage._message_type(transaction_id=transaction_id)
    message_obj.data = AppMessagePush(
        uuid=pebble.uuid, dictionary=build_appmessage_tuples(dictionary)
    )
    pebble._appmessage._pending_messages[transaction_id] = pebble.uuid
    pebble._appmessage._pebble.send_packet(message_obj)
    return transaction_id


def send_wire_appmessage(pebble, message):
    from pypkjs.javascript.pebble import JSRuntimeException

    plain = wire_appmessage_plain_dict(pebble.runtime, message)
    if not plain:
        raise JSRuntimeException(
            "Failed to serialize AppMessage payload (no keys: %s)"
            % type(message).__name__
        )

    dictionary = build_appmessage_dictionary(plain, pebble.app_keys)
    log_payload = {
        "plain": plain,
        "dictionary": {
            str(key): appmessage_number_value(value) for key, value in dictionary.items()
        },
        "split": False,
    }
    transaction_id = send_single_appmessage_packet(pebble, dictionary, log_payload)
    agent_log(
        "initial",
        "H47,H48,H50",
        "embedded_pypkjs.py:appmessage:send_wire",
        "pypkjs sending wire AppMessage dictionary",
        log_payload,
    )
    return transaction_id


def companion_wire_message_tag(plain):
    if not isinstance(plain, dict):
        return None

    for key in ("message_tag", "10", 10):
        if key in plain:
            return plain[key]

    return None


def patch_pebble_send_appmessage():
    """Route companion JS sendAppMessage through the wire encoder with visible logging."""
    from pypkjs.javascript.pebble import JSRuntimeException, Pebble

    if getattr(Pebble.sendAppMessage, "__elm_patched__", False):
        return

    def sendAppMessage(self, message, success=None, failure=None):
        self._check_ready()
        runner = getattr(self.runtime, "runner", None)
        plain = None
        try:
            plain = wire_appmessage_plain_dict(self.runtime, message)
            tid = send_wire_appmessage(self, message)
            self.pending_acks[tid] = (success, failure)
            if runner is not None:
                runner.log_output(
                    "Companion phone→watch AppMessage sent tag=%s tid=%s keys=%s"
                    % (
                        companion_wire_message_tag(plain),
                        tid,
                        sorted(str(k) for k in plain.keys()) if plain else [],
                    )
                )
        except Exception as exc:
            if runner is not None:
                runner.log_output(
                    "Companion phone→watch AppMessage failed tag=%s: %s: %s"
                    % (companion_wire_message_tag(plain), type(exc).__name__, exc)
                )
            if callable(failure):
                self.runtime.enqueue(failure, exc)
            else:
                raise JSRuntimeException(str(exc))

    sendAppMessage.__elm_patched__ = True
    Pebble.sendAppMessage = sendAppMessage


patch_pebble_send_appmessage()


def patch_pebble_appmessage_acks():
    """Deliver AppMessage ACK/NACK handling on the JS runtime queue."""
    from pypkjs.javascript.pebble import Pebble

    if getattr(Pebble._handle_response, "__elm_patched__", False):
        return

    original_handle_response = Pebble._handle_response

    def _handle_response(self, tid, did_succeed):
        def deliver():
            original_handle_response(self, tid, did_succeed)

        self.runtime.enqueue(deliver)

    _handle_response.__elm_patched__ = True
    Pebble._handle_response = _handle_response


patch_pebble_appmessage_acks()


def patch_pebble_inbound_appmessage():
    """Deliver watch→phone AppMessages on the JS runtime queue (STPyV8 is not thread-safe)."""
    global _inbound_appmessage_original
    from pypkjs.javascript.pebble import Pebble

    if getattr(Pebble._handle_message, "__elm_patched__", False):
        return

    original_handle_message = Pebble._handle_message
    _inbound_appmessage_original = original_handle_message

    def queue_inbound_appmessage(pebble, tid, uuid, inbound):
        runner = getattr(pebble.runtime, "runner", None)
        if runner is None:
            return False

        pending = pending_inbound_appmessages(runner)
        pending.append((pebble, tid, uuid, inbound))

        while len(pending) > MAX_PENDING_INBOUND_APPMESSAGES:
            pending.pop(0)

        return True

    def _handle_message(self, tid, uuid, dictionary):
        runner = getattr(self.runtime, "runner", None)

        if uuid != self.uuid:
            running_uuid = getattr(runner, "running_uuid", None) if runner is not None else None
            if running_uuid is not None and uuid == running_uuid:
                if runner is not None:
                    runner.log_output(
                        "Companion rebinding watch AppMessage uuid %s (js had %s)"
                        % (uuid, self.uuid)
                    )
                self.uuid = uuid
            else:
                if runner is not None:
                    runner.log_output(
                        "Discarded watch AppMessage for %s (companion js uuid %s running %s)"
                        % (uuid, self.uuid, running_uuid)
                    )
                return

        inbound = inbound_plain_dict(dictionary)
        message_tag = inbound.get(10)
        if message_tag is not None and runner is not None:
            runner.log_output("Watch companion AppMessage tag=%s" % message_tag)

        if not companion_js_eval_ready(self):
            if queue_inbound_appmessage(self, tid, uuid, inbound):
                return
            return

        def deliver():
            if not companion_js_eval_ready(self):
                queue_inbound_appmessage(self, tid, uuid, inbound)
                return
            deliver_watch_inbound_to_companion_js(self, inbound)

        self.runtime.enqueue(deliver)

    _handle_message.__elm_patched__ = True
    Pebble._handle_message = _handle_message


patch_pebble_inbound_appmessage()


def patch_simulator_settings():
    original_on_message = WebsocketRunner.on_message

    def on_message(runner, ws, message):
        message = normalize_ws_message(message)
        if message is None or len(message) == 0 or message[0] != 0x0E:
            return original_on_message(runner, ws, message)

        if runner.requires_auth and not ws.authed:
            runner.log_output("Simulator settings apply skipped: phone bridge not authenticated")
            return

        runner._elm_pebble_last_ws = ws

        try:
            settings = json.loads(bytes(message[1:]).decode("utf-8"))
        except Exception as exc:
            runner.log_output("Simulator settings apply failed: %s: %s" % (type(exc).__name__, exc))
            weather_trace_log(runner, ws, "settings_failed", detail=str(exc))
            ws.send(bytearray([0x0E, 0x01]))
            return

        remember_simulator_settings(runner, settings)
        weather = simulator_weather_from_settings(settings)
        weather_trace_log(runner, ws, "settings_received", weather=weather)
        ws.send(bytearray([0x0E, 0x00]))

        import gevent

        def go_apply():
            applied = apply_settings_to_runner(runner, settings)
            weather_trace_log(
                runner,
                ws,
                "settings_applied" if applied else "settings_pending",
                weather=weather,
                detail="js apply ok" if applied else "js apply deferred",
            )
            if not applied:
                store_pending_simulator_settings(runner, settings)
            send_simulator_weather_to_watch(runner, "simulator_settings_update", ws=ws)
            schedule_simulator_weather_to_watch(
                runner, "simulator_settings_update_retry", delay_seconds=0.8, ws=ws
            )

        gevent.spawn(go_apply)

    WebsocketRunner.on_message = on_message


patch_simulator_settings()


def patch_xhr_progress_event():
    from pypkjs.javascript import xhr as xhr_module

    original_trigger = xhr_module.XMLHttpRequest._trigger_async_event

    def safe_trigger_async_event(self, event_name, event=None, event_params=(), params=()):
        def go():
            try:
                if event is not None:
                    self.triggerEvent(event_name, event(*event_params), *params)
                else:
                    self.triggerEvent(event_name, *params)
            except AttributeError:
                try:
                    self.triggerEvent(event_name, *params)
                except Exception:
                    pass
            except Exception:
                pass

        if self._async:
            go()
        else:
            self._runtime.enqueue(go)

    xhr_module.XMLHttpRequest._trigger_async_event = safe_trigger_async_event


patch_xhr_progress_event()


def patch_js_runtime_eval():
    try:
        from pypkjs.javascript import runtime as runtime_module
    except Exception:
        return

    js_runtime = getattr(runtime_module, "JSRuntime", None)
    if js_runtime is None:
        return

    original_eval = getattr(js_runtime, "eval", None)
    if original_eval is None:
        return

    def eval_with_pending_prefix(self, source):
        return original_eval(self, source)

    js_runtime.eval = eval_with_pending_prefix


patch_js_runtime_eval()


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
        with _get_js_lifecycle_lock():
            global _pending_companion_js_prefix
            settings = getattr(runner, "_elm_pebble_pending_simulator_settings", None)
            if settings is None:
                settings = getattr(runner, "_elm_pebble_last_simulator_settings", None)
            if settings:
                prepare_companion_js_prefix(settings)
            else:
                _pending_companion_js_prefix = None
            # region agent log
            agent_log("initial", "H34,H35", "embedded_pypkjs.py:runner:start_js", "pypkjs starting js runtime", {
                "uuid": str(pbw.uuid),
                "has_js": pbw.src is not None,
                "js_bytes": len(pbw.src) if pbw.src is not None else 0,
            })
            # endregion
            result = original_start_js(runner, pbw)
            flush_pending_inbound_appmessages(runner)
            if runner_has_phone_companion(runner):
                schedule_companion_watch_resync(runner, "start_js")
            schedule_simulator_weather_to_watch(runner, "start_js", delay_seconds=2.0)
            return result

    def stop_js(runner):
        with _get_js_lifecycle_lock():
            runner._elm_companion_resync_scheduled = False
            runner._elm_companion_watch_ping_scheduled = False
            # region agent log
            agent_log("initial", "H37", "embedded_pypkjs.py:runner:stop_js", "pypkjs stopping js runtime", {
                "running_uuid": str(runner.running_uuid) if runner.running_uuid else None,
                "has_js_runtime": runner.js is not None,
            })
            # endregion
            return original_stop_js(runner)

    def run_js(runtime, source):
        global _pending_companion_js_prefix
        if _pending_companion_js_prefix and source is not None:
            source = _pending_companion_js_prefix + source
            _pending_companion_js_prefix = None
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
patch_embedded_geolocation()


def patch_pebble_manager_connect_retry():
    """QEMU can be slow to answer WatchVersion right after boot or PBW install."""
    try:
        from libpebble2.exceptions import TimeoutError as PebbleTimeoutError
        from pypkjs.runner.pebble_manager import PebbleManager
    except Exception:
        return

    original_connect = PebbleManager.connect

    def connect_with_retry(self):
        delays = (0.0, 0.75, 1.5, 3.0, 5.0)
        last_error = None

        for delay in delays:
            if delay:
                time.sleep(delay)
            try:
                return original_connect(self)
            except PebbleTimeoutError as exc:
                last_error = exc

        if last_error is not None:
            raise last_error

        return original_connect(self)

    PebbleManager.connect = connect_with_retry


patch_pebble_manager_connect_retry()


if __name__ == "__main__":
    sys.exit(run_tool())
