import {
  Compartment,
  EditorSelection,
  EditorState,
  Prec,
  RangeSetBuilder,
  StateEffect,
  StateField,
  type Line,
  type Text
} from "@codemirror/state"
import {getUserSocket} from "../user_socket"
import type {HookContext} from "../types/liveview_hook"
import {Channel, Socket} from "phoenix"
import {
  Decoration,
  drawSelection,
  EditorView,
  keymap,
  lineNumbers,
  highlightActiveLine,
  type ViewUpdate
} from "@codemirror/view"
import {defaultKeymap, history, historyKeymap, indentLess, indentSelection, redo, selectAll, undo} from "@codemirror/commands"
import {searchKeymap} from "@codemirror/search"
import {acceptCompletion, closeCompletion, completionStatus, startCompletion} from "@codemirror/autocomplete"
import {codeFolding, foldGutter, foldKeymap, foldService, indentService, indentUnit, IndentContext} from "@codemirror/language"
import {lintGutter, setDiagnostics, type Diagnostic} from "@codemirror/lint"
import {LSPClient, formatKeymap, hoverTooltips, serverCompletion, serverDiagnostics} from "@codemirror/lsp-client"
import {getCM, Vim, vim} from "@replit/codemirror-vim"

type EditorTheme = "dark" | "light" | "system"
type EditorMode = "vim" | "regular"
type FoldRange = {start_line: number; end_line: number}
type TokenHighlight = {line: number; column: number; length: number; class?: string}
type EditorRestoreState = {cursor_offset: number; scroll_top: number; scroll_left: number}
type LintRow = {
  line?: number
  column?: number
  end_line?: number
  end_column?: number
  severity?: string
  message?: string
  source?: string
}
type LintSeverity = Diagnostic["severity"]
type LspChannelPayload = {message?: string}
type LspFoldingRange = {startLine?: number; endLine?: number}

const INDENT_WIDTH = 4
const MIN_FOLD_SPAN_LINES = 10
const clamp = (value: number, min: number, max: number): number =>
  Math.min(max, Math.max(min, value))
const safeLower = (value: unknown): string =>
  typeof value === "string" ? value.toLowerCase() : ""
const parseBooleanDataset = (value: string | undefined, fallback: boolean): boolean =>
  typeof value === "string" ? value === "true" : fallback
const parseEditorTheme = (value: string | undefined): EditorTheme => {
  const normalized = safeLower(value)
  if (normalized === "dark" || normalized === "light") return normalized
  return "system"
}
const resolvedEditorTheme = (theme: EditorTheme): "dark" | "light" => {
  if (theme === "dark" || theme === "light") return theme
  if (window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches) return "dark"
  return "light"
}

const nextIndentStop = (column: number): number => {
  const remainder = column % INDENT_WIDTH
  return column + (remainder === 0 ? INDENT_WIDTH : INDENT_WIDTH - remainder)
}

const vimDebugEnabled = (): boolean =>
  typeof localStorage !== "undefined" && localStorage.getItem("ide-vim-debug") === "1"

function vimDebug(...args: unknown[]): void {
  if (vimDebugEnabled()) console.log("[ide-vim]", ...args)
}

function clearAppTimeout(timer: ReturnType<typeof setTimeout> | null): void {
  if (timer != null) clearTimeout(timer)
}

function leadingIndentColumns(text: string): number {
  let column = 0

  for (const char of text) {
    if (char === " ") {
      column += 1
    } else if (char === "\t") {
      column = nextIndentStop(column)
    } else {
      break
    }
  }

  return column
}

function previousNonBlankLine(doc: Text, lineNumber: number): Line | null {
  for (let number = lineNumber - 1; number >= 1; number -= 1) {
    const line = doc.line(number)
    if (line.text.trim() !== "") return line
  }
  return null
}

function nextNonBlankLine(doc: Text, lineNumber: number): Line | null {
  for (let number = lineNumber + 1; number <= doc.lines; number += 1) {
    const line = doc.line(number)
    if (line.text.trim() !== "") return line
  }
  return null
}

function startsWithClosingDelimiter(text: string): boolean {
  return /^[}\])]/.test(text.trim())
}

function isSingleOpeningDelimiter(text: string): boolean {
  const trimmed = text.trim()
  return trimmed === "{" || trimmed === "[" || trimmed === "("
}

function opensIndentedBlock(text: string): boolean {
  const trimmed = text.trim()
  if (trimmed === "") return false
  if (/^(let|then|else|of)\b/.test(trimmed)) return true
  return /(?:=|->|[({[])\s*$/.test(trimmed)
}

function csrfToken(): string {
  const meta = document.querySelector("meta[name='csrf-token']")
  return meta?.getAttribute("content") ?? ""
}

function lspUri(projectSlug: string | undefined, sourceRoot: string | undefined, relPath: string | undefined): string {
  return `elm-pebble://${encodeURIComponent(projectSlug || "project")}/${encodeURIComponent(
    sourceRoot || "watch"
  )}/${encodeURIComponent(relPath || "src/Main.elm")}`
}

class PhoenixLspTransport {
  handlers = new Set<(message: string) => void>()
  queue: string[] = []
  joined = false
  socket: Socket
  channel: Channel

  constructor(projectSlug: string | undefined) {
    this.socket = getUserSocket()
    this.channel = this.socket.channel(`lsp:${projectSlug || "project"}`, {})
    this.channel.on("message", (payload: unknown) => {
      const data = payload as LspChannelPayload
      if (typeof data.message === "string") {
        for (const handler of this.handlers) handler(data.message)
      }
    })
    this.channel
      .join()
      .receive("ok", () => {
        this.joined = true
        const queued = this.queue.splice(0)
        queued.forEach(message => this.send(message))
      })
      .receive("error", response => console.warn("[lsp] channel join failed", response))
  }

  send(message: string): void {
    if (!this.joined) {
      this.queue.push(message)
      return
    }
    this.channel.push("message", {message})
  }

  subscribe(handler: (message: string) => void): void {
    this.handlers.add(handler)
  }

  unsubscribe(handler: (message: string) => void): void {
    this.handlers.delete(handler)
  }

  destroy(): void {
    this.handlers.clear()
    this.channel.leave()
    this.socket.disconnect()
  }
}

const setTokenHighlightsEffect = StateEffect.define<TokenHighlight[]>()
const setFoldRangesEffect = StateEffect.define<FoldRange[]>()

const tokenHighlightField = StateField.define({
  create() {
    return Decoration.none
  },

  update(value, transaction) {
    let next = value.map(transaction.changes)

    for (const effect of transaction.effects) {
      if (effect.is(setTokenHighlightsEffect)) {
        next = buildTokenHighlights(transaction.state, effect.value)
      }
    }

    return next
  },

  provide: field => EditorView.decorations.from(field)
})

const foldRangesField = StateField.define<FoldRange[]>({
  create() {
    return []
  },

  update(value, transaction) {
    let next = value

    for (const effect of transaction.effects) {
      if (effect.is(setFoldRangesEffect)) {
        next = normalizeFoldRanges(effect.value, transaction.state.doc.lines)
      }
    }

    return next
  }
})

function normalizeFoldRanges(ranges: unknown, maxLines: number): FoldRange[] {
  if (!Array.isArray(ranges) || ranges.length === 0) return []
  const unique = new Set()
  const normalized = []

  for (const range of ranges) {
    const start = Number(range && range.start_line)
    const end = Number(range && range.end_line)
    if (!Number.isInteger(start) || !Number.isInteger(end)) continue
    if (start < 1 || end < 1 || end - start <= MIN_FOLD_SPAN_LINES || start > maxLines) continue
    const clampedEnd = clamp(end, start + 1, maxLines)
    const key = `${start}:${clampedEnd}`
    if (unique.has(key)) continue
    unique.add(key)
    normalized.push({start_line: start, end_line: clampedEnd})
  }

  normalized.sort((a, b) => (a.start_line === b.start_line ? a.end_line - b.end_line : a.start_line - b.start_line))
  return normalized
}

function sanitizeTokenClass(value: unknown): string {
  return `cm-tok-${String(value || "plain").replace(/[^a-zA-Z0-9_-]/g, "-")}`
}

function buildTokenHighlights(state: EditorState, tokens: TokenHighlight[]) {
  if (!Array.isArray(tokens) || tokens.length === 0) return Decoration.none

  const docLength = state.doc.length
  const spans: {from: number; to: number; className: string}[] = []

  for (const token of tokens) {
    const lineNumber = Number(token && token.line)
    const column = Number(token && token.column)
    const length = Number(token && token.length)

    if (!Number.isInteger(lineNumber) || !Number.isInteger(column) || !Number.isInteger(length)) continue
    if (lineNumber < 1 || lineNumber > state.doc.lines || column < 1 || length <= 0) continue

    const lineInfo = state.doc.line(lineNumber)
    const from = clamp(lineInfo.from + column - 1, lineInfo.from, docLength)
    const to = clamp(from + length, from, docLength)
    if (to <= from) continue

    spans.push({from, to, className: sanitizeTokenClass(token.class)})
  }

  if (spans.length === 0) return Decoration.none

  spans.sort((a, b) => a.from - b.from || a.to - b.to)

  const builder = new RangeSetBuilder<Decoration>()
  for (const span of spans) {
    builder.add(span.from, span.to, Decoration.mark({class: span.className}))
  }

  return builder.finish()
}

let cmVisibilityStyleInjected = false
let vimWriteCommandRegistered = false
const vimHostByCm = new WeakMap<object, CodeMirrorEditorHost>()

function ensureVimOnlyEditorStyles() {
  if (cmVisibilityStyleInjected) return

  const style = document.createElement("style")
  style.id = "cm-vim-editor-styles"
  style.textContent = `
    /* Standard caret in regular mode (never strip the border globally). */
    [data-role="cm-root"] .cm-editor:not(.cm-fat-cursor) .cm-cursor,
    [data-role="cm-root"] .cm-editor:not(.cm-fat-cursor) .cm-dropCursor {
      border-left-width: 2px !important;
      border-left-style: solid !important;
      background: transparent !important;
    }

    /* Vim block cursor layer sits above text; keep it visible in our theme. */
    [data-role="cm-root"] .cm-vimCursorLayer .cm-fat-cursor {
      background: var(--cm-cursor-bg, rgba(244, 244, 245, 0.85)) !important;
      color: var(--cm-editor-fg, #f4f4f5) !important;
    }
  `
  document.head.appendChild(style)
  cmVisibilityStyleInjected = true
}

function ensureVimWriteCommandRegistered() {
  if (vimWriteCommandRegistered) return

  try {
    Vim.defineEx("write", "w", cm => {
      const host = vimHostByCm.get(cm)
      if (host && host.saveEvent) host.pushSaveEvent()
    })
  } catch (_error) {
    // Ignore duplicate registrations from hot reload cycles.
  }

  vimWriteCommandRegistered = true
}

export class CodeMirrorEditorHost {
  hook: HookContext
  el: HTMLElement
  root: Element | null
  hiddenInput: HTMLInputElement | null
  form: HTMLFormElement | null
  modeBadge: HTMLElement | null
  editorMode: EditorMode
  editorTheme: EditorTheme
  editorLineNumbers: boolean
  editorActiveLineHighlight: boolean
  readOnly: boolean
  idleEvent: string | undefined
  focusNextEvent: string | undefined
  focusPrevEvent: string | undefined
  saveEvent: string | undefined
  formatEvent: string | undefined
  contextMenuEvent: string | undefined
  tabId: string | undefined
  projectSlug: string | undefined
  sourceRoot: string | undefined
  relPath: string | undefined
  lspUri: string
  lspTransport: PhoenixLspTransport
  lspClient: LSPClient
  idleTimer: ReturnType<typeof setTimeout> | null = null
  changeTimer: ReturnType<typeof setTimeout> | null = null
  autoCompletionTimer: ReturnType<typeof setTimeout> | null = null
  lspFoldTimer: ReturnType<typeof setTimeout> | null = null
  scrollStateTimer: ReturnType<typeof setTimeout> | null = null
  pendingEnterIndent = false
  restoringState = false
  modeCompartment = new Compartment()
  keymapCompartment = new Compartment()
  themeCompartment = new Compartment()
  lineNumbersCompartment = new Compartment()
  activeLineCompartment = new Compartment()
  view?: EditorView
  onKeydown?: (event: KeyboardEvent) => void
  onContextMenu?: (event: MouseEvent) => void
  onClick?: (event: MouseEvent) => void
  onFocusIn?: () => void
  onFocusOut?: () => void
  onScroll?: () => void
  onSubmit?: () => void
  vimModeListener?: (event: {mode?: string; subMode?: string}) => void

  constructor(hook: HookContext) {
    this.hook = hook
    this.el = hook.el
    this.root = this.el.querySelector("[data-role='cm-root']")
    this.hiddenInput = this.el.querySelector<HTMLInputElement>("[data-role='input']")
    this.form = this.el.closest("form")
    this.modeBadge = this.el.querySelector("[data-role='mode-badge']")
    this.editorMode = safeLower(this.el.dataset.editorMode) === "vim" ? "vim" : "regular"
    this.editorTheme = parseEditorTheme(this.el.dataset.editorTheme)
    this.editorLineNumbers = parseBooleanDataset(this.el.dataset.editorLineNumbers, true)
    this.editorActiveLineHighlight = parseBooleanDataset(
      this.el.dataset.editorActiveLineHighlight,
      true
    )
    this.readOnly = this.el.dataset.editorReadonly === "true"

    this.idleEvent = this.el.dataset.tokenizeIdleEvent
    this.focusNextEvent = this.el.dataset.focusNextEvent
    this.focusPrevEvent = this.el.dataset.focusPrevEvent
    this.saveEvent = this.el.dataset.saveEvent
    this.formatEvent = this.el.dataset.formatEvent
    this.contextMenuEvent = this.el.dataset.contextMenuEvent
    this.tabId = this.el.dataset.tabId
    this.projectSlug = this.el.dataset.projectSlug
    this.sourceRoot = this.el.dataset.sourceRoot
    this.relPath = this.el.dataset.relPath
    this.lspUri = lspUri(this.projectSlug, this.sourceRoot, this.relPath)
    this.lspTransport = new PhoenixLspTransport(this.projectSlug)
    this.lspClient = new LSPClient({
      rootUri: `elm-pebble://${encodeURIComponent(this.projectSlug || "project")}`,
      timeout: 10000,
      extensions: [
        serverCompletion({override: true}),
        serverDiagnostics(),
        hoverTooltips(),
        keymap.of(formatKeymap)
      ]
    }).connect(this.lspTransport)

    this.idleTimer = null
    this.changeTimer = null
    this.autoCompletionTimer = null
    this.lspFoldTimer = null
    this.scrollStateTimer = null
    this.pendingEnterIndent = false
    this.restoringState = false
    this.modeCompartment = new Compartment()
    this.keymapCompartment = new Compartment()
    this.themeCompartment = new Compartment()
    this.lineNumbersCompartment = new Compartment()
    this.activeLineCompartment = new Compartment()
  }

  mount() {
    if (!this.root || !this.hiddenInput) return
    this.ensureModeBadge()

    const initialContent = this.hiddenInput.value || ""
    const initialRestoreState = this.restoreStateFromDataset(initialContent.length)

    this.view = new EditorView({
      parent: this.root,
      state: EditorState.create({
        doc: initialContent,
        selection: {anchor: initialRestoreState.cursor_offset},
        extensions: this.editorExtensions()
      })
    })

    ensureVimOnlyEditorStyles()
    this.bindDomEvents()
    this.syncEditorPresentation()
    this.updateModeBadge()
    this.bindVimInstance()
    this.restoreState(initialRestoreState)
    this.requestLspFoldRangesDebounced()
    this.scheduleCompilerTokenize()
  }

  editorExtensions() {
    const extensions = [
      // Vim must load before other keymaps so normal-mode bindings win.
      this.modeCompartment.of(this.modeExtension()),
      this.workspaceShortcutsExtension(),
      this.clipboardShortcutsExtension(),
      this.vimKeydownBridgeExtension(),
      this.vimInputGuardExtension(),
      drawSelection(),
      this.lineNumbersCompartment.of(this.lineNumbersExtension()),
      history(),
      this.activeLineCompartment.of(this.activeLineExtension()),
      this.tabKeymapExtension(),
      this.keymapCompartment.of(keymap.of(this.sharedKeymapBindings())),
      Prec.high(
        EditorView.domEventHandlers({
          keydown: event => this.handleSemanticDomKeydown(event)
        })
      ),
      tokenHighlightField,
      foldRangesField,
      codeFolding(),
      foldGutter(),
      lintGutter(),
      this.lspClient.plugin(this.lspUri, "elm"),
      foldService.of((state, lineStart) => {
        const ranges = state.field(foldRangesField, false) || []
        if (ranges.length === 0) return null

        const lineNumber = state.doc.lineAt(lineStart).number
        const match = ranges.find(range => range.start_line === lineNumber)
        if (!match) return null

        const from = state.doc.line(match.start_line).to
        const to = state.doc.line(Math.min(match.end_line, state.doc.lines)).to
        return to > from ? {from, to} : null
      }),
      indentService.of((context, pos) => this.indentColumnForLine(context, pos)),
      this.themeCompartment.of(this.themeExtension()),
      EditorState.tabSize.of(INDENT_WIDTH),
      indentUnit.of("    "),
      EditorView.editable.of(!this.readOnly),
      EditorState.readOnly.of(this.readOnly),
      EditorView.updateListener.of(update => this.onUpdate(update))
    ]

    if (this.editorMode === "regular") {
      extensions.push(
        Prec.high(
          keymap.of([
            ...searchKeymap,
            {key: "Enter", run: () => false},
            {key: "Tab", run: () => false},
            {key: "Shift-Tab", run: () => false}
          ])
        )
      )
    }

    return extensions
  }

  sharedKeymapBindings() {
    // completionKeymap comes from LSP autocompletion; duplicating it fights vim.
    return [...defaultKeymap, ...historyKeymap, ...foldKeymap]
  }

  shouldDeferToWorkspaceShortcut(event: KeyboardEvent): boolean {
    const mod = event.metaKey || event.ctrlKey
    if (mod && safeLower(event.key) === "s") return true
    if (mod && (event.key === " " || event.code === "Space")) return true
    if (event.altKey && !mod && (event.key === "ArrowDown" || event.key === "ArrowUp")) return true
    return false
  }

  selectedEditorText(view: EditorView): string | null {
    const parts: string[] = []

    for (const range of view.state.selection.ranges) {
      if (!range.empty) parts.push(view.state.sliceDoc(range.from, range.to))
    }

    if (parts.length === 0) return null
    return parts.join(view.state.lineBreak)
  }

  async writeClipboardText(text: string): Promise<void> {
    try {
      await navigator.clipboard.writeText(text)
    } catch {
      const target = document.createElement("textarea")
      target.style.cssText = "position: fixed; left: -10000px; top: 10px"
      target.value = text
      document.body.appendChild(target)
      target.focus()
      target.select()
      try {
        document.execCommand("copy")
      } finally {
        target.remove()
      }
    }
  }

  copyEditorSelection(view: EditorView = this.view!): boolean {
    const text = this.selectedEditorText(view)
    if (!text) return false
    void this.writeClipboardText(text)
    return true
  }

  cutEditorSelection(view: EditorView = this.view!): boolean {
    if (this.readOnly) return false
    const text = this.selectedEditorText(view)
    if (!text) return false
    const changes = view.state.selection.ranges
      .filter(range => !range.empty)
      .map(range => ({from: range.from, to: range.to}))
    void this.writeClipboardText(text)
    view.dispatch({changes, userEvent: "delete.cut"})
    return true
  }

  async pasteEditorSelection(view: EditorView = this.view!): Promise<boolean> {
    if (this.readOnly) return false
    try {
      const text = await navigator.clipboard.readText()
      if (!text) return false
      const {from, to} = view.state.selection.main
      view.dispatch({
        changes: {from, to, insert: text},
        selection: {anchor: from + text.length},
        scrollIntoView: true,
        userEvent: "input.paste"
      })
      return true
    } catch {
      return false
    }
  }

  runContextAction(action: string): void {
    const view = this.view
    if (!view) return

    switch (action) {
      case "copy":
        this.copyEditorSelection(view)
        break
      case "cut":
        this.cutEditorSelection(view)
        break
      case "paste":
        void this.pasteEditorSelection(view)
        break
      case "undo":
        undo(view)
        break
      case "redo":
        redo(view)
        break
      case "select-all":
        selectAll(view)
        break
      case "save":
        this.pushSaveEvent()
        break
      case "format":
        this.requestFormatDocument()
        break
      default:
        return
    }

    view.focus()
  }

  clipboardShortcutsExtension() {
    // Must run before vimKeydownBridgeExtension — vim maps <C-c> to <Esc>.
    return Prec.highest(
      EditorView.domEventHandlers({
        keydown: (event, view) => {
          const mod = event.metaKey || event.ctrlKey
          if (!mod) return false

          const key = safeLower(event.key)
          if (key === "c") {
            const text = this.selectedEditorText(view)
            if (!text) return false
            event.preventDefault()
            this.copyEditorSelection(view)
            return true
          }

          if (key === "x" && !this.readOnly) {
            if (!this.selectedEditorText(view)) return false
            event.preventDefault()
            this.cutEditorSelection(view)
            return true
          }

          return false
        }
      })
    )
  }

  dispatchVimTextInput(cm: NonNullable<ReturnType<typeof getCM>>, text: string): void {
    if (completionStatus(cm.cm6.state) === "active") closeCompletion(cm.cm6)

    for (const char of text) {
      const vimKey =
        char === "\n" || char === "\r" ? "<CR>" : char === "\t" ? "<Tab>" : char
      Vim.multiSelectHandleKey(cm, vimKey, "user")
    }
  }

  vimKeydownBridgeExtension() {
    // Opt-in trace: localStorage.setItem("ide-vim-debug", "1") then hard-refresh.
    return Prec.highest(
      EditorView.domEventHandlers({
        keydown: (event, view) => {
          vimDebug("keydown:event", event.key)
          if (this.editorMode !== "vim") return false
          if (this.shouldDeferToWorkspaceShortcut(event)) return false
          if (this.selectedEditorText(view)) {
            const mod = event.metaKey || event.ctrlKey
            if (mod && (safeLower(event.key) === "c" || safeLower(event.key) === "x")) return false
          }

          const cm = getCM(view)
          if (!cm) {
            vimDebug("keydown: no cm bridge on view", event.key)
            return false
          }

          const vim = cm.state?.vim
          if (!vim) {
            vimDebug("keydown: vim state missing", event.key)
            return false
          }

          // Insert-mode typing is handled by the vim plugin + contenteditable.
          if (vim.insertMode) return false

          if (completionStatus(view.state) === "active") closeCompletion(view)

          const key = Vim.vimKeyFromEvent(event, vim)
          if (!key) {
            vimDebug("keydown: no vim key mapping", event.key)
            return false
          }

          const handled = !!Vim.multiSelectHandleKey(cm, key, "user")
          vimDebug("keydown", {
            key: event.key,
            vimKey: key,
            handled,
            insertMode: vim.insertMode,
            visualMode: vim.visualMode
          })

          if (handled) {
            event.preventDefault()
            event.stopPropagation()
          }

          return handled
        }
      })
    )
  }

  vimInputGuardExtension() {
    // Runs before @replit/codemirror-vim's inputHandler. In normal/visual mode we must
    // dispatch keys through vim — not only block insertion (which breaks Firefox/Linux
    // Dead-key and useNextTextInput paths if we return true unconditionally).
    return Prec.highest(
      EditorView.inputHandler.of((view, from, to, text) => {
        if (this.editorMode !== "vim" || view.composing) return false

        const cm = getCM(view)
        if (!cm) return false

        const vim = cm.state?.vim
        const vimPlugin = cm.state?.vimPlugin as {useNextTextInput?: boolean} | undefined
        if (!vim || vim.insertMode) return false
        if (cm.curOp?.isVimOp) return false
        if (!text) return false
        if (text === "\0\0") return true

        // Let the vim plugin handle IME / Dead-key / Firefox-Linux text-input fallback.
        if (vimPlugin?.useNextTextInput && text.length === 1) return false

        this.dispatchVimTextInput(cm, text)
        vimDebug("input->vim", {
          text: JSON.stringify(text),
          insertMode: vim.insertMode
        })
        return true
      })
    )
  }

  workspaceShortcutsExtension() {
    return Prec.highest(
      keymap.of([
        {
          key: "Mod-s",
          run: () => {
            if (!this.saveEvent) return false
            this.pushSaveEvent()
            return true
          }
        },
        {
          key: "Mod-Space",
          mac: "Cmd-Space",
          run: view => this.runManualCompletion(view)
        },
        {
          key: "Alt-ArrowDown",
          run: () => {
            if (!this.focusNextEvent) return false
            this.hook.pushEvent(this.focusNextEvent, {})
            return true
          }
        },
        {
          key: "Alt-ArrowUp",
          run: () => {
            if (!this.focusPrevEvent) return false
            this.hook.pushEvent(this.focusPrevEvent, {})
            return true
          }
        }
      ])
    )
  }

  tabKeymapExtension() {
    return Prec.highest(
      keymap.of([
        {
          key: "Tab",
          run: view => this.runTabIndent(view, false),
          shift: view => this.runTabIndent(view, true)
        },
        {
          key: "Shift-Alt-f",
          run: () => this.requestFormatDocument()
        }
      ])
    )
  }

  modeExtension() {
    return this.editorMode === "vim" ? vim() : []
  }

  lineNumbersExtension() {
    return this.editorLineNumbers ? lineNumbers() : []
  }

  activeLineExtension() {
    return this.editorActiveLineHighlight ? highlightActiveLine() : []
  }

  themeExtension() {
    const theme = resolvedEditorTheme(this.editorTheme)

    const shared = {
      ".cm-scroller": {
        fontFamily: "ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace",
        lineHeight: "1.5rem",
        fontSize: "0.875rem"
      },
      ".cm-tooltip.cm-tooltip-lint .cm-diagnostic.cm-diagnostic-warning": {color: "#b45309"},
      ".cm-tooltip.cm-tooltip-lint .cm-diagnostic.cm-diagnostic-error": {color: "#b91c1c"},
      ".cm-tooltip.cm-tooltip-lint .cm-diagnostic.cm-diagnostic-info": {color: "#1d4ed8"},
      ".cm-selectionLayer .cm-selectionBackground, .cm-selectionBackground, .cm-content ::selection":
        {
          backgroundColor: "rgba(56, 189, 248, 0.3) !important"
        },
      "&.cm-focused": {outline: "none"},
      ".cm-tok-error": {textDecoration: "wavy underline #f97316"},
      ".cm-tok-invalid": {textDecoration: "wavy underline #f97316"}
    }

    const darkStyles = {
      "&": {
        height: "100%",
        color: "#f4f4f5",
        backgroundColor: "#09090b",
        "--cm-editor-fg": "#f4f4f5",
        "--cm-cursor-bg": "rgba(244, 244, 245, 0.85)",
        "--cm-selection-bg": "rgba(56, 189, 248, 0.32)",
        "--cm-selection-fg": "#f4f4f5"
      },
      ".cm-content": {padding: "0.75rem", tabSize: "4", color: "#f4f4f5"},
      ".cm-line": {color: "#f4f4f5"},
      ".cm-cursor, .cm-dropCursor": {
        borderLeftWidth: "2px",
        borderLeftStyle: "solid",
        borderLeftColor: "#f4f4f5"
      },
      ".cm-gutters": {
        backgroundColor: "#18181b",
        color: "#71717a",
        borderRight: "1px solid #27272a"
      },
      ".cm-foldGutter .cm-gutterElement": {color: "#a1a1aa"},
      ".cm-foldGutter .cm-foldPlaceholder": {
        backgroundColor: "#27272a",
        border: "1px solid #3f3f46",
        color: "#e4e4e7"
      },
      ".cm-tooltip.cm-tooltip-lint": {
        backgroundColor: "#18181b",
        border: "1px solid #3f3f46",
        color: "#f4f4f5"
      },
      ".cm-tooltip.cm-tooltip-lint .cm-diagnostic": {color: "#f4f4f5"},
      ".cm-tooltip.cm-tooltip-lint .cm-diagnostic:hover": {backgroundColor: "#27272a"},
      ".cm-activeLineGutter": {backgroundColor: "#27272a"},
      "&.cm-focused.cm-fat-cursor .cm-line, &.cm-focused.cm-fat-cursor .cm-line *": {
        color: "#f4f4f5 !important",
        textShadow: "none !important"
      },
      "&.cm-focused.cm-fat-cursor .cm-cursorLayer .cm-cursor": {
        borderLeft: "none",
        backgroundColor: "rgba(244, 244, 245, 0.85)"
      },
      ".cm-tok-comment": {color: "#71717a"},
      ".cm-tok-string, .cm-tok-char": {color: "#34d399"},
      ".cm-tok-number": {color: "#fbbf24"},
      ".cm-tok-keyword": {color: "#c084fc", fontWeight: "500"},
      ".cm-tok-operator": {color: "#d4d4d8"},
      ".cm-tok-type_identifier": {color: "#22d3ee"},
      ".cm-tok-identifier": {color: "#f4f4f5"},
      ".cm-tok-field_identifier": {color: "#7dd3fc"},
      ".cm-tok-delimiter": {color: "#a1a1aa"}
    }

    const lightStyles = {
      "&": {
        height: "100%",
        color: "#18181b",
        backgroundColor: "#ffffff",
        "--cm-editor-fg": "#18181b",
        "--cm-cursor-bg": "rgba(24, 24, 27, 0.45)",
        "--cm-selection-bg": "rgba(14, 165, 233, 0.25)",
        "--cm-selection-fg": "#0f172a"
      },
      ".cm-content": {padding: "0.75rem", tabSize: "4", color: "#18181b"},
      ".cm-line": {color: "#18181b"},
      ".cm-cursor, .cm-dropCursor": {
        borderLeftWidth: "2px",
        borderLeftStyle: "solid",
        borderLeftColor: "#18181b"
      },
      ".cm-gutters": {
        backgroundColor: "#fafafa",
        color: "#71717a",
        borderRight: "1px solid #e4e4e7"
      },
      ".cm-foldGutter .cm-gutterElement": {color: "#52525b"},
      ".cm-foldGutter .cm-foldPlaceholder": {
        backgroundColor: "#f4f4f5",
        border: "1px solid #d4d4d8",
        color: "#27272a"
      },
      ".cm-tooltip.cm-tooltip-lint": {
        backgroundColor: "#ffffff",
        border: "1px solid #d4d4d8",
        color: "#18181b"
      },
      ".cm-tooltip.cm-tooltip-lint .cm-diagnostic": {color: "#18181b"},
      ".cm-tooltip.cm-tooltip-lint .cm-diagnostic:hover": {backgroundColor: "#f4f4f5"},
      ".cm-activeLineGutter": {backgroundColor: "#f4f4f5"},
      "&.cm-focused.cm-fat-cursor .cm-line, &.cm-focused.cm-fat-cursor .cm-line *": {
        color: "#18181b !important",
        textShadow: "none !important"
      },
      "&.cm-focused.cm-fat-cursor .cm-cursorLayer .cm-cursor": {
        borderLeft: "none",
        backgroundColor: "rgba(24, 24, 27, 0.45)"
      },
      ".cm-tok-comment": {color: "#71717a"},
      ".cm-tok-string, .cm-tok-char": {color: "#047857"},
      ".cm-tok-number": {color: "#b45309"},
      ".cm-tok-keyword": {color: "#7c3aed", fontWeight: "500"},
      ".cm-tok-operator": {color: "#52525b"},
      ".cm-tok-type_identifier": {color: "#0e7490"},
      ".cm-tok-identifier": {color: "#18181b"},
      ".cm-tok-field_identifier": {color: "#0369a1"},
      ".cm-tok-delimiter": {color: "#52525b"}
    }

    const styles = theme === "dark" ? {...shared, ...darkStyles} : {...shared, ...lightStyles}
    return EditorView.theme(styles, {dark: theme === "dark"})
  }

  bindVimInstance() {
    if (!this.view) return
    const cm = getCM(this.view)
    if (!cm) return
    ensureVimWriteCommandRegistered()
    vimHostByCm.set(cm, this)

    if (this.vimModeListener) cm.off("vim-mode-change", this.vimModeListener)

    this.vimModeListener = event => {
      if (event.mode === "normal" && this.view) closeCompletion(this.view)
      this.updateModeBadge(event.mode, event.subMode)
    }

    cm.on("vim-mode-change", this.vimModeListener)

    if (this.editorMode === "vim") closeCompletion(this.view)
  }

  onUpdate(update: ViewUpdate): void {
    this.syncEditorPresentation()

    if (update.docChanged) {
      if (this.updateInsertedNewline(update)) this.pendingEnterIndent = true
      this.applyPendingEnterIndent()
      this.syncHiddenInput()
      this.pushEditorChangeDebounced()
      this.requestLspFoldRangesDebounced()
      this.scheduleCompilerTokenize()
      this.scheduleAutoCompletions()
    }
    if (!this.restoringState && (update.docChanged || update.selectionSet || update.viewportChanged)) {
      this.reportEditorState()
    }
  }

  updateInsertedNewline(update: ViewUpdate): boolean {
    let insertedNewline = false
    update.changes.iterChanges((_fromA, _toA, _fromB, _toB, inserted) => {
      if (inserted.toString().includes("\n")) insertedNewline = true
    })
    return insertedNewline
  }

  bindDomEvents(): void {
    const view = this.view
    if (!view) return

    this.onKeydown = event => this.handleKeydown(event)
    this.onContextMenu = event => this.handleContextMenu(event)
    this.onClick = event => this.handleClick(event)
    this.onFocusIn = () => {
      this.syncEditorPresentation()
    }
    this.onFocusOut = () => {}
    this.onScroll = () => this.reportEditorStateDebounced()
    this.onSubmit = () => {
      this.cancelPendingEditorChange()
      this.syncHiddenInput()
    }

    view.dom.addEventListener("keydown", this.onKeydown)
    view.dom.addEventListener("contextmenu", this.onContextMenu)
    view.dom.addEventListener("click", this.onClick)
    view.dom.addEventListener("focusin", this.onFocusIn)
    view.dom.addEventListener("focusout", this.onFocusOut)
    view.scrollDOM.addEventListener("scroll", this.onScroll, {passive: true})
    if (this.form) this.form.addEventListener("submit", this.onSubmit)
  }

  unbindDomEvents(): void {
    const view = this.view
    if (!view) return
    const {onKeydown, onContextMenu, onClick, onFocusIn, onFocusOut, onScroll, onSubmit} = this
    if (onKeydown) view.dom.removeEventListener("keydown", onKeydown)
    if (onContextMenu) view.dom.removeEventListener("contextmenu", onContextMenu)
    if (onClick) view.dom.removeEventListener("click", onClick)
    if (onFocusIn) view.dom.removeEventListener("focusin", onFocusIn)
    if (onFocusOut) view.dom.removeEventListener("focusout", onFocusOut)
    if (onScroll) view.scrollDOM.removeEventListener("scroll", onScroll)
    if (this.form && onSubmit) this.form.removeEventListener("submit", onSubmit)
  }

  syncEditorPresentation(): void {
    if (!this.view) return

    const {dom, scrollDOM} = this.view
    dom.classList.remove("cm-force-visible-text")

    if (this.editorMode === "regular") {
      dom.classList.remove("cm-fat-cursor")
      scrollDOM.classList.remove("cm-vimMode")
    }
  }

  ensureModeBadge() {
    if (this.modeBadge) return
    this.modeBadge = document.createElement("div")
    this.modeBadge.dataset.role = "mode-badge"
    this.modeBadge.className =
      "pointer-events-none absolute bottom-2 right-2 rounded bg-zinc-900/85 px-2 py-1 font-mono text-[10px] tracking-wide text-zinc-200"
    this.el.appendChild(this.modeBadge)
  }

  updateModeBadge(vimMode?: string, vimSubMode?: string): void {
    if (!this.modeBadge) return

    if (this.editorMode !== "vim") {
      this.modeBadge.textContent = "REGULAR"
      return
    }

    const cm = this.view ? getCM(this.view) : null
    const vim = cm?.state?.vim
    const modeLabel =
      vim?.insertMode === true
        ? "INSERT"
        : (vimMode || vim?.mode || "normal").toUpperCase()
    const subMode = vimSubMode ? ` ${vimSubMode.toUpperCase()}` : ""
    this.modeBadge.textContent = `VIM ${modeLabel}${subMode}`
  }

  getSelection() {
    if (!this.view) return {start: 0, end: 0}
    const main = this.view.state.selection.main
    return {start: main.from, end: main.to}
  }

  getValue() {
    return this.view ? this.view.state.doc.toString() : ""
  }

  syncHiddenInput() {
    if (this.hiddenInput) this.hiddenInput.value = this.getValue()
  }

  pushEditorChangeDebounced(): void {
    clearAppTimeout(this.changeTimer)
    this.changeTimer = setTimeout(() => {
      this.hook.pushEvent("editor-change", {content: this.getValue()})
    }, 80)
  }

  scheduleCompilerTokenize(): void {
    if (!this.idleEvent) return
    const idleEvent = this.idleEvent
    clearAppTimeout(this.idleTimer)
    this.idleTimer = setTimeout(() => this.hook.pushEvent(idleEvent, {}), 650)
  }

  reportEditorState() {
    if (!this.view) return
    const cursor = this.view.state.selection.main.head
    this.hook.pushEvent("editor-state-changed", {
      tab_id: this.tabId,
      cursor_offset: cursor,
      scroll_top: this.view.scrollDOM.scrollTop || 0,
      scroll_left: this.view.scrollDOM.scrollLeft || 0
    })
  }

  reportEditorStateDebounced(): void {
    if (this.restoringState) return
    clearAppTimeout(this.scrollStateTimer)
    this.scrollStateTimer = setTimeout(() => this.reportEditorState(), 80)
  }

  applyTokenHighlights({tokens}: {tokens?: TokenHighlight[]}): void {
    if (!this.view) return

    this.view.dispatch({
      effects: setTokenHighlightsEffect.of(Array.isArray(tokens) ? tokens : [])
    })
  }

  applyFoldRanges({ranges}: {ranges?: FoldRange[]}): void {
    if (this.lspClient && this.lspClient.connected) return
    if (!this.view) return

    this.view.dispatch({
      effects: setFoldRangesEffect.of(Array.isArray(ranges) ? ranges : [])
    })
  }

  requestLspFoldRangesDebounced(): void {
    if (!this.lspClient || !this.lspClient.connected || !this.view) return
    clearAppTimeout(this.lspFoldTimer)
    this.lspFoldTimer = setTimeout(() => this.requestLspFoldRanges(), 250)
  }

  requestLspFoldRanges() {
    if (!this.lspClient || !this.lspClient.connected || !this.view) return
    this.lspClient.sync()
    this.lspClient
      .request("textDocument/foldingRange", {textDocument: {uri: this.lspUri}})
      .then(ranges => {
        if (!this.view || !Array.isArray(ranges)) return
        const converted = (ranges as LspFoldingRange[]).map(range => ({
          start_line: Number(range.startLine) + 1,
          end_line: Number(range.endLine) + 1
        }))
        this.view.dispatch({effects: setFoldRangesEffect.of(converted)})
      })
      .catch(error => console.warn("[lsp] foldingRange failed", error))
  }

  applyLintDiagnostics({diagnostics}: {diagnostics?: LintRow[]}): void {
    if (!this.view) return

    const rows = Array.isArray(diagnostics) ? diagnostics : []
    const mapped: Diagnostic[] = []

    for (const row of rows) {
      const line = Number(row && row.line)
      if (!Number.isInteger(line) || line < 1 || line > this.view.state.doc.lines) continue

      const lineInfo = this.view.state.doc.line(line)
      const startColumn = Number(row && row.column)
      const fallbackFrom = lineInfo.from
      const from = Number.isInteger(startColumn)
        ? clamp(lineInfo.from + Math.max(startColumn - 1, 0), lineInfo.from, lineInfo.to)
        : fallbackFrom

      const endLine = Number(row && row.end_line)
      const endColumn = Number(row && row.end_column)

      let to
      if (Number.isInteger(endLine) && Number.isInteger(endColumn) && endLine >= line) {
        const endLineInfo = this.view.state.doc.line(clamp(endLine, 1, this.view.state.doc.lines))
        to = clamp(endLineInfo.from + Math.max(endColumn - 1, 0), from + 1, this.view.state.doc.length)
      } else {
        to = clamp(from + 1, from + 1, this.view.state.doc.length)
      }

      mapped.push({
        from,
        to,
        severity: this.mapLintSeverity(row && row.severity),
        message: String((row && row.message) || "Issue"),
        source: row && row.source ? String(row.source) : "parser"
      })
    }

    this.view.dispatch(setDiagnostics(this.view.state, mapped))
  }

  mapLintSeverity(value: unknown): LintSeverity {
    const normalized = safeLower(value)
    if (normalized === "error") return "error"
    if (normalized === "warning" || normalized === "warn") return "warning"
    return "info"
  }

  requestSemanticEdit(key: string, shiftKey: boolean): boolean {
    if (!this.view || this.readOnly) return false
    const value = this.getValue()
    const {start, end} = this.getSelection()
    this.hook.pushEvent("editor-key-edit", {
      key,
      shift_key: !!shiftKey,
      content: value,
      selection_start: start,
      selection_end: end
    })
    return true
  }

  requestFormatDocument() {
    return this.pushFormatEvent()
  }

  pushSaveEvent() {
    if (!this.saveEvent) return
    this.cancelPendingEditorChange()
    this.syncHiddenInput()
    this.hook.pushEvent(this.saveEvent, {content: this.getValue()})
  }

  pushFormatEvent() {
    if (!this.view || this.readOnly || !this.formatEvent) return false
    this.cancelPendingEditorChange()
    this.syncHiddenInput()
    this.hook.pushEvent(this.formatEvent, {content: this.getValue()})
    return true
  }

  cancelPendingEditorChange(): void {
    clearAppTimeout(this.changeTimer)
    this.changeTimer = null
  }

  applyPendingEnterIndent() {
    if (!this.pendingEnterIndent || !this.view || this.readOnly) return
    this.pendingEnterIndent = false

    const state = this.view.state
    const main = state.selection.main
    if (!main.empty) return

    const line = state.doc.lineAt(main.head)
    const beforeCursor = state.doc.sliceString(line.from, main.head)
    if (!/^\s*$/.test(beforeCursor)) return

    const desiredIndent = this.indentColumnForLine(new IndentContext(state), line.from)
    const currentIndent = beforeCursor.length
    if (desiredIndent === currentIndent) return

    const indentText = " ".repeat(Math.max(0, desiredIndent))
    this.view.dispatch({
      changes: {from: line.from, to: main.head, insert: indentText},
      selection: {anchor: line.from + indentText.length}
    })
  }

  indentColumnForLine(context: IndentContext, pos: number): number {
    const doc = context.state.doc
    const line = context.lineAt(pos)
    const lineNumber = doc.lineAt(line.from).number
    const currentIndent = leadingIndentColumns(line.text)
    const trimmed = line.text.trim()

    if (trimmed === "" && doc) {
      const previous = previousNonBlankLine(doc, lineNumber)
      if (previous && startsWithClosingDelimiter(previous.text)) {
        return Math.max(0, leadingIndentColumns(previous.text) - INDENT_WIDTH)
      }

      if (previous && isSingleOpeningDelimiter(previous.text)) {
        return leadingIndentColumns(previous.text)
      }

      if (previous && opensIndentedBlock(previous.text)) {
        return leadingIndentColumns(previous.text) + INDENT_WIDTH
      }

      const next = nextNonBlankLine(doc, lineNumber)
      if (next && leadingIndentColumns(next.text) <= currentIndent) {
        return leadingIndentColumns(next.text)
      }

      if (previous) return leadingIndentColumns(previous.text)
      return 0
    }

    if (isSingleOpeningDelimiter(line.text)) return currentIndent
    if (opensIndentedBlock(line.text)) return currentIndent + INDENT_WIDTH
    return currentIndent
  }

  runTabIndent(view: EditorView, outdent: boolean): boolean {
    if (this.readOnly) return false

    if (acceptCompletion(view)) return true

    if (outdent) return indentLess(view)
    if (!view.state.selection.ranges.every(range => range.empty)) return indentSelection(view)

    view.dispatch(
      view.state.changeByRange(range => {
        const line = view.state.doc.lineAt(range.head)
        const column = range.head - line.from
        const spaces = nextIndentStop(column) - column
        return {
          changes: {from: range.head, insert: " ".repeat(spaces)},
          range: EditorSelection.cursor(range.head + spaces)
        }
      })
    )
    return true
  }

  runManualCompletion(view: EditorView): boolean {
    if (this.readOnly) return false
    startCompletion(view)
    return true
  }

  requestCompletions(): void {
    if (!this.view || this.readOnly) return
    startCompletion(this.view)
  }

  scheduleAutoCompletions(): void {
    if (!this.view || this.readOnly) return
    if (this.editorMode === "vim") return
    clearAppTimeout(this.autoCompletionTimer)

    const main = this.view.state.selection.main
    if (!main.empty) return

    if (!this.shouldAutoComplete()) return

    this.autoCompletionTimer = setTimeout(() => this.requestCompletions(), 120)
  }

  shouldAutoComplete(): boolean {
    if (!this.view) return false

    const cursor = this.view.state.selection.main.head
    const beforeCursor = this.getValue().slice(0, cursor)
    const trimmed = beforeCursor.replace(/\s+$/, "")

    if (trimmed.endsWith(".") || trimmed.endsWith("(")) return true

    const prefix = this.currentCompletionPrefix()
    return prefix.length >= 1
  }

  currentCompletionPrefix() {
    if (!this.view) return ""
    const cursor = this.view.state.selection.main.head
    const content = this.getValue()
    const prefix = content.slice(0, cursor)
    if (prefix.endsWith(".")) return "."
    const match = prefix.match(/([A-Za-z_][A-Za-z0-9_']*)$/)
    return match ? match[1] : ""
  }

  cursorOffsetFromEvent(event: MouseEvent): number {
    if (!this.view) return 0
    const pos = this.view.posAtCoords({x: event.clientX, y: event.clientY})
    if (typeof pos === "number") return pos
    return this.view.state.selection.main.head
  }

  handleContextMenu(event: MouseEvent): void {
    if (!this.contextMenuEvent || !this.view) return
    event.preventDefault()
    const offset = this.cursorOffsetFromEvent(event)
    this.hook.pushEvent(this.contextMenuEvent, {x: event.clientX, y: event.clientY, offset})
  }

  handleClick(event: MouseEvent): void {
    if (!this.view) return
    if (this.contextMenuEvent && event.ctrlKey) {
      event.preventDefault()
      const offset = this.cursorOffsetFromEvent(event)
      this.hook.pushEvent(this.contextMenuEvent, {x: event.clientX, y: event.clientY, offset})
      return
    }
    this.reportEditorState()
  }

  handleKeydown(event: KeyboardEvent): void {
    if (event.key === "Enter" && !event.metaKey && !event.ctrlKey && !event.altKey && !event.isComposing) {
      this.pendingEnterIndent = true
    }
  }

  handleSemanticDomKeydown(event: KeyboardEvent): boolean {
    if (this.readOnly || event.defaultPrevented) return false
    if (event.metaKey || event.ctrlKey || event.altKey || event.isComposing) return false

    return false
  }

  focusPosition({line, column}: {line: number; column: number}): void {
    if (!this.view || !Number.isInteger(line) || !Number.isInteger(column)) return
    const doc = this.view.state.doc
    const safeLine = clamp(line, 1, doc.lines)
    const lineInfo = doc.line(safeLine)
    const safeColumn = Math.max(1, column)
    const offsetInLine = clamp(safeColumn - 1, 0, lineInfo.length)
    const offset = lineInfo.from + offsetInLine
    this.view.dispatch({selection: {anchor: offset}, scrollIntoView: true})
    this.view.focus()
  }

  restoreState({cursor_offset, scroll_top, scroll_left}: EditorRestoreState): void {
    if (!this.view) return
    const len = this.view.state.doc.length
    const offset = clamp(Number(cursor_offset || 0), 0, len)
    this.restoringState = true
    this.view.dispatch({selection: {anchor: offset}})
    this.restoreScrollPosition(scroll_top, scroll_left)
  }

  restoreScrollPosition(scrollTop: number, scrollLeft: number): void {
    const top = Math.max(0, Number(scrollTop || 0))
    const left = Math.max(0, Number(scrollLeft || 0))
    let attempts = 0
    const apply = () => {
      if (!this.view) return
      attempts += 1
      this.view.requestMeasure({
        read: () => null,
        write: () => {
          if (!this.view) return
          this.view.scrollDOM.scrollTop = top
          this.view.scrollDOM.scrollLeft = left
          if (attempts < 4) {
            window.requestAnimationFrame(apply)
          } else {
            window.requestAnimationFrame(() => {
              this.restoringState = false
            })
          }
        }
      })
    }
    window.requestAnimationFrame(apply)
  }

  restoreStateFromDataset(docLength = 0): EditorRestoreState {
    const len = Math.max(0, Number(docLength || 0))
    return {
      cursor_offset: clamp(Number(this.el.dataset.restoreCursorOffset || 0), 0, len),
      scroll_top: Number(this.el.dataset.restoreScrollTop || 0),
      scroll_left: Number(this.el.dataset.restoreScrollLeft || 0)
    }
  }

  updated() {
    if (!this.view) return

    if (this.el.dataset.tabId !== this.tabId) {
      this.tabId = this.el.dataset.tabId
      this.restoreState(this.restoreStateFromDataset(this.view.state.doc.length))
    } else {
      this.tabId = this.el.dataset.tabId
    }

    const nextMode = safeLower(this.el.dataset.editorMode) === "vim" ? "vim" : "regular"
    if (nextMode !== this.editorMode) {
      this.editorMode = nextMode
      this.view.dispatch({
        effects: [
          this.modeCompartment.reconfigure(this.modeExtension()),
          this.keymapCompartment.reconfigure(keymap.of(this.sharedKeymapBindings()))
        ]
      })
      this.updateModeBadge()
      this.syncEditorPresentation()
      this.bindVimInstance()
      if (this.view) closeCompletion(this.view)
    }

    const nextTheme = parseEditorTheme(this.el.dataset.editorTheme)
    const nextLineNumbers = parseBooleanDataset(this.el.dataset.editorLineNumbers, true)
    const nextActiveLineHighlight = parseBooleanDataset(
      this.el.dataset.editorActiveLineHighlight,
      true
    )

    const effects = []

    if (nextTheme !== this.editorTheme) {
      this.editorTheme = nextTheme
      effects.push(this.themeCompartment.reconfigure(this.themeExtension()))
    }

    if (nextLineNumbers !== this.editorLineNumbers) {
      this.editorLineNumbers = nextLineNumbers
      effects.push(this.lineNumbersCompartment.reconfigure(this.lineNumbersExtension()))
    }

    if (nextActiveLineHighlight !== this.editorActiveLineHighlight) {
      this.editorActiveLineHighlight = nextActiveLineHighlight
      effects.push(this.activeLineCompartment.reconfigure(this.activeLineExtension()))
    }

    if (effects.length > 0) this.view.dispatch({effects})

    this.bindVimInstance()
  }

  applyServerEdit({
    replace_from,
    replace_to,
    inserted_text,
    cursor_start,
    cursor_end
  }: {
    replace_from: number
    replace_to: number
    inserted_text: string
    cursor_start?: number
    cursor_end?: number
  }): void {
    if (!this.view) return
    if (!Number.isInteger(replace_from) || !Number.isInteger(replace_to)) return
    if (typeof inserted_text !== "string") return

    const len = this.view.state.doc.length
    const from = clamp(replace_from, 0, len)
    const to = clamp(replace_to, from, len)
    const nextLen = len - (to - from) + inserted_text.length
    const start = clamp(Number(cursor_start ?? from), 0, nextLen)
    const end = clamp(Number(cursor_end ?? start), 0, nextLen)

    this.view.dispatch({
      changes: {from, to, insert: inserted_text},
      selection: {anchor: start, head: end},
      scrollIntoView: true
    })
    this.syncHiddenInput()
  }

  destroy(): void {
    clearAppTimeout(this.idleTimer)
    clearAppTimeout(this.changeTimer)
    clearAppTimeout(this.autoCompletionTimer)
    clearAppTimeout(this.lspFoldTimer)
    clearAppTimeout(this.scrollStateTimer)
    this.reportEditorState()
    this.unbindDomEvents()
    if (this.lspClient) this.lspClient.disconnect()
    if (this.lspTransport) this.lspTransport.destroy()
    if (this.view) this.view.destroy()
  }
}
