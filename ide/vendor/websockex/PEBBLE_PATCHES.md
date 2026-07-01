# Pebble IDE vendored patches (websockex 0.5.1)

## `lib/websockex/conn.ex` — `decode_response/1`

OTP `:erlang.decode_packet/3` can return `{:ok, {:http_error, Reason}, Rest}` when the
upstream sends non-HTTP data during a WebSocket handshake (for example QEMU kernel log lines
while pypkjs is not ready during PBW install). Upstream websockex only handled
`{:http_response, ...}` and `{:error, ...}`, so the missing clause raised `CaseClauseError`
inside the connect `Task` and tore down the phone proxy.

We map `{:http_error, reason}` to `{:error, %WebSockex.RequestError{code: 0, message: ...}}`
so connect fails gracefully and `EmulatorProxyClient` can notify its owner.

## `lib/websockex/frame.ex` — bitstring `size/1` pin operator

Elixir 1.19+ warns when a variable bound outside a match is used in `bytes-size(var)` on
the **match** side without the pin operator (`^var`). Payload-length extractions in
`parse_frame/1` and `parse_text_payload/3` use `^len` / `^size`. Binary **construction**
in `encode_frame/1` keeps `binary-size(len)` (pin is invalid there).
