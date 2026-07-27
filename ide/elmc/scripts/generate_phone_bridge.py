#!/usr/bin/env python3
"""
Generate a companion bridge from the phone protocol schema.

Outputs:
  1) Elm port module with envelope encoders/decoders
  2) JS dispatch skeleton with API operation registry
"""

import json
import re
import sys
from pathlib import Path


def to_camel(name: str) -> str:
    parts = re.split(r"[^A-Za-z0-9]+", name)
    parts = [p for p in parts if p]
    if not parts:
        return "unknown"
    first = parts[0].lower()
    rest = "".join(p[:1].upper() + p[1:] for p in parts[1:])
    return first + rest


def to_pascal(name: str) -> str:
    c = to_camel(name)
    return c[:1].upper() + c[1:]


def load_schema(path: Path) -> dict:
    data = json.loads(path.read_text())
    required_top = ["version", "channel", "envelopes", "apis"]
    for key in required_top:
        if key not in data:
            raise ValueError(f"missing schema key: {key}")
    if not isinstance(data["apis"], list) or not data["apis"]:
        raise ValueError("schema apis must be a non-empty list")
    return data


def generate_elm(schema: dict, module_name: str) -> str:
    channel = schema["channel"]
    version = schema["version"]

    command_ctors = []
    for api in schema["apis"]:
        api_name = api["name"]
        for op in api.get("ops", []):
            ctor = f"{to_pascal(api_name)}{to_pascal(op)}"
            command_ctors.append((ctor, api_name, op))

    command_type_lines = "\n".join(
        [f"    = {ctor} Encode.Value" if idx == 0 else f"    | {ctor} Encode.Value"
         for idx, (ctor, _, _) in enumerate(command_ctors)]
    )

    encoder_branches = []
    for ctor, api_name, op in command_ctors:
        encoder_branches.append(
            f"""        {ctor} payload ->
            Encode.object
                [ ( "id", Encode.string id )
                , ( "api", Encode.string "{api_name}" )
                , ( "op", Encode.string "{op}" )
                , ( "payload", payload )
                ]"""
        )

    return f"""port module {module_name} exposing
    ( Command(..)
    , Event
    , Error
    , ResultEnvelope
    , decodeEvent
    , decodeResult
    , fromBridge
    , send
    , toBridge
    , version
    )

{{-| AUTO-GENERATED FILE.

Generated from `shared/companion-protocol/phone_bridge_v1.json`.
Channel: `{channel}`
-}}

import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode


port toBridge : Encode.Value -> Cmd msg


port fromBridge : (Decode.Value -> msg) -> Sub msg


type Command
{command_type_lines}


type alias Error =
    {{ type_ : String
    , message : String
    , retryable : Maybe Bool
    }}


type alias ResultEnvelope =
    {{ id : String
    , ok : Bool
    , payload : Maybe Decode.Value
    , error : Maybe Error
    }}


type alias Event =
    {{ event : String
    , payload : Decode.Value
    }}


version : Int
version =
    {version}


send : String -> Command -> Cmd msg
send id command =
    toBridge (encodeCommand id command)


encodeCommand : String -> Command -> Encode.Value
encodeCommand id command =
    case command of
{chr(10).join(encoder_branches)}


decodeResult : Decoder ResultEnvelope
decodeResult =
    Decode.map4 ResultEnvelope
        (Decode.field "id" Decode.string)
        (Decode.field "ok" Decode.bool)
        (Decode.maybe (Decode.field "payload" Decode.value))
        (Decode.maybe (Decode.field "error" decodeError))


decodeError : Decoder Error
decodeError =
    Decode.map3 Error
        (Decode.field "type" Decode.string)
        (Decode.field "message" Decode.string)
        (Decode.maybe (Decode.field "retryable" Decode.bool))


decodeEvent : Decoder Event
decodeEvent =
    Decode.map2 Event
        (Decode.field "event" Decode.string)
        (Decode.field "payload" Decode.value)
"""


def generate_js(schema: dict) -> str:
    channel = schema["channel"]
    version = schema["version"]

    handler_lines = []
    for api in schema["apis"]:
        api_name = api["name"]
        for op in api.get("ops", []):
            key = f"{api_name}.{op}"
            handler_lines.append(f'  "{key}": null,')

    return f"""// AUTO-GENERATED FILE.
// Generated from shared/companion-protocol/phone_bridge_v1.json
// Channel: {channel}

const Bridge = (function () {{
  const VERSION = {version};
  const handlers = {{
{chr(10).join(handler_lines)}
  }};

  function keyFor(command) {{
    return String(command.api || "") + "." + String(command.op || "");
  }}

  function makeError(type, message, retryable) {{
    const error = {{ type: String(type || "unknown"), message: String(message || "") }};
    if (typeof retryable === "boolean") {{
      error.retryable = retryable;
    }}
    return error;
  }}

  function replySuccess(id, payload) {{
    return {{ id, ok: true, payload: payload }};
  }}

  function replyFailure(id, type, message, retryable) {{
    return {{ id, ok: false, error: makeError(type, message, retryable) }};
  }}

  function dispatch(command) {{
    if (!command || typeof command.id !== "string") {{
      return replyFailure("", "invalid_command", "missing command id", false);
    }}

    const key = keyFor(command);
    const handler = handlers[key];

    if (typeof handler !== "function") {{
      return replyFailure(command.id, "unsupported_operation", "No handler for " + key, false);
    }}

    try {{
      const payload = handler(command.payload, command);
      if (payload && typeof payload.then === "function") {{
        return payload
          .then((value) => replySuccess(command.id, value))
          .catch((err) =>
            replyFailure(command.id, "handler_error", err && err.message ? err.message : String(err), true)
          );
      }}

      return replySuccess(command.id, payload === undefined ? null : payload);
    }} catch (err) {{
      return replyFailure(
        command.id,
        "handler_error",
        err && err.message ? err.message : String(err),
        true
      );
    }}
  }}

  function setHandler(api, op, fn) {{
    handlers[String(api) + "." + String(op)] = fn;
  }}

  return {{
    VERSION,
    handlers,
    dispatch,
    setHandler,
    replySuccess,
    replyFailure
  }};
}})();

module.exports = Bridge;
"""


def main() -> int:
    if len(sys.argv) != 4:
        print("usage: generate_phone_bridge.py <schema.json> <out_elm> <out_js>")
        return 1

    schema_path = Path(sys.argv[1])
    out_elm = Path(sys.argv[2])
    out_js = Path(sys.argv[3])

    schema = load_schema(schema_path)
    elm_module = "Pebble.Companion.GeneratedBridge"

    out_elm.parent.mkdir(parents=True, exist_ok=True)
    out_js.parent.mkdir(parents=True, exist_ok=True)
    out_elm.write_text(generate_elm(schema, elm_module))
    out_js.write_text(generate_js(schema))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
