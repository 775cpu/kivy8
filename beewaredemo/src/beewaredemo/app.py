"""BeeWare Android RPC demo with a full-screen runtime log."""

import sys
import threading
import traceback
from queue import Empty, Queue

import toga
from toga.style import Pack
from toga.style.pack import COLUMN

from . import rpc


class LogStream:
    def __init__(self, queue):
        self.queue = queue

    def write(self, value):
        if value:
            self.queue.put(value)

    def flush(self):
        pass


class BeeWareDemo(toga.App):
    def startup(self):
        self.log_queue = Queue()
        self.log_view = toga.MultilineTextInput(
            value="Starting BeeWare RPC...\n",
            readonly=True,
            style=Pack(flex=1, font_size=12),
        )
        self.main_window = toga.MainWindow(title=self.formal_name)
        self.main_window.content = toga.Box(
            children=[self.log_view],
            style=Pack(direction=COLUMN, flex=1, padding=0),
        )
        self.main_window.show()

        self._stdout = sys.stdout
        self._stderr = sys.stderr
        sys.stdout = LogStream(self.log_queue)
        sys.stderr = LogStream(self.log_queue)

        try:
            self.rpc_server, self.rpc_thread = rpc.start_rpc_server(
                port=1144,
                globals=globals(),
                locals=locals(),
            )
            print("[APP] RPC server started on http://0.0.0.0:1144/")
        except Exception:
            print("[APP] Failed to start RPC server:")
            traceback.print_exc()

        self._log_thread = threading.Thread(
            target=self._drain_logs,
            name="BeeWareLogDrain",
            daemon=True,
        )
        self._log_thread.start()

    def _drain_logs(self):
        while True:
            try:
                message = self.log_queue.get(timeout=0.25)
            except Empty:
                continue
            try:
                self.app.loop.call_soon_threadsafe(self._append_log, message)
            except Exception:
                pass

    def _append_log(self, message):
        self.log_view.value = (self.log_view.value or "") + message

    def on_exit(self):
        sys.stdout = self._stdout
        sys.stderr = self._stderr
        if hasattr(self, "rpc_server"):
            self.rpc_server.shutdown()
        return True


def main():
    return BeeWareDemo()
