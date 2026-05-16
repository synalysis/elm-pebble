defmodule IdeWeb.WasmEmulatorController do
  use IdeWeb, :controller

  alias Ide.Emulator.PBW
  alias Ide.Emulator.PebbleProtocol.CRC32
  alias Ide.Emulator.PebbleProtocol.Packets
  alias Ide.Projects
  alias Ide.Screenshots
  alias Ide.WasmEmulator
  alias IdeWeb.WorkspaceLive.BuildFlow

  @spec status(term(), term()) :: term()
  def status(conn, _params) do
    json(conn, WasmEmulator.status())
  end

  @spec page(term(), term()) :: term()
  def page(conn, _params) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_content_type("text/html")
    |> send_resp(200, page_html())
  end

  @spec asset(term(), term()) :: term()
  def asset(conn, %{"path" => parts}) when is_list(parts) do
    rel_path = Path.join(parts)

    case WasmEmulator.asset_path(rel_path) do
      {:ok, path} ->
        conn
        |> put_resp_header("cache-control", "no-store")
        |> put_resp_header("content-type", WasmEmulator.content_type(path))
        |> send_file(200, path)

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "WASM emulator asset not found"})

      {:error, reason} ->
        conn |> put_status(:bad_request) |> json(%{error: inspect(reason)})
    end
  end

  @spec package(term(), term()) :: term()
  def package(conn, %{"slug" => slug} = params) do
    platform = Map.get(params, "platform", "emery")

    with project when not is_nil(project) <- Projects.get_project_by_slug(slug),
         workspace_root <- Projects.project_workspace_path(project),
         {:ok, packaged} <-
           BuildFlow.package_for_emulator_session(project, workspace_root, platform),
         true <- File.regular?(packaged.artifact_path) do
      send_download(conn, {:file, packaged.artifact_path},
        filename: Path.basename(packaged.artifact_path),
        content_type: "application/octet-stream"
      )
    else
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      false ->
        conn |> put_status(:not_found) |> json(%{error: "PBW artifact not found"})

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
    end
  end

  @spec install_plan(term(), term()) :: term()
  def install_plan(conn, %{"slug" => slug} = params) do
    platform = Map.get(params, "platform", "emery")
    firmware = Map.get(params, "firmware", "sdk")

    with project when not is_nil(project) <- Projects.get_project_by_slug(slug),
         workspace_root <- Projects.project_workspace_path(project),
         {:ok, packaged} <-
           BuildFlow.package_for_emulator_session(project, workspace_root, platform),
         {:ok, pbw} <- PBW.load(packaged.artifact_path, platform) do
      json(conn, build_install_plan(pbw, firmware))
    else
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
    end
  end

  @spec screenshot(term(), term()) :: term()
  def screenshot(conn, %{"slug" => slug, "image" => image} = params) do
    emulator_target = Map.get(params, "platform", "wasm")

    with project when not is_nil(project) <- Projects.get_project_by_slug(slug),
         {:ok, png} <- decode_png_data_url(image),
         {:ok, shot} <- Screenshots.store_png(project.slug, emulator_target, png) do
      json(conn, %{status: "ok", screenshot: shot})
    else
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
    end
  end

  def screenshot(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{error: "Expected image data URL"})
  end

  defp decode_png_data_url("data:image/png;base64," <> encoded) do
    Base.decode64(encoded)
  end

  defp decode_png_data_url(_), do: {:error, :invalid_data_url}

  defp build_install_plan(pbw, firmware) do
    sdk_limit = firmware_sdk_limit(firmware)
    app_metadata = compatible_app_metadata(pbw.app_metadata, sdk_limit)

    blob_token = 0x454C
    delete_blob_token = 0x454D
    {_endpoint, blob_payload} = Packets.blob_insert_app(blob_token, app_metadata)
    {_endpoint, delete_blob_payload} = Packets.blob_delete_app(delete_blob_token, pbw.uuid)
    {_endpoint, start_payload} = Packets.app_run_state_start(pbw.uuid)

    %{
      uuid: pbw.uuid,
      platform: pbw.platform,
      variant: pbw.variant,
      blob_insert_frame: packet_base64(Packets.endpoint(:blob_db), blob_payload),
      blob_delete_frame: packet_base64(Packets.endpoint(:blob_db), delete_blob_payload),
      app_start_frame: packet_base64(Packets.endpoint(:app_run_state), start_payload),
      parts:
        pbw.parts
        |> Enum.sort_by(&install_part_order/1)
        |> Enum.map(fn part ->
          data = compatible_part_data(part, sdk_limit)

          %{
            kind: Atom.to_string(part.kind),
            name: part.name,
            object_type: Packets.object_type(part.object_type),
            size: part.size,
            crc: CRC32.stm32(data),
            data: Base.encode64(data)
          }
        end)
    }
  end

  defp firmware_sdk_limit("full"), do: {5, 86}
  defp firmware_sdk_limit(_), do: nil

  defp compatible_app_metadata(metadata, nil), do: metadata

  defp compatible_app_metadata(
         %{sdk_version_major: major, sdk_version_minor: minor} = metadata,
         {major, max_minor}
       )
       when minor > max_minor do
    %{metadata | sdk_version_minor: max_minor}
  end

  defp compatible_app_metadata(metadata, _sdk_limit), do: metadata

  defp compatible_part_data(%{kind: :binary, data: data}, {major, max_minor})
       when byte_size(data) >= 12 do
    case data do
      <<prefix::binary-size(10), ^major, minor, rest::binary>> when minor > max_minor ->
        <<prefix::binary, major, max_minor, rest::binary>>

      _ ->
        data
    end
  end

  defp compatible_part_data(part, _sdk_limit), do: part.data

  defp packet_base64(endpoint, payload) do
    {endpoint, payload}
    |> Packets.frame()
    |> Base.encode64()
  end

  defp install_part_order(%{kind: :binary}), do: 0
  defp install_part_order(%{kind: :resources}), do: 1
  defp install_part_order(%{kind: :worker}), do: 2
  defp install_part_order(_part), do: 3

  defp page_html do
    """
    <!doctype html>
    <html>
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Pebble WASM Emulator</title>
        <style>
          html, body { margin: 0; min-height: 100%; background: #020617; color: #e2e8f0; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
          body { display: flex; align-items: center; justify-content: center; padding: 0; }
          #status, #progress, #console { display: none !important; }
          #progress > div { width: 0%; height: 100%; background: #38bdf8; transition: width 0.2s; }
          canvas { width: 200px; height: 228px; border-radius: 0.75rem; border: 1px solid #334155; image-rendering: pixelated; background: #000; }
        </style>
      </head>
      <body>
        <div id="status">Waiting for launch...</div>
        <div id="progress"><div></div></div>
        <canvas id="canvas" width="200" height="228"></canvas>
        <pre id="console"></pre>
        <script>
          const ASSET_BASE = "/wasm-emulator/assets/";
          const ASSET_VERSION = String(Date.now());
          const statusEl = document.getElementById("status");
          const consoleEl = document.getElementById("console");
          const progressEl = document.getElementById("progress");
          const progressFill = progressEl.firstElementChild;
          const canvas = document.getElementById("canvas");
          const canvasCtx = canvas.getContext("2d");
          let runtimeReady = false;
          let booted = false;
          let lastFrameCount = 0;
          let buttonState = 0;
          let buttonStateAddr = 0;
          let cachedImgData = null;
          let cachedWidth = 0;
          let cachedHeight = 0;
          let lastProgressStatusAt = 0;
          let watchReady = false;
          let installActive = false;
          let qemuBluetoothConnected = false;
          const buttons = {back: 1 << 0, up: 1 << 1, select: 1 << 2, down: 1 << 3};

          function post(type, payload = {}) { parent.postMessage({source: "elm-pebble-wasm-emulator", type, ...payload}, window.location.origin); }
          function log(message) { consoleEl.textContent = `${new Date().toLocaleTimeString()} ${message}\\n${consoleEl.textContent}`.slice(0, 50000); post("log", {message}); }
          function setStatus(message) { statusEl.textContent = message; post("status", {message}); }
          function setInstallProgress(label, percent) { post("progress", {label, percent}); }
          function showProgress(pct) { progressEl.style.display = "block"; progressFill.style.width = `${pct}%`; }
          function hideProgress() { progressEl.style.display = "none"; }
          function setProgressStatus(message) {
            statusEl.textContent = message;
            const now = performance.now();
            if (now - lastProgressStatusAt > 500) {
              lastProgressStatusAt = now;
              post("status", {message});
            }
          }

          function dumpDebugSerial(label = "debug serial") {
            if (!window.Module?.FS) return;
            try {
              const data = Module.FS.readFile("/tmp/pebble_serial.log");
              const decoded = decodeDebugSerial(data);
              if (decoded.length > 0) {
                log(`${label} decoded tail:\\n${decoded.slice(-40).join("\\n")}`);
              }
            } catch (_error) {
              // The file is created lazily by QEMU once the firmware writes debug serial output.
            }
          }

          function decodeDebugSerial(bytes) {
            const strings = [];
            let current = [];
            const flush = () => {
              if (current.length >= 4) strings.push(new TextDecoder().decode(new Uint8Array(current)));
              current = [];
            };
            for (const byte of bytes) {
              if (byte >= 0x20 && byte <= 0x7e) {
                current.push(byte);
              } else {
                flush();
              }
            }
            flush();
            return strings
              .map(value => value.trim())
              .filter(value => value.length >= 4)
              .filter((value, index, all) => index === 0 || value !== all[index - 1]);
          }

          async function fetchWithProgress(url, label, expectedSize) {
            const response = await fetch(`${url}?v=${ASSET_VERSION}`, {cache: "no-store"});
            if (!response.ok) throw new Error(`${label}: HTTP ${response.status}`);
            const reader = response.body.getReader();
            const total = parseInt(response.headers.get("content-length") || "", 10) || expectedSize;
            let received = 0;
            const chunks = [];
            while (true) {
              const result = await reader.read();
              if (result.done) break;
              chunks.push(result.value);
              received += result.value.length;
              if (total) showProgress(Math.round((received / total) * 100));
              setProgressStatus(`${label}... ${Math.round(received / 1024)}KB`);
            }
            hideProgress();
            setStatus(`${label} loaded (${Math.round(received / 1024)}KB)`);
            const data = new Uint8Array(received);
            let offset = 0;
            chunks.forEach(chunk => { data.set(chunk, offset); offset += chunk.length; });
            return data;
          }

          async function fetchJSON(url) {
            const response = await fetch(`${url}?v=${ASSET_VERSION}`, {cache: "no-store"});
            if (!response.ok) throw new Error(`${url}: HTTP ${response.status}`);
            return await response.json();
          }

          function firmwareVariantName(firmware) {
            const parts = String(firmware || "").split("/");
            return parts[0] || "sdk";
          }

          async function firmwareManifest(fwBase, firmware) {
            try {
              return await fetchJSON(`${fwBase}manifest.json`);
            } catch (error) {
              if (firmwareVariantName(firmware) === "full") {
                return {
                  platform: "emery",
                  machine: "pebble-snowy-emery-bb",
                  spi_flash_size: null,
                  manifest: "fallback"
                };
              }
              throw error;
            }
          }

          function normalizeFlashImage(data, expectedSize, label) {
            if (!expectedSize || data.length === expectedSize) return data;
            if (data.length > expectedSize) {
              log(`${label}: using first ${Math.round(expectedSize / 1024)}KB of ${Math.round(data.length / 1024)}KB SDK image`);
              return data.slice(0, expectedSize);
            }
            throw new Error(`${label}: expected ${expectedSize} bytes, got ${data.length}`);
          }

          function qemuArgsForFirmware(manifest) {
            const platform = manifest.platform || "basalt";
            const machine = manifest.machine || "pebble-snowy-bb";
            const cpu = manifest.cpu || (platform === "aplite" ? "cortex-m3" : "cortex-m4");
            const storage = manifest.storage || (["aplite", "diorite", "flint"].includes(platform) ? "mtdblock" : "pflash");
            const storageArgs = storage === "mtdblock" ?
              ["-mtdblock", "/firmware/qemu_spi_flash.bin"] :
              ["-drive", "if=none,id=spi-flash,file=/firmware/qemu_spi_flash.bin,format=raw"];

            return [
              "-machine", machine,
              "-accel", "tcg,thread=single",
              "-cpu", cpu,
              "-display", "none",
              "-monitor", "none",
              "-parallel", "none",
              "-kernel", "/firmware/qemu_micro_flash.bin",
              ...storageArgs,
              "-serial", "null",
              "-serial", "null",
              "-serial", "file:/tmp/pebble_serial.log"
            ];
          }

          async function boot(firmware = "sdk") {
            if (booted) return;
            booted = true;
            try {
              if (!crossOriginIsolated) throw new Error("Page is not cross-origin isolated; SharedArrayBuffer is unavailable.");
              const fwBase = `${ASSET_BASE}firmware/${firmware}/`;
              const manifest = await firmwareManifest(fwBase, firmware);
              const spiSize = Object.prototype.hasOwnProperty.call(manifest, "spi_flash_size") ? manifest.spi_flash_size : 16777216;
              const micro = await fetchWithProgress(`${fwBase}qemu_micro_flash.bin`, "Micro flash", 968704);
              const spi = normalizeFlashImage(
                await fetchWithProgress(`${fwBase}qemu_spi_flash.bin`, "SPI flash", spiSize),
                spiSize,
                "SPI flash"
              );
              window.Module = {
                canvas,
                noInitialRun: false,
                arguments: qemuArgsForFirmware(manifest),
                print: text => log(text),
                printErr: text => { if (text && !/write 0x|read 0x|DMA:|guest_errors|unsupported syscall|^DEBUG:|^\\[fps\\]/.test(text)) log(`[err] ${text}`); },
                locateFile: path => `${ASSET_BASE}${path}?v=${ASSET_VERSION}`,
                preRun: [() => {
                  try { FS.mkdir("/firmware"); } catch (_e) {}
                  try { FS.mkdir("/tmp"); } catch (_e) {}
                  ENV.TZ_OFFSET_SEC = String(-new Date().getTimezoneOffset() * 60);
                  FS.writeFile("/firmware/qemu_micro_flash.bin", micro);
                  FS.writeFile("/firmware/qemu_spi_flash.bin", spi);
                }],
                onRuntimeInitialized: () => {
                  runtimeReady = true;
                  setStatus("QEMU runtime initialized; booting Pebble firmware...");
                  setTimeout(pumpPhoneServices, 100);
                  post("ready");
                }
              };
              setStatus("Loading QEMU WASM module...");
              const script = document.createElement("script");
              script.src = `${ASSET_BASE}qemu-system-arm.js?v=${ASSET_VERSION}`;
              script.onload = () => log("qemu-system-arm.js loaded");
              script.onerror = event => {
                booted = false;
                console.error("Failed to load qemu-system-arm.js", event);
                setStatus("Failed to load qemu-system-arm.js. Check the browser console and /wasm-emulator/assets/qemu-system-arm.js.");
              };
              document.body.appendChild(script);
            } catch (error) {
              booted = false;
              setStatus(`Error: ${error.message}`);
            }
          }

          function updateButtons(name, pressed) {
            const bit = buttons[name];
            if (!bit) return;
            buttonState = pressed ? (buttonState | bit) : (buttonState & ~bit);
            if (!runtimeReady || !window.Module) return;
            if (!buttonStateAddr && Module._pebble_button_state_addr) {
              const addr = Module._pebble_button_state_addr();
              if (addr) buttonStateAddr = addr >> 2;
            }
            if (buttonStateAddr) Atomics.store(Module.HEAPU32, buttonStateAddr, buttonState);
          }

          function b64ToBytes(value) {
            const binary = atob(value || "");
            const bytes = new Uint8Array(binary.length);
            for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
            return bytes;
          }

          function u32be(value) {
            const out = new Uint8Array(4);
            new DataView(out.buffer).setUint32(0, value >>> 0, false);
            return out;
          }

          function concatBytes(parts) {
            const length = parts.reduce((sum, part) => sum + part.length, 0);
            const out = new Uint8Array(length);
            let offset = 0;
            parts.forEach(part => { out.set(part, offset); offset += part.length; });
            return out;
          }

          function pebbleFrame(endpoint, payload) {
            const out = new Uint8Array(4 + payload.length);
            const view = new DataView(out.buffer);
            view.setUint16(0, payload.length, false);
            view.setUint16(2, endpoint, false);
            out.set(payload, 4);
            return out;
          }

          function qemuPacket(protocol, payload) {
            const out = new Uint8Array(8 + payload.length);
            const view = new DataView(out.buffer);
            view.setUint16(0, 0xfeed, false);
            view.setUint16(2, protocol, false);
            view.setUint16(4, payload.length, false);
            out.set(payload, 6);
            view.setUint16(6 + payload.length, 0xbeef, false);
            return out;
          }

          function qemuSppPacket(payload) {
            return qemuPacket(1, payload);
          }

          function decodePebbleFrame(raw) {
            if (raw.length < 4) return null;
            const view = new DataView(raw.buffer, raw.byteOffset, raw.byteLength);
            const length = view.getUint16(0, false);
            if (raw.length < 4 + length) return null;
            return {endpoint: view.getUint16(2, false), payload: raw.slice(4, 4 + length)};
          }

          function endpointName(endpoint) {
            return {
              0x000b: "Time",
              0x0010: "WatchVersion",
              0x0011: "PhoneVersion",
              0x0020: "MusicControl",
              0x0030: "AppMessage",
              0x0034: "AppRunState",
              0x07d1: "PingPong",
              0x07d2: "Logs",
              0x07d6: "AppLog",
              0x0bb8: "Screenshot",
              0x1771: "AppFetch",
              0x1a7a: "DataLogging",
              0xb1db: "BlobDB",
              0xbeef: "PutBytes"
            }[endpoint] || "Unknown";
          }

          function qemuProtocolName(protocol) {
            return {
              0x0001: "SPP",
              0x0002: "Button",
              0x0003: "BluetoothConnection",
              0x0005: "Battery",
              0x0009: "TimeFormat",
              0x000a: "TimelinePeek"
            }[protocol] || "Unknown";
          }

          function blobStatusName(status) {
            return {
              0x01: "Success",
              0x02: "GeneralFailure",
              0x03: "InvalidOperation",
              0x04: "InvalidDatabaseID",
              0x05: "InvalidData",
              0x06: "KeyDoesNotExist",
              0x07: "DatabaseFull",
              0x08: "DataStale",
              0x09: "NotSupported",
              0x0a: "Locked",
              0x0b: "TryLater"
            }[status] || "Unknown";
          }

          function blobResponse(frame) {
            if (frame.endpoint !== 0xb1db || frame.payload.length < 3) return null;
            const view = new DataView(frame.payload.buffer, frame.payload.byteOffset, frame.payload.byteLength);
            const token = view.getUint16(0, true);
            const status = frame.payload[2];
            return {token, status, name: blobStatusName(status), ok: status === 0x01};
          }

          function hardwarePlatformName(hardware) {
            return {
              0x07: "basalt",
              0x08: "basalt",
              0x0a: "basalt",
              0x09: "chalk",
              0x0b: "chalk",
              0x0c: "diorite",
              0x0d: "emery",
              0x0e: "diorite",
              0x0f: "flint",
              0x10: "emery",
              0x11: "emery",
              0x12: "emery",
              0x13: "gabbro",
              0x14: "gabbro",
              0xfd: "basalt",
              0xfc: "basalt",
              0xfb: "chalk",
              0xfa: "diorite",
              0xf9: "emery",
              0xf8: "diorite",
              0xf7: "emery",
              0xf6: "flint",
              0xf5: "emery",
              0xf4: "emery",
              0xf3: "emery",
              0xf2: "gabbro"
            }[hardware] || "unknown";
          }

          function payloadHex(payload, limit = 24) {
            const bytes = Array.from(payload.slice(0, limit));
            const suffix = payload.length > limit ? "..." : "";
            return bytes.map(byte => byte.toString(16).padStart(2, "0")).join("") + suffix;
          }

          function uuidFromBytes(bytes) {
            if (bytes.length !== 16) return payloadHex(bytes);
            const hex = Array.from(bytes).map(byte => byte.toString(16).padStart(2, "0"));
            return `${hex.slice(0, 4).join("")}-${hex.slice(4, 6).join("")}-${hex.slice(6, 8).join("")}-${hex.slice(8, 10).join("")}-${hex.slice(10).join("")}`;
          }

          function describeDataLoggingPayload(payload) {
            if (payload.length < 29) return `dataLogging payloadPrefix=${payloadHex(payload)}`;
            const view = new DataView(payload.buffer, payload.byteOffset, payload.byteLength);
            return [
              `dataLogging command=${payload[0]}`,
              `session=${payload[1]}`,
              `uuid=${uuidFromBytes(payload.slice(2, 18))}`,
              `timestamp=${view.getUint32(18, true)}`,
              `tag=0x${view.getUint32(22, true).toString(16).padStart(8, "0")}`,
              `itemType=${payload[26]}`,
              `itemSize=${view.getUint16(27, true)}`
            ].join(" ");
          }

          function cString(bytes) {
            const end = bytes.indexOf(0);
            const view = end >= 0 ? bytes.slice(0, end) : bytes;
            return new TextDecoder().decode(view);
          }

          function appLogLevelName(level) {
            return {
              1: "error",
              2: "warning",
              3: "info",
              50: "warning",
              100: "info"
            }[level] || `level=${level}`;
          }

          function describeAppLogPayload(payload) {
            if (payload.length >= 40) {
              const view = new DataView(payload.buffer, payload.byteOffset, payload.byteLength);
              const level = appLogLevelName(payload[20]);
              const messageLength = payload[21];
              const line = view.getUint16(22, false);
              const filename = cString(payload.slice(24, 40));
              const message = cString(payload.slice(40, 40 + messageLength));
              const source = filename ? `${filename}:${line}` : `line=${line}`;
              return `AppLog ${level} ${source}: ${message || payloadHex(payload)}`;
            }

            return `AppLog: ${payloadHex(payload)}`;
          }

          function describeWatchVersionPayload(payload) {
            if (payload.length < 48 || payload[0] !== 0x01) return "";
            const hardware = payload[46];
            const platform = hardwarePlatformName(hardware);
            const version = cString(payload.slice(5, 37));
            post("watch-info", {platform, hardware, version});
            return ` watchVersion version=${version} hardware=0x${hardware.toString(16).padStart(2, "0")} platform=${platform}`;
          }

          function traceFrame(direction, frame) {
            if (frame.endpoint === 0x07d6) {
              const message = `${direction} ${describeAppLogPayload(frame.payload)}`;
              log(message);
              return;
            }

            const extra =
              frame.endpoint === 0x1a7a ? ` ${describeDataLoggingPayload(frame.payload)}` :
              frame.endpoint === 0x0010 ? describeWatchVersionPayload(frame.payload) :
              "";
            log(`pebble-protocol ${direction} endpoint=${frame.endpoint} name=${endpointName(frame.endpoint)} len=${frame.payload.length} payload=${payloadHex(frame.payload)}${extra}`);
          }

          function controlBridge() {
            if (typeof Module.pebbleControlSend === "function" && typeof Module.pebbleControlRecv === "function") {
              return Module;
            }
            const wasmSend = Module._pebble_control_wasm_send || window._pebble_control_wasm_send;
            const wasmRecv = Module._pebble_control_wasm_recv || window._pebble_control_wasm_recv;
            const malloc = Module._malloc || window._malloc;
            const free = Module._free || window._free;
            if (typeof wasmSend === "function" &&
                typeof wasmRecv === "function" &&
                typeof malloc === "function" &&
                typeof free === "function") {
              Module.pebbleControlSend = bytes => {
                const ptr = malloc(bytes.length);
                try {
                  Module.HEAPU8.set(bytes, ptr);
                  const written = wasmSend(ptr, bytes.length);
                  if (written !== bytes.length) throw new Error(`Control bridge accepted ${written}/${bytes.length} bytes`);
                } finally {
                  free(ptr);
                }
              };
              Module.pebbleControlRecv = () => {
                const capacity = 4096;
                const ptr = malloc(capacity);
                try {
                  const count = wasmRecv(ptr, capacity);
                  if (count <= 0) return null;
                  return Module.HEAPU8.slice(ptr, ptr + count);
                } finally {
                  free(ptr);
                }
              };
              return Module;
            }
            throw new Error("This qemu-system-arm.js does not expose the Pebble control UART bridge. Build the local patched runtime with runtime_bridge/build_patched_runtime.sh.");
          }

          function sendPebbleFrame(frame) {
            const decoded = decodePebbleFrame(frame);
            if (decoded) traceFrame("host->watch", decoded);
            controlBridge().pebbleControlSend(qemuSppPacket(frame));
          }

          function sendQemuPacket(protocol, payload) {
            log(`qemu-control host->watch protocol=${protocol} name=${qemuProtocolName(protocol)} len=${payload.length} payload=${payloadHex(payload)}`);
            controlBridge().pebbleControlSend(qemuPacket(protocol, payload));
          }

          function enableAppLogs() {
            try {
              sendPebbleFrame(pebbleFrame(0x07d6, new Uint8Array([1])));
              log("requested watch AppLog shipping");
            } catch (error) {
              log(`could not request watch AppLog shipping: ${error.message}`);
            }
          }

          function maybeRespondToPhoneService(frame) {
            if (frame.endpoint === 0x0011 && frame.payload[0] === 0x00) {
              const response = new Uint8Array([
                0x01,
                0xff, 0xff, 0xff, 0xff,
                0x00, 0x00, 0x00, 0x00,
                0x00, 0x00, 0x00, 0x02,
                0x02, 0x04, 0x01, 0x01,
                0xaf, 0x29, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
              ]);
              sendPebbleFrame(pebbleFrame(0x0011, response));
              return true;
            }

            if (frame.endpoint === 0x000b && frame.payload[0] === 0x00) {
              const now = Math.floor(Date.now() / 1000);
              sendPebbleFrame(pebbleFrame(0x000b, concatBytes([new Uint8Array([0x01]), u32be(now)])));
              return true;
            }

            if (frame.endpoint === 0x0020 && frame.payload[0] === 0x08) {
              // MusicControl "get current track"; report an empty paused player.
              sendPebbleFrame(pebbleFrame(0x0020, new Uint8Array([0x10, 0x00, 0x00, 0x00])));
              sendPebbleFrame(pebbleFrame(0x0020, new Uint8Array([0x11, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x01])));
              return true;
            }

            if (frame.endpoint === 0x07d1 && frame.payload[0] === 0x00 && frame.payload.length >= 5) {
              sendPebbleFrame(pebbleFrame(0x07d1, concatBytes([new Uint8Array([0x01]), frame.payload.slice(1, 5)])));
              return true;
            }

            if (frame.endpoint === 0x1a7a && [0x01, 0x02, 0x03, 0x07].includes(frame.payload[0]) && frame.payload.length >= 2) {
              sendPebbleFrame(pebbleFrame(0x1a7a, new Uint8Array([0x85, frame.payload[1]])));
              return true;
            }

            return false;
          }

          function recvPebbleFrames() {
            const bridge = controlBridge();
            const packets = bridge.pebbleControlRecv();
            if (!packets) return [];
            const list = Array.isArray(packets) ? packets : [packets];
            return list.flatMap(packet => {
              const bytes = packet instanceof Uint8Array ? packet : new Uint8Array(packet);
              if (bytes.length < 8) return [];
              const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
              if (view.getUint16(0, false) !== 0xfeed || view.getUint16(bytes.length - 2, false) !== 0xbeef) return [];
              const protocol = view.getUint16(2, false);
              if (protocol !== 1) {
                const length = view.getUint16(4, false);
                const payload = bytes.slice(6, 6 + length);
                log(`qemu-control watch->host protocol=${protocol} name=${qemuProtocolName(protocol)} len=${payload.length} payload=${payloadHex(payload)}`);
                return [];
              }
              const length = view.getUint16(4, false);
              const frame = decodePebbleFrame(bytes.slice(6, 6 + length));
              if (frame) traceFrame("watch->host", frame);
              if (frame) maybeRespondToPhoneService(frame);
              return frame ? [frame] : [];
            });
          }

          function pumpPhoneServices() {
            if (!runtimeReady || !window.Module) return;
            if (!installActive) {
              try {
                recvPebbleFrames();
              } catch (error) {
                log(`phone-service pump stopped: ${error.message}`);
                return;
              }
            }
            setTimeout(pumpPhoneServices, 100);
          }

          function frameSummary(frame) {
            return `${frame.endpoint}:${endpointName(frame.endpoint)}:${payloadHex(frame.payload, 12)}`;
          }

          function waitForFrame(matcher, timeoutMs, label = "Pebble protocol response") {
            const startedAt = Date.now();
            const observed = [];
            return new Promise((resolve, reject) => {
              const check = () => {
                try {
                  const frames = recvPebbleFrames();
                  frames.forEach(frame => observed.push(frameSummary(frame)));
                  const match = frames.find(matcher);
                  if (match) {
                    resolve(match);
                  } else if (Date.now() - startedAt >= timeoutMs) {
                    const suffix = observed.length ? `; observed ${observed.slice(-8).join(", ")}` : "; no Pebble frames observed";
                    reject(new Error(`Timed out waiting for ${label}${suffix}`));
                  } else {
                    setTimeout(check, 25);
                  }
                } catch (error) {
                  reject(error);
                }
              };
              check();
            });
          }

          function putbytesPayload(op, cookie, rest = new Uint8Array(0)) {
            return concatBytes([new Uint8Array([op]), u32be(cookie), rest]);
          }

          function putbytesAck(frame) {
            if (frame.endpoint !== 0xbeef || frame.payload.length < 5) return null;
            const cookie = new DataView(frame.payload.buffer, frame.payload.byteOffset, frame.payload.byteLength).getUint32(1, false);
            return {ok: frame.payload[0] === 1, cookie};
          }

          async function sendAndAwait(frame, matcher, timeoutMs = 10000) {
            sendPebbleFrame(frame);
            return await waitForFrame(matcher, timeoutMs);
          }

          function delay(ms) {
            return new Promise(resolve => setTimeout(resolve, ms));
          }

          const PUTBYTES_CHUNK_SIZE = 200;
          const PUTBYTES_CHUNK_DELAY_MS = 25;

          async function ensureWatchReady() {
            if (watchReady) return;
            setStatus("Preparing watch protocol services...");
            setInstallProgress("Preparing watch protocol", 10);

            await sendAndAwait(
              pebbleFrame(0x0010, new Uint8Array([0x00])),
              frame => frame.endpoint === 0x0010,
              15000
            );

            if (!qemuBluetoothConnected) {
              sendQemuPacket(0x0003, new Uint8Array([0x01]));
              qemuBluetoothConnected = true;
            }

            const settleUntil = Date.now() + 1500;
            while (Date.now() < settleUntil) {
              recvPebbleFrames();
              await delay(100);
            }

            watchReady = true;
          }

          async function requestAppFetch(startFrame) {
            setStatus("Requesting app fetch...");
            setInstallProgress("Waiting for watch app-fetch request", 25);
            sendPebbleFrame(startFrame);

            return await waitForFrame(frame => frame.endpoint === 6001, 30000, "AppFetch request");
          }

          async function writeBlobMetadata(insertFrame, deleteFrame, label) {
            let insertResponse = await sendAndAwait(insertFrame, frame => frame.endpoint === 0xb1db, 30000);
            let insert = blobResponse(insertResponse);
            if (!insert?.ok && deleteFrame) {
              log(`BlobDB ${label} insert returned ${insert?.name || "unknown"}; deleting any stale app metadata and retrying`);
              const deleteResponse = await sendAndAwait(deleteFrame, frame => frame.endpoint === 0xb1db, 30000);
              const deleted = blobResponse(deleteResponse);
              if (deleted && ![0x01, 0x06].includes(deleted.status)) {
                throw new Error(`BlobDB app metadata delete failed: ${deleted.name}`);
              }
              insertResponse = await sendAndAwait(insertFrame, frame => frame.endpoint === 0xb1db, 30000);
              insert = blobResponse(insertResponse);
            }
            if (!insert?.ok) throw new Error(`BlobDB ${label} insert failed: ${insert?.name || "unknown"}`);
          }

          async function installPart(part, appId, finalPart) {
            setStatus(`Installing ${part.kind} (${Math.round(part.size / 1024)}KB)...`);
            setInstallProgress(`Starting ${part.kind}`, 35);
            const init = concatBytes([new Uint8Array([1]), u32be(part.size), new Uint8Array([part.object_type | 0x80]), u32be(appId)]);
            const initResponse = await sendAndAwait(pebbleFrame(0xbeef, init), frame => frame.endpoint === 0xbeef);
            const initAck = putbytesAck(initResponse);
            if (!initAck?.ok) throw new Error(`PutBytes init failed for ${part.kind}`);
            const cookie = initAck.cookie;
            await delay(PUTBYTES_CHUNK_DELAY_MS);
            const data = b64ToBytes(part.data);
            for (let offset = 0; offset < data.length; offset += PUTBYTES_CHUNK_SIZE) {
              const chunk = data.slice(offset, Math.min(offset + PUTBYTES_CHUNK_SIZE, data.length));
              setInstallProgress(`Sending ${part.kind}`, 40 + Math.round((offset / Math.max(data.length, 1)) * 35));
              const put = concatBytes([putbytesPayload(2, cookie), u32be(chunk.length), chunk]);
              const putResponse = await sendAndAwait(pebbleFrame(0xbeef, put), frame => frame.endpoint === 0xbeef, 30000);
              const putAck = putbytesAck(putResponse);
              if (!putAck?.ok || putAck.cookie !== cookie) throw new Error(`PutBytes chunk failed for ${part.kind}`);
              await delay(PUTBYTES_CHUNK_DELAY_MS);
            }
            const commit = putbytesPayload(3, cookie, u32be(part.crc));
            setInstallProgress(`Committing ${part.kind}`, 80);
            const commitResponse = await sendAndAwait(pebbleFrame(0xbeef, commit), frame => frame.endpoint === 0xbeef);
            const commitAck = putbytesAck(commitResponse);
            if (!commitAck?.ok || commitAck.cookie !== cookie) throw new Error(`PutBytes commit failed for ${part.kind}`);
            try {
              setInstallProgress(`Installing ${part.kind}`, finalPart ? 90 : 85);
              const installResponse = await sendAndAwait(pebbleFrame(0xbeef, putbytesPayload(5, cookie)), frame => frame.endpoint === 0xbeef, finalPart ? 120000 : 30000);
              const installAck = putbytesAck(installResponse);
              const installCookieOk = installAck?.cookie === cookie || (finalPart && installAck?.cookie === 0);
              if (!installAck?.ok || !installCookieOk) throw new Error(`PutBytes install failed for ${part.kind}`);
            } catch (error) {
              if (finalPart) throw error;
              log(`Continuing after ${part.kind} transition install timeout`);
            }
          }

          async function installPbw(plan) {
            if (!runtimeReady || !window.Module) {
              throw new Error("Boot the WASM emulator before installing a PBW.");
            }
            if (typeof Module.pebbleInstallPbw === "function") {
              return await Module.pebbleInstallPbw(plan);
            }
            try {
              controlBridge();
              installActive = true;
              await ensureWatchReady();
              setStatus("Writing app metadata to BlobDB...");
              setInstallProgress("Writing metadata", 15);
              const blobFrame = b64ToBytes(plan.blob_insert_frame);
              const deleteFrame = plan.blob_delete_frame ? b64ToBytes(plan.blob_delete_frame) : null;
              await writeBlobMetadata(blobFrame, deleteFrame, "app metadata");
              setInstallProgress("Metadata accepted", 20);
              await delay(1500);
              const startFrame = b64ToBytes(plan.app_start_frame);
              const fetchFrame = await requestAppFetch(startFrame);
              if (fetchFrame.payload[0] !== 1) throw new Error("Unexpected app fetch response");
              const appId = new DataView(fetchFrame.payload.buffer, fetchFrame.payload.byteOffset, fetchFrame.payload.byteLength).getUint32(17, true);
              const appIdSource = "watch";
              setInstallProgress("Watch requested app payload", 30);
              for (let index = 0; index < plan.parts.length; index += 1) {
                await installPart(plan.parts[index], appId, index === plan.parts.length - 1);
              }
              setInstallProgress("Install complete", 100);
              enableAppLogs();
              return {uuid: plan.uuid, appId, appIdSource, parts: plan.parts.map(part => part.kind)};
            } finally {
              installActive = false;
            }
          }

          function renderLoop() {
            if (runtimeReady && window.Module?._pebble_display_frame_count) {
              try {
                const frameCount = Module._pebble_display_frame_count();
                if (frameCount !== lastFrameCount) {
                  lastFrameCount = frameCount;
                  const width = Module._pebble_display_width();
                  const height = Module._pebble_display_height();
                  const stride = Module._pebble_display_stride();
                  const dataPtr = Module._pebble_display_data();
                  if (dataPtr && width && height) {
                    canvas.width = width;
                    canvas.height = height;
                    if (!cachedImgData || cachedWidth !== width || cachedHeight !== height) {
                      cachedImgData = canvasCtx.createImageData(width, height);
                      cachedWidth = width;
                      cachedHeight = height;
                    }
                    const dst32 = new Uint32Array(cachedImgData.data.buffer);
                    const heap = Module.HEAPU8;
                    for (let y = 0; y < height; y += 1) {
                      const rowSrc = dataPtr + y * stride;
                      const rowDst = y * width;
                      for (let x = 0; x < width; x += 1) {
                        const s = rowSrc + x * 4;
                        dst32[rowDst + x] = heap[s + 2] | (heap[s + 1] << 8) | (heap[s] << 16) | 0xFF000000;
                      }
                    }
                    canvasCtx.putImageData(cachedImgData, 0, 0);
                  }
                }
              } catch (_error) {}
            }
            requestAnimationFrame(renderLoop);
          }
          requestAnimationFrame(renderLoop);

          window.addEventListener("message", event => {
            if (event.origin !== window.location.origin) return;
            const msg = event.data || {};
            if (msg.type === "launch") boot(msg.firmware || "sdk");
            if (msg.type === "button") updateButtons(msg.name, !!msg.pressed);
            if (msg.type === "qemuControl") sendQemuPacket(msg.protocol, new Uint8Array(msg.payload || []));
            if (msg.type === "screenshot") post("screenshot", {image: canvas.toDataURL("image/png")});
            if (msg.type === "installPbw") {
              installPbw(msg.plan)
                .then(result => post("install-ok", {result}))
                .catch(error => {
                  dumpDebugSerial("install failure debug serial");
                  post("install-error", {error: error.message});
                });
            }
          });
          post("loaded", {isolated: crossOriginIsolated});
        </script>
      </body>
    </html>
    """
  end
end
