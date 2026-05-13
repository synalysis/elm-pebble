import sys

from libpebble2.protocol import transfers
from libpebble2.services import install as install_service
from libpebble2.services.install import AppInstaller
from libpebble2.services.putbytes import PutBytes
from pypkjs.runner.pebble_manager import PebbleManager


class QemuPutBytes(PutBytes):
    def _send_object(self, cookie):
        sent = 0
        length = 500
        total = len(self._object)

        while sent < total:
            chunk = self._object[sent : sent + length]
            packet = transfers.PutBytes(data=transfers.PutBytesPut(cookie=cookie, payload=chunk))
            self._assert_success(self._pebble.send_and_read(packet, transfers.PutBytesResponse))
            sent += len(chunk)
            print(f"PUTBYTES_PROGRESS {sent}/{total}", flush=True)
            self._broadcast_event("progress", len(chunk), sent, total)


def main(argv):
    if len(argv) != 3:
        print("usage: embedded_install.py HOST:PORT APP.pbw", file=sys.stderr)
        return 2

    qemu, pbw_path = argv[1], argv[2]
    manager = PebbleManager(qemu)
    manager.connect()
    install_service.PutBytes = QemuPutBytes
    AppInstaller(manager.pebble, pbw_path, blobdb_client=manager.blobdb).install()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
