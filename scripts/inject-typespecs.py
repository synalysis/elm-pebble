#!/usr/bin/env python3
"""Insert missing @spec attributes using guard/name heuristics and package Types hubs."""

from __future__ import annotations

import argparse
import os
import re
import sys
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path

PACKAGES = ("elm_ex", "elmc", "elmx", "ide")

META_SKIP = frozenset(
    {
        "@doc",
        "@moduledoc",
        "@impl",
        "@dialyzer",
        "@deprecated",
        "@since",
        "@behaviour",
        "@before_compile",
    }
)

DEF_START = re.compile(
    r"^(\s*)(def|defmacro|defmacrop|defp|defmacro)\s+([a-zA-Z_][\w!?]*)\s*"
)
DEF_HEAD = re.compile(
    r"^(\s*)(def|defmacro|defmacrop|defp|defmacro)\s+([a-zA-Z_][\w!?]*)\s*"
    r"(?:\(([^)]*)\)|\s*(?:do|,|\\|\s*$))"
)
SPEC_LINE = re.compile(r"^\s*@spec\s+")
GUARD_RE = re.compile(r"\bwhen\s+(.+)$")


def write_ex_file(path: Path, content: str) -> None:
    path.chmod(path.stat().st_mode | 0o200)
    path.write_text(content, encoding="utf-8")


def parse_def_clause(lines: list[str], i: int) -> tuple[Clause | None, int]:
    m = DEF_START.match(lines[i])
    if not m:
        return None, i + 1

    indent, kind, name = m.group(1), m.group(2), m.group(3)
    rest = lines[i][m.end() :].strip()
    params_raw = ""
    guards: list[str] = []

    if rest.startswith("<<"):
        # Binary pattern heads are a single argument (optionally followed by more
        # args after `>>, ...`). Never treat `name::size` segments as params.
        depth = 0
        j = i
        col_start = m.end()
        while j < len(lines):
            line = lines[j][col_start if j == i else 0 :]
            idx = 0
            while idx < len(line):
                if line.startswith("<<", idx):
                    depth += 1
                    idx += 2
                    continue
                if line.startswith(">>", idx) and depth > 0:
                    depth -= 1
                    idx += 2
                    if depth == 0:
                        tail = line[idx:].strip()
                        params = ["_bin"]
                        if tail.startswith(","):
                            extra = tail[1:]
                            # strip trailing do/when from extra arg list
                            extra = re.split(r"\s+\bwhen\b|\s+\bdo\b|,?\s*$", extra, maxsplit=1)[0]
                            # If more args remain on this head, parse them
                            # e.g. defp foo(<<x>>, y, z)
                            more = split_params(extra.strip().rstrip(","))
                            # more may still include "do" junk — filter empties
                            more = [p for p in more if p and p not in ("do", "do:")]
                            params.extend(more)
                        gm = GUARD_RE.search(lines[i] + (" " + tail if tail else ""))
                        guards = [gm.group(1)] if gm else []
                        return (
                            Clause(
                                kind=kind,
                                name=name,
                                params=params,
                                guards=guards,
                                line=i,
                                indent=indent,
                            ),
                            j + 1,
                        )
                    continue
                idx += 1
            j += 1
    elif rest.startswith("(") or rest.startswith("%{"):
        depth_paren = 0
        depth_brace = 0
        depth_bin = 0
        in_string = None
        started = False
        buf: list[str] = []
        j = i
        while j < len(lines):
            col_start = m.end() if j == i else 0
            chunk = lines[j][col_start:]
            k = 0
            while k < len(chunk):
                # Inside string literals, ignore depth and char-literal rules.
                if in_string is not None:
                    if chunk[k] == "\\" and k + 1 < len(chunk):
                        buf.append(chunk[k])
                        buf.append(chunk[k + 1])
                        k += 2
                        continue
                    buf.append(chunk[k])
                    if chunk[k] == in_string:
                        in_string = None
                    k += 1
                    continue
                # Elixir char literal ?x / ?\n / ?{ / ?} — only when `?` is not
                # part of an identifier (names may end with `?`, e.g. skip_default?).
                if chunk[k] == "?" and k + 1 < len(chunk):
                    prev = chunk[k - 1] if k > 0 else ""
                    if not (prev.isalnum() or prev == "_"):
                        buf.append(chunk[k])
                        buf.append(chunk[k + 1])
                        k += 2
                        continue
                if chunk.startswith("<<", k):
                    depth_bin += 1
                    started = True
                    buf.append("<<")
                    k += 2
                    continue
                if chunk.startswith(">>", k) and depth_bin > 0:
                    depth_bin -= 1
                    buf.append(">>")
                    k += 2
                    continue
                ch = chunk[k]
                if depth_bin == 0 and ch in ('"', "'"):
                    in_string = ch
                    buf.append(ch)
                    k += 1
                    continue
                # While inside <<...>>, ignore paren/brace depth (binary may contain
                # quoted ")" / "}" without closing the function head).
                if depth_bin > 0:
                    buf.append(ch)
                    k += 1
                    continue
                if ch == "(":
                    depth_paren += 1
                    started = True
                elif ch == ")":
                    depth_paren -= 1
                elif ch == "{":
                    depth_brace += 1
                    started = True
                elif ch == "}":
                    depth_brace -= 1
                if (
                    started
                    and depth_paren <= 0
                    and depth_brace <= 0
                    and depth_bin <= 0
                    and ch in ")}"
                ):
                    params_raw = "".join(buf)
                    # tail after closing paren/brace on this line
                    tail = chunk[k + 1 :].strip()
                    gm = GUARD_RE.search(lines[i] if not tail else lines[i] + " " + tail)
                    guards = [gm.group(1)] if gm else []
                    clause = Clause(
                        kind=kind,
                        name=name,
                        params=split_params(params_raw),
                        guards=guards,
                        line=i,
                        indent=indent,
                    )
                    return clause, j + 1
                if depth_paren > 1 or depth_brace > 1:
                    buf.append(ch)
                elif depth_paren == 1 and depth_brace == 0 and ch not in "()":
                    buf.append(ch)
                elif depth_brace == 1 and depth_paren == 0 and ch not in "{}":
                    buf.append(ch)
                elif depth_paren >= 1 and depth_brace >= 1:
                    buf.append(ch)
                k += 1
            j += 1
        i = j - 1
    elif rest and not rest.startswith("do") and not rest.startswith(","):
        # zero-arg with trailing content on same line handled by DEF_HEAD fallback
        pass

    gm = GUARD_RE.search(lines[i] if not rest else lines[i] + " " + rest)
    if gm:
        guards.append(gm.group(1))

    clause = Clause(
        kind=kind,
        name=name,
        params=split_params(params_raw),
        guards=guards,
        line=i,
        indent=indent,
    )
    return clause, i + 1


@dataclass
class Clause:
    kind: str
    name: str
    params: list[str]
    guards: list[str]
    line: int
    indent: str


@dataclass
class FnGroup:
    kind: str
    name: str
    clauses: list[Clause] = field(default_factory=list)
    first_line: int = 0
    indent: str = "  "
    has_spec: bool = False
    existing_spec: str | None = None


# Parameter name -> type hints (suffix match or exact)
PARAM_HINTS: list[tuple[str, str]] = [
    ("module_name", "String.t()"),
    ("module", "String.t()"),
    ("name", "String.t()"),
    ("target", "String.t()"),
    ("source", "String.t()"),
    ("path", "String.t()"),
    ("key", "String.t()"),
    ("tag", "String.t()"),
    ("label", "String.t()"),
    ("text", "String.t()"),
    ("msg", "String.t()"),
    ("kind", "atom()"),
    ("op", "atom()"),
    ("opts", "keyword()"),
    ("options", "keyword()"),
    ("env", "Types.compile_env()"),
    ("compile_env", "Types.compile_env()"),
    ("decl", "Types.decl()"),
    ("decl_map", "Types.decl_map()"),
    ("expr", "Types.expr()"),
    ("ir_expr", "Types.ir_expr()"),
    ("pattern", "Types.pattern()"),
    ("module_t", "Types.module_t()"),
    ("ir", "Types.t()"),
    ("diagnostic", "Types.diagnostic()"),
    ("diagnostics", "[Types.diagnostic()]"),
    ("args", "[String.t()]"),
    ("arity", "non_neg_integer()"),
    ("index", "non_neg_integer()"),
    ("line", "pos_integer()"),
    ("col", "non_neg_integer()"),
    ("depth", "non_neg_integer()"),
    ("count", "non_neg_integer()"),
    ("value", "integer()"),
    ("n", "integer()"),
    ("i", "integer()"),
    ("acc", "term()"),
]


def package_types_alias(module: str, package: str) -> str | None:
    if package == "elm_ex":
        if module.startswith("ElmEx.IR"):
            return "ElmEx.IR.Types"
        if module.startswith("ElmEx.CoreIR"):
            return "ElmEx.CoreIR.Types"
        if module.startswith("ElmEx.Frontend"):
            return "ElmEx.Frontend.AstContract.Types"
        if module.startswith("ElmEx.DebuggerContract"):
            return "ElmEx.DebuggerContract.Types"
        return "ElmEx.Types"
    if package == "elmc":
        if "CCodegen" in module:
            return "Elmc.Backend.CCodegen.Types"
        if "Plan" in module:
            return "Elmc.Backend.Plan.Types"
        if "Bytecode" in module:
            return "Elmc.Backend.Bytecode.Artifacts.Types"
        if module.startswith("Elmc.CLI"):
            return "Elmc.CLI.Types"
        return "Elmc.Types"
    if package == "elmx":
        return "Elmx.Types"
    if package == "ide":
        if module.startswith("IdeWeb"):
            return "IdeWeb.Types"
        if module.startswith("Ide.Debugger"):
            return "Ide.Debugger.Types"
        if module.startswith("Ide.Mcp"):
            return "Ide.Mcp.Types"
        if module.startswith("Ide.Emulator"):
            return "Ide.Emulator.Types"
        if module.startswith("Ide.Projects"):
            return "Ide.Projects.Types"
        return "Ide.Types"
    return None


def parse_module_name(text: str) -> str | None:
    m = re.search(r"^defmodule\s+([\w.]+)\s+do", text, re.M)
    return m.group(1) if m else None


def split_params(raw: str | None) -> list[str]:
    if not raw or not raw.strip():
        return []
    parts: list[str] = []
    depth = 0
    cur: list[str] = []
    i = 0
    s = raw
    in_string = None
    while i < len(s):
        ch = s[i]
        if in_string is not None:
            cur.append(ch)
            if ch == "\\" and i + 1 < len(s):
                cur.append(s[i + 1])
                i += 2
                continue
            if ch == in_string:
                in_string = None
            i += 1
            continue
        if ch in ('"', "'"):
            in_string = ch
            cur.append(ch)
            i += 1
            continue
        if ch == "<" and i + 1 < len(s) and s[i + 1] == "<":
            depth += 1
            cur.append("<<")
            i += 2
            continue
        if ch == ">" and i + 1 < len(s) and s[i + 1] == ">" and depth > 0:
            depth -= 1
            cur.append(">>")
            i += 2
            continue
        if ch in "([{":
            depth += 1
            cur.append(ch)
            i += 1
            continue
        if ch in ")]}":
            depth -= 1
            cur.append(ch)
            i += 1
            continue
        if ch == "," and depth == 0:
            parts.append("".join(cur).strip())
            cur = []
            i += 1
            continue
        cur.append(ch)
        i += 1
    tail = "".join(cur).strip()
    if tail:
        parts.append(tail)
    return parts


def guard_type(guard: str, param: str) -> str | None:
    g = guard.strip()
    # is_binary(x), is_map(x), etc.
    for typ, pat in [
        ("String.t()", rf"is_binary\(\s*{re.escape(param)}\s*\)"),
        ("map()", rf"is_map\(\s*{re.escape(param)}\s*\)"),
        ("list()", rf"is_list\(\s*{re.escape(param)}\s*\)"),
        ("integer()", rf"is_integer\(\s*{re.escape(param)}\s*\)"),
        ("float()", rf"is_float\(\s*{re.escape(param)}\s*\)"),
        ("boolean()", rf"is_boolean\(\s*{re.escape(param)}\s*\)"),
        ("atom()", rf"is_atom\(\s*{re.escape(param)}\s*\)"),
        ("pid()", rf"is_pid\(\s*{re.escape(param)}\s*\)"),
        ("reference()", rf"is_reference\(\s*{re.escape(param)}\s*\)"),
        ("non_neg_integer()", rf"is_non_neg_integer\(\s*{re.escape(param)}\s*\)"),
        ("pos_integer()", rf"is_pos_integer\(\s*{re.escape(param)}\s*\)"),
        ("String.t()", rf"is_binary\(\s*{re.escape(param)}\s*\)"),
    ]:
        if re.search(pat, g):
            return typ
    # binary pattern
    if re.search(rf"%\{{.*\}}\s*=\s*{re.escape(param)}\b", g):
        return "map()"
    if re.search(rf"%\w+\{{.*\}}\s*=\s*{re.escape(param)}\b", g):
        return "map()"
    if re.search(rf"\[\s*.*\s*\|\s*{re.escape(param)}\s*\]", g):
        return "list()"
    return None


def param_name_type(param: str, module: str, package: str) -> str:
    base = param.split("::")[0].strip()
    # strip default
    if "=" in base:
        base = base.split("=")[0].strip()
    # pattern bindings
    if base.startswith("<<") or base in ("_bin", "_pattern"):
        return "binary()"
    if base.startswith("%"):
        return "map()"
    if base.startswith("{") or base.startswith("["):
        return "term()"
    if base in ("_",):
        return "term()"
    for hint, typ in PARAM_HINTS:
        if base == hint or base.endswith("_" + hint) or base.endswith(hint):
            return typ
    if base.endswith("?"):
        return "boolean()"
    if base.endswith("_map"):
        return "map()"
    if base.endswith("_list") or base.endswith("s"):
        if base in ("args", "opts", "options", "branches", "clauses", "fields", "items"):
            return "list()"
    if "name" in base or "path" in base or "module" in base or "target" in base:
        return "String.t()"
    if "expr" in base or base in ("left", "right", "cond", "body", "subject", "node"):
        types_mod = package_types_alias(module, package)
        if types_mod:
            if package == "elmc":
                return "Types.ir_expr()"
            return "Types.expr()"
    if "pattern" in base:
        return "Types.pattern()"
    if "decl" in base:
        if package == "elmc":
            return "Types.decl()"
        if package == "elm_ex":
            return "Types.declaration()"
    if package == "elm_ex" and base in ("map", "node", "ast", "contract"):
        return "Types.expr()"
    return default_type(package, module)


def default_type(package: str, module: str) -> str:
    if package == "elm_ex":
        if module and ("IR" in module or "Frontend" in module or "CoreIR" in module):
            return "Types.expr()"
        return "term()"
    if package == "elmc":
        return "Types.ir_expr()"
    if package == "elmx":
        return "Types.elm_value()"
    return "term()"


def infer_return(name: str, clauses: list[Clause], package: str, module: str) -> str:
    if name.endswith("?"):
        return "boolean()"
    if name.startswith("maybe_") or name.startswith("try_"):
        return default_type(package, module) + " | nil"
    if name.startswith("normalize") or name.startswith("rewrite") or name.startswith("desugar"):
        if clauses and clauses[0].params:
            return infer_param_type(clauses[0].params[0], clauses, module, package)
        return default_type(package, module)
    if name in ("ok?", "present?", "empty?", "valid?"):
        return "boolean()"
    if name in ("to_string", "inspect", "format", "macro_name", "ident", "sanitize"):
        return "String.t()"
    if name in ("to_list", "keys", "values"):
        if package == "elmx":
            return "Types.elm_list()"
        return "[term()]"
    return default_type(package, module)


def merge_types(types: list[str]) -> str:
    uniq = []
    for t in types:
        if t not in uniq:
            uniq.append(t)
    if len(uniq) == 1:
        return uniq[0]
    return " | ".join(uniq)


def infer_param_type(param: str, clauses: list[Clause], module: str, package: str) -> str:
    types: list[str] = []
    base = param.split("=")[0].strip()
    for clause in clauses:
        for g in clause.guards:
            gt = guard_type(g, base)
            if gt:
                types.append(gt)
    if not types:
        types.append(param_name_type(param, module, package))
    return merge_types(types)


def build_spec(group: FnGroup, module: str, package: str) -> str:
    arg_types = [
        infer_param_type(p, group.clauses, module, package) for p in group.clauses[0].params
    ] if group.clauses else []
    # multi-clause arity 0 with different heads — use first clause params only
    if len(group.clauses) > 1:
        max_params = max(len(c.params) for c in group.clauses)
        arg_types = []
        for i in range(max_params):
            ptypes = []
            for c in group.clauses:
                if i < len(c.params):
                    ptypes.append(infer_param_type(c.params[i], [c], module, package))
            arg_types.append(merge_types(ptypes))

    ret = infer_return(group.name, group.clauses, package, module)
    args = ", ".join(arg_types)
    return f"@spec {group.name}({args}) :: {ret}"


def find_spec_before(lines: list[str], line_idx: int) -> str | None:
    j = line_idx - 1
    while j >= 0:
        s = lines[j].strip()
        if not s or s.startswith("#") or s.startswith('"""') or s.startswith("'''"):
            j -= 1
            continue
        if any(s.startswith(m) for m in META_SKIP):
            j -= 1
            continue
        if s.startswith("@spec"):
            return s
        return None
    return None


def find_spec_for_function(lines: list[str], line_idx: int, name: str) -> str | None:
    spec = find_spec_before(lines, line_idx)
    if spec and f"{name}(" in spec:
        return spec
    j = line_idx - 1
    while j >= 0:
        stripped = lines[j].strip()
        if stripped.startswith(f"@spec {name}("):
            return stripped
        if DEF_START.match(lines[j]):
            break
        j -= 1
    return None


def parse_functions(lines: list[str]) -> list[FnGroup]:
    groups: dict[tuple[str, str], FnGroup] = {}
    order: list[tuple[str, str]] = []

    i = 0
    while i < len(lines):
        line = lines[i]
        m = DEF_START.match(line)
        if not m:
            i += 1
            continue

        clause, next_i = parse_def_clause(lines, i)
        if clause is None:
            i += 1
            continue
        # Macro-generated heads like `def unquote(name)(...)` are not real functions.
        if clause.name == "unquote":
            i = next_i
            continue

        key = (clause.kind, clause.name)
        if key not in groups:
            groups[key] = FnGroup(
                kind=clause.kind, name=clause.name, first_line=i, indent=clause.indent
            )
            order.append(key)
        groups[key].clauses.append(clause)
        spec = find_spec_for_function(lines, i, clause.name)
        if spec:
            groups[key].has_spec = True
            groups[key].existing_spec = spec
        elif i < groups[key].first_line:
            groups[key].first_line = i
        i = next_i

    return [groups[k] for k in order]


def ensure_types_alias(lines: list[str], module: str, package: str, needs_types: bool) -> list[str]:
    if not needs_types:
        return lines
    types_mod = package_types_alias(module, package)
    if not types_mod:
        return lines
    alias_line = f"  alias {types_mod}, as: Types"
    # Only treat a real module-level alias as present (not text inside heredocs/docs).
    has_alias = False
    in_heredoc = False
    for line in lines:
        if '"""' in line:
            # toggle for each """ occurrence on the line
            count = line.count('"""')
            if count % 2 == 1:
                in_heredoc = not in_heredoc
        if in_heredoc:
            continue
        if re.search(r"\balias\s+.+\s+as:\s*Types\b", line) or re.search(
            r"\balias\s+[\w.]+\.Types\b", line
        ):
            has_alias = True
            break
    if has_alias:
        return lines
    # insert after moduledoc / after defmodule line
    insert_at = 0
    for i, line in enumerate(lines):
        if line.strip().startswith("defmodule "):
            insert_at = i + 1
            break
    # skip moduledoc block (false/true one-liners OR heredoc)
    j = insert_at
    while j < len(lines):
        s = lines[j].strip()
        if s.startswith("@moduledoc"):
            # @moduledoc false / true / "..." on one line
            if '"""' not in s or s.count('"""') >= 2:
                j += 1
                break
            # heredoc moduledoc
            j += 1
            while j < len(lines) and '"""' not in lines[j]:
                j += 1
            if j < len(lines):
                j += 1
            break
        if s and not s.startswith("#"):
            break
        j += 1
    insert_at = j
    new_lines = lines[:insert_at] + [alias_line, ""] + lines[insert_at:]
    return new_lines


def inject_file(path: Path, package: str, dry_run: bool) -> int:
    text = path.read_text(encoding="utf-8", errors="ignore")
    if "@type " in text and not DEF_HEAD.search(text):
        return 0
    module = parse_module_name(text) or ""
    lines = text.splitlines()
    groups = parse_functions(lines)
    missing = [g for g in groups if not g.has_spec]
    if not missing:
        return 0

    # build insertions line -> spec lines (reverse order to preserve indices)
    insertions: dict[int, list[str]] = {}
    needs_types = False
    for g in missing:
        spec = build_spec(g, module, package)
        if "Types." in spec:
            needs_types = True
        insertions.setdefault(g.first_line, []).append(spec)

    new_lines = list(lines)
    for line_idx in sorted(insertions.keys(), reverse=True):
        specs = insertions[line_idx]
        indent = new_lines[line_idx][: len(new_lines[line_idx]) - len(new_lines[line_idx].lstrip())]
        block = [indent + s for s in specs] + [""]
        new_lines[line_idx:line_idx] = block

    if any(g for g in missing):
        new_lines = ensure_types_alias(new_lines, module, package, needs_types)

    if not dry_run:
        write_ex_file(
            path,
            "\n".join(new_lines) + ("\n" if text.endswith("\n") else ""),
        )
    return len(missing)


def tighten_broad_in_spec(spec: str, module: str, package: str) -> str:
    """Replace bare map/list/term/any only as standalone type tokens."""
    token = r"(?<![a-zA-Z0-9_.])({})\(\)"
    if package == "elm_ex":
        replacements = [
            (token.format("term"), "Types.expr()"),
            (token.format("any"), "Types.expr()"),
            (r"(?<![a-zA-Z0-9_.])(map)\(\)", "Types.declaration()"),
            (r"::\s*(?<![a-zA-Z0-9_.])(map)\(\)", ":: Types.declaration()"),
            (r"(?<![a-zA-Z0-9_.])(list)\(\)", "[Types.expr()]"),
        ]
    elif package == "elmc":
        replacements = [
            (token.format("term"), "Types.ir_expr()"),
            (token.format("any"), "Types.ir_expr()"),
            (r"::\s*(?<![a-zA-Z0-9_.])(map)\(\)", ":: Types.ir_expr()"),
            (r"(?<![a-zA-Z0-9_.])(map)\(\)", "Types.decl_map()"),
            (r"(?<![a-zA-Z0-9_.])(list)\(\)", "[Types.ir_expr()]"),
        ]
    elif package == "elmx":
        replacements = [
            (r"(?<![a-zA-Z0-9_.])(list)\(\)", "Types.elm_list()"),
            (r"(?<![a-zA-Z0-9_.])(map)\(\)", "Types.elm_dict()"),
            (token.format("term"), "Types.elm_value()"),
            (token.format("any"), "Types.elm_value()"),
        ]
    elif package == "ide":
        return spec
    else:
        return spec

    out = spec
    for pat, repl in replacements:
        out = re.sub(pat, repl, out)
    return out


def tighten_file(path: Path, package: str, dry_run: bool) -> int:
    text = path.read_text(encoding="utf-8", errors="ignore")
    module = parse_module_name(text) or ""
    lines = text.splitlines()
    changed = 0
    new_lines = []
    i = 0
    while i < len(lines):
        if SPEC_LINE.match(lines[i]):
            chunk = [lines[i]]
            j = i + 1
            while j < len(lines):
                s = lines[j].strip()
                if not s:
                    j += 1
                    continue
                if s.startswith("@") or DEF_START.match(lines[j]):
                    break
                if s.startswith("|") or "::" in s:
                    chunk.append(lines[j])
                    j += 1
                    continue
                break
            old = " ".join(chunk)
            new = tighten_broad_in_spec(old, module, package)
            if new != old:
                changed += 1
                # preserve first line indent
                indent = lines[i][: len(lines[i]) - len(lines[i].lstrip())]
                new_lines.append(indent + new.lstrip())
                i = j
                continue
        new_lines.append(lines[i])
        i += 1

    if changed and not dry_run:
        write_ex_file(
            path,
            "\n".join(new_lines) + ("\n" if text.endswith("\n") else ""),
        )
    return changed


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--package", required=True, choices=PACKAGES)
    parser.add_argument("--mode", choices=("inject", "tighten", "both"), default="both")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--file", type=Path, help="Single file under lib/")
    args = parser.parse_args()

    lib = args.root / args.package / "lib"
    files = [args.file] if args.file else sorted(lib.rglob("*.ex"))
    injected = tightened = 0

    for path in files:
        if "vendor" in path.parts:
            continue
        if args.mode in ("inject", "both"):
            injected += inject_file(path, args.package, args.dry_run)
        if args.mode in ("tighten", "both"):
            tightened += tighten_file(path, args.package, args.dry_run)

    action = "would" if args.dry_run else ""
    print(f"{args.package}: {action} inject {injected} specs, tighten {tightened} specs")
    return 0


if __name__ == "__main__":
    sys.exit(main())
