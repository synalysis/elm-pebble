/**
 * Browser File API runtime for elmc WASM web builds.
 */

export function createFileRuntime(deps) {
  const {
    RC_SUCCESS,
    allocHandle,
    readHandle,
    writeOut,
    stringValue,
    newList,
    newStringHandle,
    newIntHandle,
    cmdNoneHandle,
    writeTaskSucceed,
    unitValue,
    TAG_RECORD,
    TAG_STRING,
    TAG_LIST,
    TAG_BYTES,
    TAG_CMD,
    TAG_CLOSURE,
    dispatchPlatformMsg,
    invokeClosure,
    retain,
    addOwner,
    handles,
  } = deps;

  const ownChild = (childPtr, ownerPtr) => {
    const child = childPtr | 0;
    if (child && handles?.has(child)) {
      retain?.(null, child);
      addOwner?.(child, ownerPtr);
    }
  };

  const acceptFromPtr = (ptr) => {
    const payload = readHandle(ptr | 0);
    if (!payload) return "";
    if (payload.tag === TAG_LIST && Array.isArray(payload.items)) {
      return payload.items
        .map((item) => stringValue(item | 0))
        .filter(Boolean)
        .join(",");
    }
    return stringValue(ptr | 0) || "";
  };

  const fileHandleFromNative = (file) => {
    if (!file) return 0;
    return allocHandle({
      tag: TAG_RECORD,
      elmFile: true,
      nativeFile: file,
      fields: [
        newStringHandle(file.name || ""),
        newStringHandle(file.type || ""),
        newIntHandle(file.size | 0),
        newIntHandle(file.lastModified | 0),
      ],
    });
  };

  const nativeFileFrom = (ptr) => {
    const payload = readHandle(ptr | 0);
    return payload?.nativeFile || null;
  };

  const fieldOr = (filePtr, index, makeFallback) => {
    const payload = readHandle(filePtr | 0);
    const field = payload?.fields?.[index];
    if (field) return field | 0;
    return makeFallback();
  };

  const blobPartsFromContent = (contentPtr) => {
    const payload = readHandle(contentPtr | 0);
    if (payload?.tag === TAG_BYTES && payload.view) {
      return [payload.view];
    }
    return [stringValue(contentPtr | 0) || ""];
  };

  const runBlobDownload = (name, mime, parts) => {
    if (typeof document === "undefined") return;
    const blob = new Blob(parts, { type: mime || "application/octet-stream" });
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement("a");
    anchor.href = url;
    anchor.download = name || "download";
    anchor.click();
    URL.revokeObjectURL(url);
  };

  const runStringDownload = (name, mime, content) => {
    runBlobDownload(name, mime || "text/plain", [content]);
  };

  const writeSelectCmd = (outPtr, toMsgPtr, acceptPtr, multiple) => {
    const handle = allocHandle({
      tag: TAG_CMD,
      kind: multiple ? "file_select_files" : "file_select",
      toMsg: toMsgPtr | 0,
      accept: acceptFromPtr(acceptPtr),
      multiple: Boolean(multiple),
    });
    ownChild(toMsgPtr, handle);
    writeOut(outPtr, handle);
    return RC_SUCCESS;
  };

  const fileSelect = (outPtr, toMsgPtr, acceptPtr) =>
    writeSelectCmd(outPtr, toMsgPtr, acceptPtr, false);

  const fileSelectFiles = (outPtr, toMsgPtr, acceptPtr) =>
    writeSelectCmd(outPtr, toMsgPtr, acceptPtr, true);

  const fileDownload = (outPtr, namePtr, mimePtr, contentPtr) => {
    const handle = allocHandle({
      tag: TAG_CMD,
      kind: "file_download",
      name: namePtr | 0,
      mime: mimePtr | 0,
      content: contentPtr | 0,
    });
    ownChild(namePtr, handle);
    ownChild(mimePtr, handle);
    ownChild(contentPtr, handle);
    writeOut(outPtr, handle);
    return RC_SUCCESS;
  };

  const fileDownloadUrl = (outPtr, hrefPtr) => {
    const handle = allocHandle({
      tag: TAG_CMD,
      kind: "file_download_url",
      href: hrefPtr | 0,
    });
    ownChild(hrefPtr, handle);
    writeOut(outPtr, handle);
    return RC_SUCCESS;
  };

  const fileDownloadTask = (outPtr, namePtr, mimePtr, contentPtr) => {
    runBlobDownload(
      stringValue(namePtr | 0) || "download.txt",
      stringValue(mimePtr | 0) || "text/plain",
      blobPartsFromContent(contentPtr)
    );
    return writeTaskSucceed(outPtr, unitValue());
  };

  const fileName = (outPtr, filePtr) => {
    const native = nativeFileFrom(filePtr);
    writeOut(
      outPtr,
      native
        ? newStringHandle(native.name || "")
        : fieldOr(filePtr, 0, () => newStringHandle(""))
    );
    return RC_SUCCESS;
  };

  const fileMime = (outPtr, filePtr) => {
    const native = nativeFileFrom(filePtr);
    writeOut(
      outPtr,
      native
        ? newStringHandle(native.type || "")
        : fieldOr(filePtr, 1, () => newStringHandle(""))
    );
    return RC_SUCCESS;
  };

  const fileSize = (outPtr, filePtr) => {
    const native = nativeFileFrom(filePtr);
    writeOut(
      outPtr,
      native ? newIntHandle(native.size | 0) : fieldOr(filePtr, 2, () => newIntHandle(0))
    );
    return RC_SUCCESS;
  };

  const fileLastModified = (outPtr, filePtr) => {
    const native = nativeFileFrom(filePtr);
    writeOut(
      outPtr,
      native
        ? newIntHandle(native.lastModified | 0)
        : fieldOr(filePtr, 3, () => newIntHandle(0))
    );
    return RC_SUCCESS;
  };

  const readNativeFile = async (kind, filePtr) => {
    const file = nativeFileFrom(filePtr);
    if (!file) return { ok: false, error: "File" };
    try {
      if (kind === "bytes") {
        const buffer = await file.arrayBuffer();
        return { ok: true, value: buffer };
      }
      if (kind === "url") {
        if (typeof FileReader !== "undefined") {
          try {
            const value = await new Promise((resolve, reject) => {
              const reader = new FileReader();
              reader.onload = () => resolve(String(reader.result || ""));
              reader.onerror = () => reject(reader.error || new Error("File"));
              reader.readAsDataURL(file);
            });
            return { ok: true, value };
          } catch {
            // Node hosts may expose FileReader that cannot read this File.
          }
        }
        const buffer = await file.arrayBuffer();
        const bytes = new Uint8Array(buffer);
        const b64 =
          typeof Buffer !== "undefined"
            ? Buffer.from(bytes).toString("base64")
            : btoa(String.fromCharCode(...bytes));
        const mime = file.type || "application/octet-stream";
        return { ok: true, value: `data:${mime};base64,${b64}` };
      }
      const text = typeof file.text === "function" ? await file.text() : "";
      return { ok: true, value: text };
    } catch (err) {
      return { ok: false, error: String(err?.message || err || "File") };
    }
  };

  const dispatchSelected = (toMsgPtr, files, multiple, taggers = []) => {
    if (!dispatchPlatformMsg || !toMsgPtr || !files.length) return;
    if (readHandle(toMsgPtr | 0)?.tag !== TAG_CLOSURE) return;
    const handles = files.map(fileHandleFromNative).filter(Boolean);
    if (!handles.length) return;
    const mapped = multiple
      ? invokeClosure(toMsgPtr | 0, [handles[0], newList(handles.slice(1))])
      : invokeClosure(toMsgPtr | 0, [handles[0]]);
    if (mapped.rc !== deps.RC_SUCCESS || !mapped.value) return;
    let ptr = mapped.value | 0;
    for (const taggerPtr of taggers ?? []) {
      if (!taggerPtr) continue;
      const next = invokeClosure(taggerPtr | 0, [ptr]);
      if (next.rc !== deps.RC_SUCCESS) return;
      ptr = next.value | 0;
    }
    if (ptr) dispatchPlatformMsg(ptr);
  };

  const openFilePicker = (payload) => {
    if (typeof document === "undefined") return;
    const input = document.createElement("input");
    input.type = "file";
    if (payload.accept) input.accept = payload.accept;
    if (payload.multiple) input.multiple = true;
    input.style.display = "none";
    document.body.appendChild(input);
    input.addEventListener("change", () => {
      const files = Array.from(input.files || []);
      dispatchSelected(
        payload.toMsg | 0,
        files,
        Boolean(payload.multiple),
        payload.taggers ?? []
      );
      input.remove();
    });
    input.click();
  };

  const drainFileCommands = (cmdPtr, taggers = []) => {
    const payload = readHandle(cmdPtr);
    if (!payload || payload.tag !== TAG_CMD) return;

    if (payload.kind === "file_download" && typeof document !== "undefined") {
      const name = stringValue(payload.name | 0) || "download.txt";
      const mime = stringValue(payload.mime | 0) || "application/octet-stream";
      runBlobDownload(name, mime, blobPartsFromContent(payload.content | 0));
      return;
    }

    if (payload.kind === "file_download_url" && typeof document !== "undefined") {
      const href = stringValue(payload.href | 0);
      if (href) {
        const anchor = document.createElement("a");
        anchor.href = href;
        anchor.download = "";
        anchor.rel = "noopener";
        document.body.appendChild(anchor);
        anchor.click();
        anchor.remove();
      }
      return;
    }

    if (
      (payload.kind === "file_select" || payload.kind === "file_select_files") &&
      typeof document !== "undefined"
    ) {
      openFilePicker({ ...payload, taggers });
    }
  };

  return {
    fileSelect,
    fileSelectFiles,
    fileDownload,
    fileDownloadUrl,
    fileDownloadTask,
    fileName,
    fileMime,
    fileSize,
    fileLastModified,
    fileHandleFromNative,
    readNativeFile,
    drainFileCommands,
  };
}
