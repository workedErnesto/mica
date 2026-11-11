"""Serves windows/shell for the preview pane without caching, so an edited module is what the page runs.
Development only: the app loads the shell from its own folder through WebView2."""
import functools, http.server, pathlib, sys

class NoCache(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Cache-Control', 'no-store')
        super().end_headers()

port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
root = pathlib.Path(__file__).resolve().parent.parent
http.server.ThreadingHTTPServer(('127.0.0.1', port), functools.partial(NoCache, directory=str(root))).serve_forever()
