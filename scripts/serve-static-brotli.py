#!/usr/bin/env python3
"""Static file server with optional precompressed Brotli (.br) negotiation.

Prefer path.br when the request Accept-Encoding includes \"br\". Serves the
uncompressed sibling otherwise. Intended for local elm_pebble_dev dist/ smoke.
"""

from __future__ import annotations

import argparse
import mimetypes
import os
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer


class BrotliRequestHandler(SimpleHTTPRequestHandler):
    # When False (default), avoid sticky caches so local wasm-web rebuilds are
    # visible without a hard refresh. Bench warm-cache runs pass --immutable-cache.
    immutable_cache = False

    extensions_map = {
        **getattr(SimpleHTTPRequestHandler, "extensions_map", {}),
        ".wasm": "application/wasm",
        ".json": "application/json",
        ".js": "text/javascript",
        ".mjs": "text/javascript",
        ".css": "text/css",
        ".html": "text/html",
        ".br": "application/octet-stream",
    }

    def end_headers(self) -> None:
        # Allow local preview from other origins / tooling.
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Cache-Control", self._cache_control_for(self.path))
        super().end_headers()

    def _cache_control_for(self, url_path: str) -> str:
        path = (url_path or "").split("?", 1)[0].lower()
        if path.endswith(".html") or path.endswith("/"):
            return "no-cache"
        if not self.immutable_cache:
            # boot.js / app.wasm / manifest keep stable URLs across rebuilds.
            return "no-cache"
        # Long cache only when explicitly requested (browser warm-load benches).
        if path.endswith(
            (
                ".wasm",
                ".js",
                ".mjs",
                ".css",
                ".json",
                ".png",
                ".jpg",
                ".jpeg",
                ".webp",
                ".gif",
                ".svg",
                ".woff2",
            )
        ):
            return "public, max-age=31536000, immutable"
        return "public, max-age=3600"

    def do_GET(self) -> None:  # noqa: N802
        if self._try_send_brotli():
            return
        super().do_GET()

    def do_HEAD(self) -> None:  # noqa: N802
        if self._try_send_brotli(head_only=True):
            return
        super().do_HEAD()

    def _try_send_brotli(self, head_only: bool = False) -> bool:
        accept = self.headers.get("Accept-Encoding", "")
        if "br" not in accept.lower():
            return False

        # Translate URL path to a filesystem path under the handler directory.
        path = self.translate_path(self.path)
        if os.path.isdir(path):
            return False
        if path.endswith(".br"):
            return False

        br_path = path + ".br"
        if not os.path.isfile(br_path):
            return False

        ctype = self.guess_type(path)
        try:
            with open(br_path, "rb") as f:
                data = f.read()
        except OSError:
            return False

        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Encoding", "br")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Vary", "Accept-Encoding")
        self.end_headers()
        if not head_only:
            self.wfile.write(data)
        return True

    def guess_type(self, path: str) -> str:
        # Prefer our map; fall back to mimetypes for everything else.
        base, ext = os.path.splitext(path)
        if ext in self.extensions_map:
            return self.extensions_map[ext]
        guessed, _ = mimetypes.guess_type(path)
        return guessed or "application/octet-stream"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", help="Directory to serve")
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument("--bind", default="127.0.0.1")
    parser.add_argument(
        "--immutable-cache",
        action="store_true",
        help="Send long-lived Cache-Control for assets (for warm-cache benches only)",
    )
    args = parser.parse_args()

    directory = os.path.abspath(args.directory)
    if not os.path.isdir(directory):
        raise SystemExit(f"not a directory: {directory}")

    handler_cls = type(
        "ConfiguredBrotliRequestHandler",
        (BrotliRequestHandler,),
        {"immutable_cache": bool(args.immutable_cache)},
    )
    handler = partial(handler_cls, directory=directory)
    server = ThreadingHTTPServer((args.bind, args.port), handler)
    cache_mode = "immutable-cache" if args.immutable_cache else "no-cache"
    print(
        f"Serving {directory} on http://{args.bind}:{args.port}/ "
        f"(brotli enabled, {cache_mode})"
    )
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped.")


if __name__ == "__main__":
    main()
