"""Supervise Hermes's private MacroDroid receiver without Twilio ingress."""

import argparse
import ast
import hmac
import runpy
from http.server import ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit


def load_receiver(path):
    tree = ast.parse(Path(path).read_text())
    routes = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.If):
            continue
        test = node.test
        if (
            isinstance(test, ast.Compare)
            and isinstance(test.left, ast.Attribute)
            and test.left.attr == "path"
            and len(test.ops) == 1
            and isinstance(test.ops[0], ast.Eq)
            and len(test.comparators) == 1
            and isinstance(test.comparators[0], ast.Constant)
            and isinstance(test.comparators[0].value, str)
            and any(
                isinstance(n, ast.Call)
                and isinstance(n.func, ast.Name)
                and n.func.id == "forward_token"
                for statement in node.body
                for n in ast.walk(statement)
            )
        ):
            routes.append(test.comparators[0].value)
    if len(routes) != 1:
        raise RuntimeError("Receiver contract changed; refusing to expose it")
    namespace = runpy.run_path(str(path), run_name="receiver_definition")
    handler = namespace["Handler"]
    original = handler.do_POST
    token_reader = namespace["forward_token"]
    route = routes[0]

    def guarded_post(self):
        self.connection.settimeout(10)
        parts = urlsplit(self.path)
        if parts.path != route:
            self._reply(404, "Not found")
            return
        supplied = parse_qs(parts.query).get("token", [""])[0]
        supplied = supplied or self.headers.get("X-SMS-Token", "")
        expected = token_reader()
        if not expected or not hmac.compare_digest(
            supplied.encode("utf-8"), expected.encode("utf-8")
        ):
            self._reply(403, "Forbidden")
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            self._reply(400, "Invalid content length")
            return
        if not 0 < length <= 65536:
            self._reply(413, "Invalid payload size")
            return
        original(self)

    handler.do_POST = guarded_post
    return handler, namespace, route


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("receiver", type=Path)
    parser.add_argument("--port", type=int, default=8788)
    args = parser.parse_args()
    handler, _, _ = load_receiver(args.receiver)
    with ThreadingHTTPServer(("0.0.0.0", args.port), handler) as server:
        print("MacroDroid receiver ready", flush=True)
        server.serve_forever()


if __name__ == "__main__":
    main()
