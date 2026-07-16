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
    cmdNoneHandle,
    writeTaskSucceed,
    unitValue,
    TAG_RECORD,
    TAG_STRING,
    TAG_CMD,
    dispatchPlatformMsg,
  } = deps;

  const runStringDownload = (name, mime, content) => {
    if (typeof document === "undefined") return;
    const blob = new Blob([content], { type: mime || "text/plain" });
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement("a");
    anchor.href = url;
    anchor.download = name || "download.txt";
    anchor.click();
    URL.revokeObjectURL(url);
  };

  const fileSelect = (outPtr, toMsgPtr, acceptPtr) => {
    const accept = stringValue(acceptPtr | 0) || "";
    const handle = allocHandle({
      tag: TAG_CMD,
      kind: "file_select",
      toMsg: toMsgPtr | 0,
      accept,
    });
    writeOut(outPtr, handle);
    return RC_SUCCESS;
  };

  const fileDownload = (outPtr, namePtr, contentPtr) => {
    const handle = allocHandle({
      tag: TAG_CMD,
      kind: "file_download",
      name: namePtr | 0,
      content: contentPtr | 0,
    });
    writeOut(outPtr, handle);
    return RC_SUCCESS;
  };

  const fileDownloadTask = (outPtr, namePtr, mimePtr, contentPtr) => {
    runStringDownload(
      stringValue(namePtr | 0) || "download.txt",
      stringValue(mimePtr | 0) || "text/plain",
      stringValue(contentPtr | 0) || ""
    );
    return writeTaskSucceed(outPtr, unitValue());
  };

  const drainFileCommands = (cmdPtr) => {
    const payload = readHandle(cmdPtr);
    if (!payload || payload.tag !== TAG_CMD) return;

    if (payload.kind === "file_download" && typeof document !== "undefined") {
      const name = stringValue(payload.name | 0) || "download.txt";
      const content = stringValue(payload.content | 0) || "";
      runStringDownload(name, "text/plain", content);
      return;
    }

    if (payload.kind === "file_select" && typeof document !== "undefined") {
      const input = document.createElement("input");
      input.type = "file";
      if (payload.accept) input.accept = payload.accept;
      input.style.display = "none";
      document.body.appendChild(input);
      input.addEventListener("change", () => {
        const file = input.files?.[0];
        const names = file ? [newStringHandle(file.name)] : [];
        const list = newList(names);
        if (dispatchPlatformMsg && payload.toMsg) {
          const mapped = deps.invokeClosure(payload.toMsg | 0, [list]);
          if (mapped.rc === deps.RC_SUCCESS && mapped.value) {
            dispatchPlatformMsg(mapped.value);
          }
        }
        input.remove();
      });
      input.click();
    }
  };

  return { fileSelect, fileDownload, fileDownloadTask, drainFileCommands };
}
