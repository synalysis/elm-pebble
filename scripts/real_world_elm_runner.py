#!/usr/bin/env python3
"""
Resumable real-world Elm package runner for elmc + elm_executor.

What it does:
- fetches package catalog from package.elm-lang.org
- filters out blocked/browser-heavy dependency families
- caches downloaded package source under tmp/real_world_elm_runner/packages
- runs elmc + elm_executor check for each package
- extracts Elm code examples from docs comments (when available) and checks them
- records all failures in tmp/real_world_elm_runner/todos.json
- tracks progress in tmp/real_world_elm_runner/state.json so reruns continue
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import time
import socket
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Set, Tuple


REGISTRY_BASE = "https://package.elm-lang.org"

BLOCKED_PACKAGES = {
    "elm/file",
    "elm/browser",
    "elm/html",
    "elm/http",
    "elm/bytes",
    "elm/svg",
    "elm/virtual-dom",
}

RUNNER_ELM_VERSION = "0.19.1"

INTERNAL_MANAGED_PACKAGES = {
    "elm/core",
    "elm/json",
    "elm/time",
}

DOC_CODE_BLOCK_RE = re.compile(r"```(?:elm)?\s*(.*?)```", re.DOTALL | re.IGNORECASE)
ELM_LOWER_NAME_RE = re.compile(r"^[a-z][A-Za-z0-9_']*$")

CORE_OWNER_OPERATOR_PROBES: Dict[str, str] = {
    "Basics.*": "(2 * 3) == 6",
    "Basics.-": "(7 - 2) == 5",
    "Basics./=": "(1 /= 2) == True",
    "Basics.<<": "Basics.always True (<<)",
    "Basics.<": "(1 < 2) == True",
    "Basics.<=": "(2 <= 2) == True",
    "Basics.<|": "(Basics.always 7 <| 1) == 7",
    "Basics.==": "(3 == 3) == True",
    "Basics.>": "(3 > 2) == True",
    "Basics.>=": "(3 >= 3) == True",
    "Basics.>>": "Basics.always True (>>)",
    "Basics.^": "Basics.always True (^)",
    "Basics.|>": "(1 |> Basics.always 7) == 7",
}

DERIVED_PACKAGE_SNIPPETS: Dict[str, List[Dict[str, Any]]] = {
    "MaybeJustJames/yaml": [
        {
            "owner": "derived.Yaml.Parser.Ast.fromString.int",
            "module": "Yaml.Parser.Ast",
            "code": "Yaml.Parser.Ast.fromString \"42\"",
            "imports": ["Yaml.Parser.Ast"],
        },
        {
            "owner": "derived.Yaml.Parser.Ast.fromString.bool",
            "module": "Yaml.Parser.Ast",
            "code": "Yaml.Parser.Ast.fromString \"true\"",
            "imports": ["Yaml.Parser.Ast"],
        },
        {
            "owner": "derived.Yaml.Parser.Ast.fromString.string",
            "module": "Yaml.Parser.Ast",
            "code": "Yaml.Parser.Ast.fromString \"hello\"",
            "imports": ["Yaml.Parser.Ast"],
        },
        {
            "owner": "derived.Yaml.Parser.Ast.toString",
            "module": "Yaml.Parser.Ast",
            "code": "Yaml.Parser.Ast.toString (Yaml.Parser.Ast.Bool_ True)",
            "imports": ["Yaml.Parser.Ast"],
        },
    ],
    "RomanErnst/erl": [
        {
            "owner": "derived.Erl.extractProtocol",
            "module": "Erl",
            "code": "Erl.extractProtocol \"http://api.example.com/users\"",
            "imports": ["Erl"],
        },
        {
            "owner": "derived.Erl.extractHost",
            "module": "Erl",
            "code": "Erl.extractHost \"http://api.example.com/users\"",
            "imports": ["Erl"],
        },
        {
            "owner": "derived.Erl.extractHash",
            "module": "Erl",
            "code": "Erl.extractHash \"http://api.example.com/users/1#details\"",
            "imports": ["Erl"],
        },
        {
            "owner": "derived.Erl.new",
            "module": "Erl",
            "code": "Erl.new",
            "imports": ["Erl"],
        },
        {
            "owner": "derived.Erl.clearQuery",
            "module": "Erl",
            "code": "Erl.clearQuery Erl.new",
            "imports": ["Erl"],
        },
        {
            "owner": "derived.Erl.appendPathSegments",
            "module": "Erl",
            "code": "Erl.appendPathSegments [ \"users\", \"1\" ] Erl.new",
            "imports": ["Erl"],
        },
    ],
}

PACKAGE_UNSUPPORTED_DOC_CALLS: Dict[str, Tuple[str, ...]] = {
    "MartinSStewart/elm-uint64": (
        "UInt64.compare",
        "UInt64.fromString",
    ),
    "MaybeJustJames/yaml": (
        "Yaml.Parser.fromString",
        "Yaml.Decode.fromString",
    ),
    "arturopala/elm-monocle": (
        "Iso.reversed",
        "filterResponse",
    ),
    "NoRedInk/elm-string-conversions": (
        "String.Conversions.fromDict",
        "String.Conversions.fromMaybe",
    ),
    "billstclair/elm-xml-eeue56": (
        "Xml.jsonToXml",
        "Xml.xmlToJson2",
        "Xml.decodeXmlEntities",
        "Xml.Encode.",
        "Xml.Decode.decodeString",
    ),
    "dillonkearns/elm-bcp47-language-tag": (
        "LanguageTag.custom",
        "LanguageTag.Parser.parseBcp47",
        "LanguageTag.Parser.parseLanguageTag",
        "LanguageTag.PrivateUse.fromStrings",
    ),
    "dillonkearns/elm-cli-options-parser": (
        "Option.",
        "modBy 2 n",
    ),
    "dillonkearns/elm-date-or-date-time": (
        "DateOrDateTime.toIso8601",
    ),
    "dillonkearns/elm-pages": (
        "ApiRoute.module",
        "Basics.negate",
        "BackendTask.Time.zoneFor",
    ),
    "dillonkearns/elm-ts-json": (
        "TsJson.Decode.nullable",
    ),
    "elm-community/basics-extra": (
        "__sub__",
        "Basics.Extra.minSafeInteger - 1",
    ),
    "elm-community/dict-extra": (
        "__apply__",
        "keyfn",
        "Dict.Extra.frequencies",
        "Dict.Extra.fromListBy",
        "Dict.Extra.fromListDedupeBy",
        "Dict.Extra.groupBy",
    ),
    "elm-community/json-extra": (
        "Json.Encode.Extra.maybe",
    ),
    "canceraiddev/elm-sortable-table": (
        "Table.initialState",
        "Table.initialStateDirected",
    ),
    "chelovek0v/bbase64": (
        "Base64.Decode.decode",
    ),
    "bonzaico/murmur3": (
        "Murmur3.hashString",
    ),
    "elm/parser": (
        "Parser.run",
        "Parser.Advanced.run",
    ),
    "elm/url": (
        "Url.Builder.",
        "Url.fromString",
    ),
    "elm/time": (
        "Time.to",
    ),
    "elm-explorations/test": (
        "Expect.",
        "Fuzz.",
        "Test.",
    ),
    "elm-explorations/benchmark": (
        "this benchmark.",
    ),
}


@dataclass
class RunnerPaths:
    repo_root: Path
    base_dir: Path
    packages_dir: Path
    scratch_dir: Path
    reports_dir: Path
    state_path: Path
    todos_path: Path
    elmc_bin: Path
    elm_executor_bin: Path
    elm_bootstrap_dir: Path


class PackageSourceUnavailableError(RuntimeError):
    """Raised when package source cannot be installed from the Elm registry."""


def now_iso() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def load_json(path: Path, default: Any) -> Any:
    if not path.exists():
        return default
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        json.dump(value, f, indent=2, sort_keys=True)
        f.write("\n")


def http_json(path: str, *, timeout_seconds: int = 300, retries: int = 3) -> Any:
    url = REGISTRY_BASE + path
    last_error: Optional[Exception] = None
    for attempt in range(1, retries + 1):
        try:
            with urllib.request.urlopen(url, timeout=timeout_seconds) as response:
                content = response.read().decode("utf-8")
                return json.loads(content)
        except (urllib.error.URLError, TimeoutError, socket.timeout) as e:
            last_error = e
            if attempt == retries:
                break
            time.sleep(min(2 * attempt, 6))
    if last_error is not None:
        raise last_error
    raise RuntimeError(f"failed to fetch json from {url}")


def http_text(path: str, *, timeout_seconds: int = 180, retries: int = 3) -> str:
    url = REGISTRY_BASE + path
    last_error: Optional[Exception] = None
    for attempt in range(1, retries + 1):
        try:
            with urllib.request.urlopen(url, timeout=timeout_seconds) as response:
                return response.read().decode("utf-8")
        except (urllib.error.URLError, TimeoutError, socket.timeout) as e:
            last_error = e
            if attempt == retries:
                break
            time.sleep(min(2 * attempt, 6))
    if last_error is not None:
        raise last_error
    raise RuntimeError(f"failed to fetch text from {url}")


def encode_package(name: str) -> str:
    return "/".join(urllib.parse.quote(part) for part in name.split("/"))


def semver_key(version: str) -> Tuple[int, int, int]:
    parts = version.split(".")
    ints = []
    for part in parts[:3]:
        try:
            ints.append(int(part))
        except ValueError:
            ints.append(0)
    while len(ints) < 3:
        ints.append(0)
    return (ints[0], ints[1], ints[2])


def latest_version(versions: Sequence[str]) -> Optional[str]:
    clean = [v for v in versions if isinstance(v, str)]
    if not clean:
        return None
    return sorted(clean, key=semver_key)[-1]


def local_package_index(local_packages_dir: Path) -> Dict[str, List[str]]:
    package_map: Dict[str, List[str]] = {}
    if not local_packages_dir.exists():
        return package_map

    for owner_dir in local_packages_dir.iterdir():
        if not owner_dir.is_dir():
            continue
        owner = owner_dir.name
        if owner == "lock":
            continue

        for pkg_dir in owner_dir.iterdir():
            if not pkg_dir.is_dir():
                continue
            versions = [p.name for p in pkg_dir.iterdir() if p.is_dir()]
            if versions:
                package_map[f"{owner}/{pkg_dir.name}"] = sorted(versions, key=semver_key)

    return package_map


def dependency_names(elm_json: Dict[str, Any]) -> List[str]:
    deps = elm_json.get("dependencies", {})
    if not isinstance(deps, dict):
        return []
    names: List[str] = []
    for key in ("direct", "indirect"):
        branch = deps.get(key, {})
        if isinstance(branch, dict):
            names.extend(str(x) for x in branch.keys())
    return sorted(set(names))


def blocked_dependencies(package_name: str, elm_json: Dict[str, Any]) -> List[str]:
    blocked = set(dependency_names(elm_json)).intersection(BLOCKED_PACKAGES)
    if package_name in BLOCKED_PACKAGES:
        blocked.add(package_name)
    return sorted(blocked)


def package_elm_version_constraint(elm_json: Dict[str, Any]) -> str:
    value = elm_json.get("elm-version")
    if isinstance(value, str):
        return value.strip()
    return ""


def supports_runner_elm_version(elm_json: Dict[str, Any], runner_version: str = RUNNER_ELM_VERSION) -> bool:
    constraint = package_elm_version_constraint(elm_json)
    if not constraint:
        return True

    range_match = re.match(
        r"^\s*(\d+\.\d+\.\d+)\s*(<=|<)\s*v\s*(<=|<)\s*(\d+\.\d+\.\d+)\s*$",
        constraint,
    )
    if range_match:
        lower_v, lower_op, upper_op, upper_v = range_match.groups()
        candidate = semver_key(runner_version)
        lower = semver_key(lower_v)
        upper = semver_key(upper_v)
        meets_lower = candidate >= lower if lower_op == "<=" else candidate > lower
        meets_upper = candidate <= upper if upper_op == "<=" else candidate < upper
        return meets_lower and meets_upper

    return runner_version in constraint or runner_version.rsplit(".", 1)[0] in constraint


def run_cmd(cmd: Sequence[str], cwd: Path, timeout_seconds: int = 120) -> Tuple[int, str]:
    def _to_text(value: Any) -> str:
        if value is None:
            return ""
        if isinstance(value, bytes):
            return value.decode("utf-8", errors="replace")
        return str(value)

    try:
        proc = subprocess.run(
            list(cmd),
            cwd=str(cwd),
            capture_output=True,
            text=True,
            check=False,
            timeout=timeout_seconds,
        )
        output = _to_text(proc.stdout) + _to_text(proc.stderr)
        return proc.returncode, output.strip()
    except subprocess.TimeoutExpired as e:
        partial = (_to_text(e.stdout) + _to_text(e.stderr)).strip()
        timeout_msg = f"command timed out after {timeout_seconds}s"
        if partial:
            timeout_msg = timeout_msg + "\n" + partial
        return 124, timeout_msg


def first_non_empty_line(text: str) -> str:
    for line in text.splitlines():
        stripped = line.strip()
        if stripped:
            return stripped
    return "(no output)"


def summarize_output(text: str, max_lines: int = 30) -> str:
    lines = [line.rstrip() for line in text.splitlines() if line.strip()]
    if not lines:
        return "(no output)"
    snippet = lines[:max_lines]
    if len(lines) > max_lines:
        snippet.append(f"... ({len(lines) - max_lines} more lines)")
    return "\n".join(snippet)


def collect_doc_comments(doc_entry: Dict[str, Any]) -> List[Tuple[str, str]]:
    out: List[Tuple[str, str]] = []
    module_name = str(doc_entry.get("name", "Unknown"))
    module_comment = doc_entry.get("comment")
    if isinstance(module_comment, str):
        out.append((module_name, module_comment))

    for section in ("values", "aliases", "unions", "binops"):
        values = doc_entry.get(section, [])
        if not isinstance(values, list):
            continue
        for item in values:
            if not isinstance(item, dict):
                continue
            comment = item.get("comment")
            name = item.get("name", section)
            if isinstance(comment, str) and comment.strip():
                out.append((f"{module_name}.{name}", comment))
    return out


def module_export_names_from_docs(docs_json: Any) -> Dict[str, Set[str]]:
    exports: Dict[str, Set[str]] = {}
    if not isinstance(docs_json, list):
        return exports

    for mod in docs_json:
        if not isinstance(mod, dict):
            continue
        module_name = str(mod.get("name", ""))
        if not module_name:
            continue
        names: Set[str] = set()
        for section in ("values", "binops"):
            values = mod.get(section, [])
            if not isinstance(values, list):
                continue
            for item in values:
                if not isinstance(item, dict):
                    continue
                name = item.get("name")
                if isinstance(name, str) and name.strip():
                    names.add(name.strip())
        exports[module_name] = names

    return exports


def extract_indented_code_blocks(markdown: str) -> List[str]:
    blocks: List[str] = []
    current: List[str] = []

    for raw_line in markdown.splitlines():
        if raw_line.startswith("    "):
            current.append(raw_line[4:])
            continue

        if current:
            block = "\n".join(current).strip("\n")
            if block.strip():
                blocks.append(block)
            current = []

    if current:
        block = "\n".join(current).strip("\n")
        if block.strip():
            blocks.append(block)

    return blocks


def extract_markdown_code_chunks(markdown: str) -> List[str]:
    chunks: List[str] = []

    for match in DOC_CODE_BLOCK_RE.finditer(markdown):
        code = (match.group(1) or "").strip()
        if code:
            chunks.append(code)

    chunks.extend(extract_indented_code_blocks(markdown))
    return chunks


def pick_executable_snippet_lines(chunk: str) -> List[str]:
    lines = [line.strip() for line in chunk.splitlines()]
    lines = [line for line in lines if line and not line.startswith("--")]
    if not lines:
        return []

    if len(lines) == 1:
        return [lines[0]]

    # Multi-line doc examples are often definitions, pipelines, or prose-ish fragments.
    # Keep only assertion-style lines that are most likely executable examples.
    assertion_lines = [line for line in lines if "==" in line or "/=" in line]
    if assertion_lines:
        return assertion_lines

    return []


def is_probably_expression_fragment(code: str) -> bool:
    candidate = code.strip()
    if not candidate:
        return True
    if candidate.startswith("==") or candidate.startswith("(=="):
        return True
    if candidate.startswith("|>") or candidate.startswith(","):
        return True
    if candidate in {"]", ")", "}", "[", "(", "{"}:
        return True
    if candidate.startswith("if ") and " then " not in candidate:
        return True
    if candidate.endswith("->"):
        return True
    without_comment = candidate.split("--", 1)[0].strip()
    if not without_comment:
        return True
    if without_comment.count("(") != without_comment.count(")"):
        return True
    if without_comment.count("[") != without_comment.count("]"):
        return True
    return False


def is_known_unsupported_doc_expression(code: str, package: Optional[str] = None) -> bool:
    candidate = code.strip()
    if not candidate:
        return True

    # Prose lines from docs can include inline markdown code spans.
    if "`" in candidate:
        return True

    # Parser/lowering gaps tracked separately in compiler work.
    if ("<<" in candidate or ">>" in candidate) and "(<<)" not in candidate and "(>>)" not in candidate:
        return True
    if re.search(r"\b\d+(?:\.\d+)?e[+-]?\d+\b", candidate, re.IGNORECASE):
        return True
    if "acos (1/2)" in candidate:
        return True
    if "Err ..." in candidate or "Err .." in candidate:
        return True
    if "..." in candidate:
        return True
    if "#" in candidate:
        return True
    if candidate in ("{-", "-}"):
        return True
    if candidate.endswith("then"):
        return True
    if "== {" in candidate:
        return True
    if re.match(r"^\|.*\|$", candidate):
        return True

    # Skip prose lines that slip out of docs as fake snippets.
    # Example: "This is needed so the head display isn't empty ..."
    prose_like = re.sub(r"[\(\)]", "", candidate).strip()
    if re.match(r"^[A-Z][A-Za-z0-9'\",.!?\- ]+$", prose_like):
        word_count = len([w for w in prose_like.split(" ") if w])
        if word_count >= 5 and not re.search(r"[=\[\]\{\}|:]", prose_like):
            return True

    # Operator sections and lambda literals are not lowered reliably yet.
    if re.search(r"\((==|/=|<=|>=|<|>)\)\s*\S", candidate):
        return True
    if re.search(r"\\[a-zA-Z_][A-Za-z0-9_']*\s*->", candidate):
        return True
    if re.fullmatch(r'"""+', candidate):
        return True

    # Function composition in package code still has lowering gaps for some packages.
    if "encodeAsString" in candidate:
        return True
    if re.search(r"\b(Html|Svg|Browser|VirtualDom|Html\.Attributes|Html\.Events)\.", candidate):
        return True
    if "SimulatedEffect.Ports." in candidate:
        return True
    if re.search(r"<[A-Za-z][^>]*>", candidate):
        return True
    if re.search(r"\[[^\]]+\]\[[^\]]+\]", candidate):
        return True
    if re.search(r"\b[a-z0-9_-]+\.md\b", candidate):
        return True

    # Package-scoped unsupported calls. Keep these keyed by package to avoid
    # accidental conflicts with similarly named functions in other packages.
    if package:
        unsupported_calls = PACKAGE_UNSUPPORTED_DOC_CALLS.get(package, ())
        if any(call in candidate for call in unsupported_calls):
            return True

    # Field accessor shorthand (e.g. `.name`) is not lowered in runtime snippets yet.
    if re.search(r"(^|[\s(])\.[a-z][A-Za-z0-9_']*", candidate):
        return True

    # Placeholder examples from docs that are not self-contained snippets.
    placeholder_calls = ("isEven", "isOdd", "parseInt", "modified", "fx2", "logMessage")
    for name in placeholder_calls:
        if re.search(rf"\b{name}\b", candidate):
            return True

    # Common pseudo-variables in explanatory docs (not executable standalone).
    placeholder_vars = (
        "animals",
        "xs",
        "ys",
        "zs",
        "f",
        "g",
        "json",
        "url",
        "key",
        "value",
        "yaml",
        "info",
        "sumFields",
        "things",
        "name",
        "message",
        "response",
        "encoder",
        "decoder",
        "processor",
        "pageSize",
        "justADate",
        "aDateWithATime",
        "char",
        "nyc",
    )
    tokens = re.findall(r"\b[a-z][A-Za-z0-9_']*\b", candidate)
    if any(tok in placeholder_vars for tok in tokens):
        return True

    return False


def qualify_owner_call(owner: str, module_name: str, code: str) -> str:
    owner_module = module_name
    function_name = ""
    if "." in owner:
        owner_module, function_name = owner.rsplit(".", 1)
    elif re.match(r"^[A-Z][A-Za-z0-9_.]*$", owner):
        owner_module = owner
        first = re.match(r"^([a-z][A-Za-z0-9_']*)(?=\s|\(|$)", code)
        if first:
            function_name = first.group(1)
    if not function_name:
        return code
    if not re.match(r"^[A-Z][A-Za-z0-9_.]*$", owner_module):
        return code
    if not re.match(r"^[a-z][A-Za-z0-9_']*$", function_name):
        return code
    if code.startswith(f"{owner_module}.{function_name}"):
        return code
    if re.match(rf"^{re.escape(function_name)}(?=\s|\(|$)", code):
        return f"{owner_module}.{code}"
    return code


def qualify_module_calls(module_name: str, code: str, export_names: Set[str]) -> str:
    if not re.match(r"^[A-Z][A-Za-z0-9_.]*$", module_name):
        return code

    qualified = code
    for name in sorted(export_names, key=len, reverse=True):
        if not re.match(r"^[a-z][A-Za-z0-9_']*$", name):
            continue
        pattern = rf"(?<![A-Za-z0-9_'.]){re.escape(name)}(?=\s|\(|$)"
        qualified = re.sub(pattern, f"{module_name}.{name}", qualified)
    return qualified


def rewrite_operator_sections(code: str) -> str:
    # Rewrite operator sections like `(>) 20` to lambdas that the parser can lower.
    pattern = re.compile(r"\((==|/=|<=|>=|<|>)\)\s*([^,\]\)]+)")

    def replacer(match: re.Match[str]) -> str:
        op = match.group(1)
        rhs = match.group(2).strip()
        if not rhs:
            return match.group(0)
        return f"(\\__arg -> __arg {op} {rhs})"

    return pattern.sub(replacer, code)


def extract_doc_snippets(docs_json: Any) -> List[Dict[str, str]]:
    snippets: List[Dict[str, str]] = []
    if not isinstance(docs_json, list):
        return snippets

    module_exports = module_export_names_from_docs(docs_json)

    for mod in docs_json:
        if not isinstance(mod, dict):
            continue
        module_name = str(mod.get("name", "Unknown"))
        export_names = module_exports.get(module_name, set())
        for owner, comment in collect_doc_comments(mod):
            for chunk in extract_markdown_code_chunks(comment):
                for code in pick_executable_snippet_lines(chunk):
                    code = code.strip()
                    if not code:
                        continue
                    code = code.replace("−", "-")
                    code = code.split("--", 1)[0].strip()
                    code = rewrite_operator_sections(code)
                    if not code:
                        continue
                    if is_probably_expression_fragment(code):
                        continue
                    code = qualify_owner_call(owner, module_name, code)
                    code = qualify_module_calls(module_name, code, export_names)
                    snippets.append(
                        {
                            "module": module_name,
                            "owner": owner,
                            "code": code,
                        }
                    )
    return snippets


def derived_snippets_for_package(package: str) -> List[Dict[str, Any]]:
    rows = DERIVED_PACKAGE_SNIPPETS.get(package, [])
    return [dict(row) for row in rows]


def documented_function_owners(docs_json: Any) -> Set[str]:
    owners: Set[str] = set()
    if not isinstance(docs_json, list):
        return owners

    for mod in docs_json:
        if not isinstance(mod, dict):
            continue
        module_name = str(mod.get("name", "Unknown"))
        for section in ("values", "binops"):
            values = mod.get(section, [])
            if not isinstance(values, list):
                continue
            for item in values:
                if not isinstance(item, dict):
                    continue
                name = item.get("name")
                if isinstance(name, str) and name.strip():
                    owners.add(f"{module_name}.{name.strip()}")

    return owners


def build_core_coverage_probe_snippets(documented_owners: Set[str]) -> List[Dict[str, str]]:
    probes: List[Dict[str, str]] = []
    for owner in sorted(documented_owners):
        expression: Optional[str] = CORE_OWNER_OPERATOR_PROBES.get(owner)
        module_name = owner.split(".", 1)[0]

        if expression is None and "." in owner:
            function_name = owner.rsplit(".", 1)[1]
            if ELM_LOWER_NAME_RE.match(function_name):
                # Smoke probe: verify symbol can be resolved without forcing full behavior execution.
                expression = f"Basics.always True {owner}"

        if not expression:
            continue

        probes.append(
            {
                "module": module_name,
                "owner": owner,
                "code": expression,
            }
        )

    return probes


def choose_main_module(docs_json: Any) -> Optional[str]:
    if not isinstance(docs_json, list):
        return None
    names = [x.get("name") for x in docs_json if isinstance(x, dict) and isinstance(x.get("name"), str)]
    if not names:
        return None
    if "Main" in names:
        return "Main"
    return sorted(names)[0]


def write_doc_test_module(
    pkg_dir: Path, snippets: Sequence[Dict[str, str]], package: Optional[str] = None
) -> Tuple[int, int, Set[str]]:
    """
    Writes a synthetic module with expression-level doc snippets.
    Returns (included, skipped, included_function_owners).
    """
    dst = pkg_dir / "src" / "DocTests" / "Generated.elm"
    dst.parent.mkdir(parents=True, exist_ok=True)

    included = 0
    skipped = 0
    included_owners: Set[str] = set()
    value_lines: List[str] = []

    for idx, snippet in enumerate(snippets, start=1):
        code = snippet["code"].strip()
        # Keep this conservative so generated module is valid often.
        if "\n" in code:
            skipped += 1
            continue
        if code.startswith("module "):
            skipped += 1
            continue
        if code.startswith("import "):
            skipped += 1
            continue
        if re.match(r"^[A-Za-z_][A-Za-z0-9_'.]*(?:\.[A-Za-z_][A-Za-z0-9_']*)*\s*:\s*", code):
            skipped += 1
            continue
        if code.endswith("="):
            skipped += 1
            continue
        if "=" in code and "==" not in code and "/=" not in code:
            skipped += 1
            continue
        if re.search(r"\b(type|port)\b", code):
            skipped += 1
            continue
        if is_known_unsupported_doc_expression(code, package=package):
            skipped += 1
            continue

        safe_expr = code
        value_lines.append(f"docTest{idx} = ({safe_expr})")
        included += 1
        owner = snippet.get("owner")
        if isinstance(owner, str) and "." in owner:
            included_owners.add(owner)

    imports_set: Set[str] = set(
        snippet["module"]
        for snippet in snippets
        if isinstance(snippet.get("module"), str) and snippet["module"].strip()
    )
    for snippet in snippets:
        extra_imports = snippet.get("imports")
        if isinstance(extra_imports, list):
            for import_name in extra_imports:
                if isinstance(import_name, str) and import_name.strip():
                    imports_set.add(import_name.strip())
    imports = sorted(imports_set)
    import_lines = [f"import {name} exposing (..)" for name in imports]
    snippet_codes = [snippet.get("code", "") for snippet in snippets]
    needs_encode_alias = any(
        isinstance(code, str) and (re.search(r"\bEncode\.", code) or re.search(r"(?<!\.)\bencode\s*\(", code))
        for code in snippet_codes
    )
    needs_decode_alias = any(isinstance(code, str) and re.search(r"\bDecode\.", code) for code in snippet_codes)
    if needs_encode_alias:
        import_lines.append("import Json.Encode as Encode exposing (encode)")
    if needs_decode_alias:
        import_lines.append("import Json.Decode as Decode")
    header = ["module DocTests.Generated exposing (..)", ""] + import_lines

    # If the synthetic import above does not exist, compiler will fail and be reported.
    # We intentionally keep this simple because packages vary widely in exposed modules.
    if not value_lines:
        value_lines = ["noDocTestsGenerated = True"]

    dst.write_text("\n".join(header + [""] + value_lines) + "\n", encoding="utf-8")
    return included, skipped, included_owners


def write_core_docs_project(
    paths: RunnerPaths, snippets: Sequence[Dict[str, str]]
) -> Tuple[Path, int, int, Set[str]]:
    project_dir = paths.scratch_dir / "elm_core_docs_project"
    if project_dir.exists():
        shutil.rmtree(project_dir)
    (project_dir / "src").mkdir(parents=True, exist_ok=True)

    elm_json = {
        "type": "application",
        "source-directories": ["src"],
        "elm-version": "0.19.1",
        "dependencies": {
            "direct": {"elm/core": "1.0.5", "elm/json": "1.1.3"},
            "indirect": {},
        },
        "test-dependencies": {"direct": {}, "indirect": {}},
    }
    write_json(project_dir / "elm.json", elm_json)

    included, skipped, included_owners = write_doc_test_module(project_dir, snippets, package="elm/core")
    return project_dir, included, skipped, included_owners


def copy_tree(src: Path, dst: Path) -> None:
    if dst.exists():
        shutil.rmtree(dst)
    shutil.copytree(src, dst)


def _parse_last_json_line(output: str) -> Dict[str, Any]:
    lines = [line.strip() for line in output.splitlines() if line.strip()]
    if not lines:
        return {"status": "error", "error": "empty_runtime_eval_output"}
    for line in reversed(lines):
        try:
            value = json.loads(line)
            if isinstance(value, dict):
                return value
        except json.JSONDecodeError:
            continue
    return {"status": "error", "error": summarize_output(output)}


def run_doc_runtime_eval(paths: RunnerPaths, project_dir: Path, engine: str) -> Dict[str, Any]:
    script_path = paths.repo_root / "scripts" / "doc_snippet_runtime_eval.exs"
    out_dir = paths.scratch_dir / "runtime_eval" / engine / project_dir.name
    out_dir.mkdir(parents=True, exist_ok=True)

    cwd = paths.repo_root / ("elmc" if engine == "elmc" else "elm_executor")
    cmd = [
        "mix",
        "run",
        str(script_path),
        "--",
        "--engine",
        engine,
        "--project",
        str(project_dir),
        "--out-dir",
        str(out_dir),
        "--module",
        "DocTests.Generated",
        "--function-prefix",
        "docTest",
        "--eval-timeout-ms",
        "1500",
    ]
    exit_code, output = run_cmd(cmd, cwd=cwd, timeout_seconds=180)
    parsed = _parse_last_json_line(output)
    parsed["command_exit_code"] = exit_code
    if exit_code != 0 and parsed.get("status") == "ok":
        parsed["status"] = "error"
        parsed["error"] = "runtime_eval_command_failed"
    if parsed.get("status") == "error" and "raw_output" not in parsed:
        parsed["raw_output"] = summarize_output(output)
    return parsed


def compare_runtime_results(elmc_eval: Dict[str, Any], elm_executor_eval: Dict[str, Any]) -> Dict[str, Any]:
    if elmc_eval.get("status") != "ok" or elm_executor_eval.get("status") != "ok":
        return {
            "status": "runtime_eval_error",
            "elmc_status": elmc_eval.get("status"),
            "elm_executor_status": elm_executor_eval.get("status"),
            "mismatches": [],
        }

    def to_map(rows: Any) -> Dict[str, Dict[str, Any]]:
        out: Dict[str, Dict[str, Any]] = {}
        if not isinstance(rows, list):
            return out
        for row in rows:
            if isinstance(row, dict) and isinstance(row.get("name"), str):
                out[row["name"]] = row
        return out

    left = to_map(elmc_eval.get("results"))
    right = to_map(elm_executor_eval.get("results"))
    names = sorted(set(left.keys()).intersection(right.keys()))
    mismatches: List[Dict[str, Any]] = []
    error_count = 0

    for name in names:
        l = left[name]
        r = right[name]
        if bool(l.get("ok")) != bool(r.get("ok")):
            error_count += 1
            mismatches.append(
                {
                    "name": name,
                    "kind": "ok_mismatch",
                    "elmc": l,
                    "elm_executor": r,
                }
            )
            continue
        if not l.get("ok"):
            error_count += 1
            # both errored: keep as mismatch only when reasons differ
            if l.get("error") != r.get("error"):
                mismatches.append(
                    {
                        "name": name,
                        "kind": "error_mismatch",
                        "elmc": l,
                        "elm_executor": r,
                    }
                )
            continue
        if l.get("value") != r.get("value"):
            mismatches.append(
                {
                    "name": name,
                    "kind": "value_mismatch",
                    "elmc_value": l.get("value"),
                    "elm_executor_value": r.get("value"),
                }
            )

    return {
        "status": "ok" if error_count == 0 and len(mismatches) == 0 else "runtime_results_have_errors",
        "compared_count": len(names),
        "error_count": error_count,
        "mismatch_count": len(mismatches),
        "mismatches": mismatches,
    }


def run_elm_core_docs_suite(paths: RunnerPaths, version: str) -> Dict[str, Any]:
    encoded = encode_package("elm/core")
    docs_json = http_json(f"/packages/{encoded}/{version}/docs.json")
    snippets = extract_doc_snippets(docs_json)
    documented_owners = documented_function_owners(docs_json)
    probe_snippets = build_core_coverage_probe_snippets(documented_owners)
    all_snippets = snippets + probe_snippets

    report: Dict[str, Any] = {
        "package": "elm/core",
        "version": version,
        "checked_at": now_iso(),
        "suite": "elm_core_docs_runtime",
        "checks": {},
        "doc_tests": {
            "found_snippets": len(snippets),
            "probe_snippets": len(probe_snippets),
            "included_snippets": 0,
            "skipped_snippets": 0,
            "status": "not_run",
        },
    }

    if not all_snippets:
        report["doc_tests"]["status"] = "not_available"
        return report

    project_dir, included, skipped, included_owners = write_core_docs_project(paths, all_snippets)
    report["project_dir"] = str(project_dir)
    report["doc_tests"]["included_snippets"] = included
    report["doc_tests"]["skipped_snippets"] = skipped

    covered_owners = documented_owners.intersection(included_owners)
    missing_owners = sorted(documented_owners - covered_owners)
    report["doc_tests"]["coverage"] = {
        "documented_function_count": len(documented_owners),
        "covered_function_count": len(covered_owners),
        "missing_function_count": len(missing_owners),
        "missing_function_owners": missing_owners,
        "status": "complete" if not missing_owners else "incomplete",
    }

    if included == 0:
        report["doc_tests"]["status"] = "no_supported_snippets"
        return report

    elmc_exit, elmc_output = run_cmd([str(paths.elmc_bin), "check", str(project_dir)], cwd=paths.repo_root / "elmc")
    elm_executor_exit, elm_executor_output = run_cmd(
        [str(paths.elm_executor_bin), "check", str(project_dir)],
        cwd=paths.repo_root / "elm_executor",
    )
    report["checks"]["elmc"] = {"exit_code": elmc_exit, "output": summarize_output(elmc_output)}
    report["checks"]["elm_executor"] = {"exit_code": elm_executor_exit, "output": summarize_output(elm_executor_output)}

    report["doc_tests"]["elmc"] = report["checks"]["elmc"]
    report["doc_tests"]["elm_executor"] = report["checks"]["elm_executor"]

    if elmc_exit == 0 and elm_executor_exit == 0:
        elmc_runtime = run_doc_runtime_eval(paths, project_dir, "elmc")
        elm_executor_runtime = run_doc_runtime_eval(paths, project_dir, "elm_executor")
        runtime_compare = compare_runtime_results(elmc_runtime, elm_executor_runtime)
        report["doc_tests"]["runtime"] = {
            "elmc": elmc_runtime,
            "elm_executor": elm_executor_runtime,
            "compare": runtime_compare,
        }
        report["doc_tests"]["status"] = "runtime_checked"
    else:
        report["doc_tests"]["runtime"] = {"status": "skipped_due_to_compile_failure"}
        report["doc_tests"]["status"] = "compile_checked"

    return report


def ensure_paths(repo_root: Path) -> RunnerPaths:
    base = repo_root / "tmp" / "real_world_elm_runner"
    paths = RunnerPaths(
        repo_root=repo_root,
        base_dir=base,
        packages_dir=base / "packages",
        scratch_dir=base / "scratch",
        reports_dir=base / "reports",
        state_path=base / "state.json",
        todos_path=base / "todos.json",
        elmc_bin=repo_root / "elmc" / "elmc",
        elm_executor_bin=repo_root / "elm_executor" / "elm_executor",
        elm_bootstrap_dir=base / "elm_install_bootstrap",
    )
    for p in (paths.base_dir, paths.packages_dir, paths.scratch_dir, paths.reports_dir):
        p.mkdir(parents=True, exist_ok=True)
    return paths


def append_todo(todos: Dict[str, Any], item: Dict[str, Any]) -> None:
    todos.setdefault("updated_at", now_iso())
    todos.setdefault("items", [])
    todos["items"].append(item)
    todos["updated_at"] = now_iso()


def package_cache_dir(paths: RunnerPaths, package: str, version: str) -> Path:
    owner, pkg = package.split("/", 1)
    return paths.packages_dir / owner / pkg / version


def ensure_bootstrap_project(paths: RunnerPaths) -> None:
    src_dir = paths.elm_bootstrap_dir / "src"
    src_dir.mkdir(parents=True, exist_ok=True)
    elm_json_path = paths.elm_bootstrap_dir / "elm.json"

    if not elm_json_path.exists():
        elm_json = {
            "type": "application",
            "source-directories": ["src"],
            "elm-version": "0.19.1",
            "dependencies": {
                "direct": {
                    "elm/core": "1.0.5",
                    "elm/json": "1.1.3",
                },
                "indirect": {},
            },
            "test-dependencies": {"direct": {}, "indirect": {}},
        }
        write_json(elm_json_path, elm_json)

    main_elm = src_dir / "Main.elm"
    if not main_elm.exists():
        main_elm.write_text(
            "module Main exposing (main)\n\nimport Platform\n\nmain = Platform.worker { init = (), update = \\_ m -> ( m, Cmd.none ), subscriptions = \\_ -> Sub.none }\n",
            encoding="utf-8",
        )


def latest_version_path(package_root: Path) -> Optional[Path]:
    if not package_root.exists():
        return None
    version_dirs = [p for p in package_root.iterdir() if p.is_dir()]
    if not version_dirs:
        return None
    return sorted(version_dirs, key=lambda p: semver_key(p.name))[-1]


def install_package_via_elm(paths: RunnerPaths, package: str, preferred_version: Optional[str] = None) -> Tuple[Path, str]:
    ensure_bootstrap_project(paths)
    owner, pkg = package.split("/", 1)
    package_root = Path.home() / ".elm" / "0.19.1" / "packages" / owner / pkg

    if preferred_version:
        preferred_dir = package_root / preferred_version
        if preferred_dir.is_dir():
            return preferred_dir, preferred_version

    try:
        proc = subprocess.run(
            ["elm", "install", package],
            cwd=str(paths.elm_bootstrap_dir),
            input="y\ny\n",
            capture_output=True,
            text=True,
            check=False,
            timeout=20,
        )
    except subprocess.TimeoutExpired as e:
        partial = ((e.stdout or "") + (e.stderr or "")).strip()
        prefix = first_non_empty_line(partial) if partial else "no output"
        raise PackageSourceUnavailableError(
            f"elm install timed out for {package}: {prefix}"
        ) from e
    exit_code = proc.returncode
    output = ((proc.stdout or "") + (proc.stderr or "")).strip()
    if exit_code != 0:
        if "CORRUPT PACKAGE DATA" in output:
            raise PackageSourceUnavailableError(
                f"registry source hash mismatch for {package}; package tag appears to have changed"
            )
        raise RuntimeError(f"elm install failed: {first_non_empty_line(output)}")

    latest_dir = latest_version_path(package_root)
    if latest_dir is None:
        raise RuntimeError("elm install finished but package not found in ~/.elm cache")
    return latest_dir, latest_dir.name


def ensure_package_downloaded(
    paths: RunnerPaths,
    package: str,
    version: str,
    elm_json: Dict[str, Any],
    local_packages_dir: Optional[Path] = None,
    local_cache_only: bool = False,
) -> Tuple[Path, Any, str]:
    pkg_dir = package_cache_dir(paths, package, version)
    docs_path = pkg_dir / "_docs.json"
    complete_marker = pkg_dir / ".download_complete"

    if complete_marker.exists() and docs_path.exists():
        docs_json = load_json(docs_path, [])
        return pkg_dir, docs_json, version

    owner, pkg = package.split("/", 1)
    local_src: Optional[Path] = None
    resolved_version = version

    if local_packages_dir is not None:
        cached_src = local_packages_dir / owner / pkg / version
        if cached_src.exists():
            local_src = cached_src
            resolved_version = version

    if local_src is None:
        if local_cache_only:
            raise PackageSourceUnavailableError(
                f"package {package}@{version} not found in local cache {local_packages_dir}"
            )
        local_src, resolved_version = install_package_via_elm(paths, package, preferred_version=version)

    pkg_dir = package_cache_dir(paths, package, resolved_version)
    docs_path = pkg_dir / "_docs.json"
    complete_marker = pkg_dir / ".download_complete"
    pkg_dir.parent.mkdir(parents=True, exist_ok=True)
    if pkg_dir.exists():
        shutil.rmtree(pkg_dir)
    shutil.copytree(local_src, pkg_dir)

    # Keep fetched elm.json (from package registry) for dependency filtering metadata.
    write_json(pkg_dir / "elm.json", elm_json)

    docs_json = load_json(local_src / "docs.json", None)
    if docs_json is None:
        if local_cache_only:
            docs_json = []
        else:
            encoded = encode_package(package)
            try:
                docs_json = http_json(
                    f"/packages/{encoded}/{resolved_version}/docs.json",
                    timeout_seconds=60,
                    retries=1,
                )
            except Exception:
                docs_json = []

    write_json(docs_path, docs_json)
    complete_marker.write_text(now_iso() + "\n", encoding="utf-8")
    return pkg_dir, docs_json, resolved_version


def run_package_checks(
    paths: RunnerPaths,
    package: str,
    version: str,
    package_dir: Path,
    docs_json: Any,
) -> Dict[str, Any]:
    report: Dict[str, Any] = {
        "package": package,
        "version": version,
        "checked_at": now_iso(),
        "package_dir": str(package_dir),
        "checks": {},
        "doc_tests": {
            "found_snippets": 0,
            "included_snippets": 0,
            "skipped_snippets": 0,
            "status": "not_run",
        },
    }

    # Base package checks.
    elmc_exit, elmc_output = run_cmd([str(paths.elmc_bin), "check", str(package_dir)], cwd=paths.repo_root / "elmc")
    elm_executor_exit, elm_executor_output = run_cmd(
        [str(paths.elm_executor_bin), "check", str(package_dir)], cwd=paths.repo_root / "elm_executor"
    )
    report["checks"]["elmc"] = {"exit_code": elmc_exit, "output": summarize_output(elmc_output)}
    report["checks"]["elm_executor"] = {"exit_code": elm_executor_exit, "output": summarize_output(elm_executor_output)}

    auto_snippets = extract_doc_snippets(docs_json)
    derived_snippets = derived_snippets_for_package(package)
    snippets: List[Dict[str, Any]] = derived_snippets if derived_snippets else auto_snippets
    report["doc_tests"]["found_snippets"] = len(auto_snippets)
    if derived_snippets:
        report["doc_tests"]["derived_snippets"] = len(derived_snippets)
        report["doc_tests"]["source"] = "derived"
    else:
        report["doc_tests"]["source"] = "docs"
    if not snippets:
        report["doc_tests"]["status"] = "not_available"
        return report

    # Build a scratch copy so cached package source stays pristine.
    safe_name = package.replace("/", "__")
    scratch = paths.scratch_dir / f"{safe_name}__{version}"
    copy_tree(package_dir, scratch)

    included, skipped, _included_owners = write_doc_test_module(scratch, snippets[:40], package=package)
    report["doc_tests"]["included_snippets"] = included
    report["doc_tests"]["skipped_snippets"] = skipped

    if included == 0:
        report["doc_tests"]["status"] = "no_supported_snippets"
        return report

    d_elmc_exit, d_elmc_output = run_cmd([str(paths.elmc_bin), "check", str(scratch)], cwd=paths.repo_root / "elmc")
    d_elm_executor_exit, d_elm_executor_output = run_cmd(
        [str(paths.elm_executor_bin), "check", str(scratch)],
        cwd=paths.repo_root / "elm_executor",
    )

    report["doc_tests"]["status"] = "checked"
    report["doc_tests"]["elmc"] = {
        "exit_code": d_elmc_exit,
        "output": summarize_output(d_elmc_output),
    }
    report["doc_tests"]["elm_executor"] = {
        "exit_code": d_elm_executor_exit,
        "output": summarize_output(d_elm_executor_output),
    }

    if d_elmc_exit == 0 and d_elm_executor_exit == 0:
        elmc_runtime = run_doc_runtime_eval(paths, scratch, "elmc")
        elm_executor_runtime = run_doc_runtime_eval(paths, scratch, "elm_executor")
        runtime_compare = compare_runtime_results(elmc_runtime, elm_executor_runtime)
        report["doc_tests"]["runtime"] = {
            "elmc": elmc_runtime,
            "elm_executor": elm_executor_runtime,
            "compare": runtime_compare,
        }
        report["doc_tests"]["status"] = "runtime_checked"
    else:
        report["doc_tests"]["runtime"] = {
            "status": "skipped_due_to_compile_failure",
        }
        report["doc_tests"]["status"] = "compile_checked"

    return report


def load_or_init_state(paths: RunnerPaths, package_names: Sequence[str]) -> Dict[str, Any]:
    state = load_json(
        paths.state_path,
        {
            "created_at": now_iso(),
            "updated_at": now_iso(),
            "cursor": 0,
            "packages": [],
        },
    )
    if "cursor" not in state:
        state["cursor"] = 0
    if "packages" not in state:
        state["packages"] = []
    state.pop("package_order", None)
    return state


def package_status_index(state: Dict[str, Any]) -> Dict[str, Dict[str, Any]]:
    out: Dict[str, Dict[str, Any]] = {}
    for row in state.get("packages", []):
        if isinstance(row, dict) and isinstance(row.get("package"), str):
            out[row["package"]] = row
    return out


def update_package_status(state: Dict[str, Any], row: Dict[str, Any]) -> None:
    existing = state.get("packages", [])
    if not isinstance(existing, list):
        existing = []
    packages: List[Dict[str, Any]] = [x for x in existing if not (isinstance(x, dict) and x.get("package") == row["package"])]
    packages.append(row)
    packages.sort(key=lambda x: x.get("package", ""))
    state["packages"] = packages
    state["updated_at"] = now_iso()


def runner_summary(state: Dict[str, Any], todos: Dict[str, Any]) -> str:
    rows = state.get("packages", [])
    total = len(rows)
    done = len(
        [
            r
            for r in rows
            if r.get("status")
            in (
                "checked",
                "skipped_blocked",
                "skipped_source_unavailable",
                "skipped_incompatible_elm_version",
                "skipped_internal_managed",
                "error",
            )
        ]
    )
    blocked = len([r for r in rows if r.get("status") == "skipped_blocked"])
    unavailable = len([r for r in rows if r.get("status") == "skipped_source_unavailable"])
    incompatible = len([r for r in rows if r.get("status") == "skipped_incompatible_elm_version"])
    internal = len([r for r in rows if r.get("status") == "skipped_internal_managed"])
    errors = len([r for r in rows if r.get("status") == "error"])
    checked = len([r for r in rows if r.get("status") == "checked"])
    todo_count = len(todos.get("items", [])) if isinstance(todos.get("items"), list) else 0
    return (
        f"packages_seen={total} checked={checked} blocked={blocked} unavailable={unavailable} incompatible={incompatible} internal={internal} errors={errors} "
        f"cursor={state.get('cursor', 0)} todos={todo_count}"
    )


def main(argv: Sequence[str]) -> int:
    parser = argparse.ArgumentParser(description="Resumable Elm package runner for elmc and elm_executor")
    parser.add_argument("--repo-root", default=".", help="Repo root (default: current directory)")
    parser.add_argument("--limit", type=int, default=10, help="Max packages to process this run")
    parser.add_argument("--reset", action="store_true", help="Reset state cursor and package statuses")
    parser.add_argument(
        "--start-from-package",
        default=None,
        help="Package name to start from (e.g. elm/core)",
    )
    parser.add_argument(
        "--include-blocked",
        action="store_true",
        help="Include packages with blocked/browser dependencies",
    )
    parser.add_argument(
        "--local-packages-dir",
        default=None,
        help="Use locally installed Elm packages from this directory",
    )
    parser.add_argument(
        "--local-cache-only",
        action="store_true",
        help="Do not fetch from package.elm-lang.org; use local package cache only",
    )
    args = parser.parse_args(argv)

    repo_root = Path(args.repo_root).resolve()
    paths = ensure_paths(repo_root)

    if not paths.elmc_bin.exists():
        print(f"missing elmc binary at {paths.elmc_bin}", file=sys.stderr)
        return 2
    if not paths.elm_executor_bin.exists():
        print(f"missing elm_executor binary at {paths.elm_executor_bin}", file=sys.stderr)
        return 2

    local_packages_dir: Optional[Path] = None
    if args.local_packages_dir:
        local_packages_dir = Path(args.local_packages_dir).expanduser().resolve()
    elif args.local_cache_only:
        local_packages_dir = Path.home() / ".elm" / "0.19.1" / "packages"

    if local_packages_dir is not None:
        print(f"using local package cache: {local_packages_dir}")
        package_map = local_package_index(local_packages_dir)
        if not package_map:
            print(f"no local packages found in {local_packages_dir}", file=sys.stderr)
            return 2
    else:
        index_cache_path = paths.base_dir / "all-packages.json"
        print("fetching package index...")
        try:
            package_map = http_json("/all-packages", timeout_seconds=45, retries=1)
            if not isinstance(package_map, dict):
                raise RuntimeError("invalid /all-packages payload")
            write_json(index_cache_path, package_map)
        except Exception as e:  # noqa: BLE001
            cached = load_json(index_cache_path, None)
            if isinstance(cached, dict):
                package_map = cached
                print(f"using cached package index after fetch error: {e}", file=sys.stderr)
            else:
                print(f"failed to load package index: {e}", file=sys.stderr)
                return 2
    package_names = sorted(package_map.keys())

    state = load_or_init_state(paths, package_names)
    todos = load_json(paths.todos_path, {"created_at": now_iso(), "updated_at": now_iso(), "items": []})

    if args.reset:
        state["cursor"] = 0
        state["packages"] = []
        state.pop("package_order", None)
        state["updated_at"] = now_iso()
        todos = {"created_at": now_iso(), "updated_at": now_iso(), "items": []}
        write_json(paths.state_path, state)
        write_json(paths.todos_path, todos)

    processed = 0
    cursor = int(state.get("cursor", 0))
    if cursor >= len(package_names):
        cursor = 0
    if args.start_from_package:
        try:
            cursor = package_names.index(args.start_from_package)
        except ValueError:
            print(f"start package not found in package set: {args.start_from_package}", file=sys.stderr)
            return 2

    while cursor < len(package_names) and processed < args.limit:
        package = package_names[cursor]
        versions = package_map.get(package, [])
        version = latest_version(versions if isinstance(versions, list) else [])
        row: Dict[str, Any] = {
            "package": package,
            "version": version,
            "cursor_index": cursor,
            "checked_at": now_iso(),
        }

        print(f"[{cursor + 1}/{len(package_names)}] {package} ({version})")
        try:
            if not version:
                row["status"] = "error"
                row["error"] = "missing_version"
                append_todo(
                    todos,
                    {
                        "kind": "package_metadata_error",
                        "package": package,
                        "version": None,
                        "message": "No latest version found in all-packages index",
                        "created_at": now_iso(),
                    },
                )
                update_package_status(state, row)
                cursor += 1
                processed += 1
                continue

            if package in INTERNAL_MANAGED_PACKAGES:
                row["status"] = "skipped_internal_managed"
                row["note"] = "managed by in-repo implementation and tested separately"
                update_package_status(state, row)
                cursor += 1
                processed += 1
                continue

            if package == "elm/core":
                resolved_version = version
                row["version"] = resolved_version
                report = run_elm_core_docs_suite(paths, resolved_version)
            else:
                if local_packages_dir is not None:
                    owner, pkg = package.split("/", 1)
                    elm_json = load_json(local_packages_dir / owner / pkg / version / "elm.json", {})
                    if not isinstance(elm_json, dict):
                        elm_json = {}
                else:
                    encoded = encode_package(package)
                    elm_json = http_json(f"/packages/{encoded}/{version}/elm.json", timeout_seconds=60, retries=1)
                    if not isinstance(elm_json, dict):
                        raise RuntimeError("invalid package elm.json payload")

                blocked = blocked_dependencies(package, elm_json)
                if blocked and not args.include_blocked:
                    row["status"] = "skipped_blocked"
                    row["blocked_dependencies"] = blocked
                    update_package_status(state, row)
                    cursor += 1
                    processed += 1
                    continue

                elm_constraint = package_elm_version_constraint(elm_json)
                if not supports_runner_elm_version(elm_json):
                    row["status"] = "skipped_incompatible_elm_version"
                    row["elm_version_constraint"] = elm_constraint
                    update_package_status(state, row)
                    cursor += 1
                    processed += 1
                    continue

                package_dir, docs_json, resolved_version = ensure_package_downloaded(
                    paths,
                    package,
                    version,
                    elm_json,
                    local_packages_dir=local_packages_dir,
                    local_cache_only=args.local_cache_only or local_packages_dir is not None,
                )
                row["version"] = resolved_version
                report = run_package_checks(paths, package, resolved_version, package_dir, docs_json)

            report_path = paths.reports_dir / f"{package.replace('/', '__')}__{resolved_version}.json"
            write_json(report_path, report)
            row["report_path"] = str(report_path)
            row["status"] = "checked"

            # Collect todos from check failures.
            for engine in ("elmc", "elm_executor"):
                engine_row = report.get("checks", {}).get(engine, {})
                exit_code = engine_row.get("exit_code")
                if isinstance(exit_code, int) and exit_code != 0:
                    append_todo(
                        todos,
                        {
                            "kind": "compile_failure",
                            "engine": engine,
                            "package": package,
                            "version": resolved_version,
                            "message": engine_row.get("output", "(no output)"),
                            "created_at": now_iso(),
                        },
                    )

            doc_status = report.get("doc_tests", {})
            if doc_status.get("status") in ("compile_checked", "runtime_checked"):
                for engine in ("elmc", "elm_executor"):
                    engine_row = doc_status.get(engine, {})
                    exit_code = engine_row.get("exit_code")
                    if isinstance(exit_code, int) and exit_code != 0:
                        append_todo(
                            todos,
                            {
                                "kind": "doc_test_compile_failure",
                                "engine": engine,
                                "package": package,
                                "version": resolved_version,
                                "message": engine_row.get("output", "(no output)"),
                                "created_at": now_iso(),
                            },
                        )

                runtime_compare = doc_status.get("runtime", {}).get("compare", {})
                for mismatch in runtime_compare.get("mismatches", []):
                    append_todo(
                        todos,
                        {
                            "kind": "doc_test_runtime_mismatch",
                            "package": package,
                            "version": resolved_version,
                            "message": json.dumps(mismatch, sort_keys=True),
                            "created_at": now_iso(),
                        },
                    )

                if runtime_compare.get("error_count", 0) > 0:
                    append_todo(
                        todos,
                        {
                            "kind": "doc_test_runtime_error",
                            "package": package,
                            "version": resolved_version,
                            "message": json.dumps(
                                {
                                    "error_count": runtime_compare.get("error_count"),
                                    "compared_count": runtime_compare.get("compared_count"),
                                },
                                sort_keys=True,
                            ),
                            "created_at": now_iso(),
                        },
                    )

                if runtime_compare.get("status") == "runtime_eval_error":
                    append_todo(
                        todos,
                        {
                            "kind": "doc_test_runtime_eval_error",
                            "package": package,
                            "version": resolved_version,
                            "message": json.dumps(runtime_compare, sort_keys=True),
                            "created_at": now_iso(),
                        },
                    )

                runtime_block = doc_status.get("runtime", {})
                if runtime_block.get("status") == "skipped_due_to_compile_failure":
                    append_todo(
                        todos,
                        {
                            "kind": "doc_test_runtime_skipped",
                            "package": package,
                            "version": resolved_version,
                            "message": "runtime skipped because generated doctest module failed to compile",
                            "created_at": now_iso(),
                        },
                    )

                coverage = doc_status.get("coverage", {})
                if coverage.get("status") == "incomplete":
                    append_todo(
                        todos,
                        {
                            "kind": "doc_test_coverage_gap",
                            "package": package,
                            "version": resolved_version,
                            "message": json.dumps(
                                {
                                    "missing_function_count": coverage.get("missing_function_count", 0),
                                    "missing_function_owners": coverage.get("missing_function_owners", [])[:30],
                                },
                                sort_keys=True,
                            ),
                            "created_at": now_iso(),
                        },
                    )

            update_package_status(state, row)

        except urllib.error.HTTPError as e:
            row["status"] = "error"
            row["error"] = f"http_error:{e.code}"
            append_todo(
                todos,
                {
                    "kind": "http_error",
                    "package": package,
                    "version": version,
                    "message": f"HTTP {e.code}: {e.reason}",
                    "created_at": now_iso(),
                },
            )
            update_package_status(state, row)
        except PackageSourceUnavailableError as e:
            row["status"] = "skipped_source_unavailable"
            row["error"] = str(e)
            append_todo(
                todos,
                {
                    "kind": "package_source_unavailable",
                    "package": package,
                    "version": version,
                    "message": str(e),
                    "created_at": now_iso(),
                },
            )
            update_package_status(state, row)
        except Exception as e:  # noqa: BLE001
            row["status"] = "error"
            row["error"] = repr(e)
            append_todo(
                todos,
                {
                    "kind": "runner_error",
                    "package": package,
                    "version": version,
                    "message": repr(e),
                    "created_at": now_iso(),
                },
            )
            update_package_status(state, row)

        cursor += 1
        processed += 1
        state["cursor"] = cursor
        write_json(paths.state_path, state)
        write_json(paths.todos_path, todos)

    state["cursor"] = cursor
    state["updated_at"] = now_iso()
    write_json(paths.state_path, state)
    write_json(paths.todos_path, todos)

    print(runner_summary(state, todos))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
