"""Exercise real Android SAF backups and a cold-process scheduled job.

python scripts/test_native_backups.py --device emulator-5554 --isolated-emulator
Uses a disposable emulator: clears Companion's test installation data first.
"""
import argparse
import base64
import hashlib
import io
import json
import os
from pathlib import Path
import queue
import re
import shutil
import subprocess
import sys
import threading
import time
import xml.etree.ElementTree as ET
import zipfile

PACKAGE = "io.github.yuuge7.companion"
FOLDER = "/sdcard/Documents/CompanionBackupTest"
ARCHIVE = re.compile(r"companion-auto-\d{13}-[0-9a-f]{8}\.companion$")


def verify_archive(raw):
    with zipfile.ZipFile(io.BytesIO(raw)) as archive:
        manifest = json.loads(archive.read("manifest.json"))
        assert manifest["app"] == "Companion"
        for name, digest in manifest["files"].items():
            assert hashlib.sha256(archive.read(name)).hexdigest() == digest, name
        assert json.loads(archive.read("manga.json"))[0]["currentChapter"] == 7
        assert json.loads(archive.read("film.json"))["entries"][0]["title"] == "Native backup film"
        assert json.loads(archive.read("anime.json"))["library"]["entries"][0]["currentEpisode"] == 3
        with zipfile.ZipFile(io.BytesIO(archive.read("books.bcbackup"))) as books:
            assert any(name.startswith("covers/") for name in books.namelist())


def main():
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True)
    parser.add_argument("--isolated-emulator", action="store_true", required=True)
    args = parser.parse_args()
    if not args.device.startswith("emulator-"):
        parser.error("This test requires a disposable emulator.")
    root = Path(__file__).resolve().parent.parent
    sdk = Path(os.environ.get("ANDROID_HOME", Path.home() / "AppData/Local/Android/sdk"))
    adb = str(sdk / "platform-tools/adb.exe") if os.name == "nt" else "adb"

    def run(*parts, binary=False, input=None):
        result = subprocess.run([adb, "-s", args.device, *parts], input=input,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                timeout=180 if parts == ("wait-for-device",) else 30)
        if result.returncode and not (parts[:2] == ("shell", "pidof") and result.returncode == 1):
            raise RuntimeError(result.stderr.decode(errors="replace"))
        return result.stdout if binary else result.stdout.decode(errors="replace").strip()

    run("wait-for-device")
    avd_name = run("emu", "avd", "name").splitlines()[0]
    if not avd_name.startswith("Companion_Backup_Test"):
        parser.error("Use a separate AVD named Companion_Backup_Test (optionally with a suffix).")
    deadline = time.monotonic() + 180
    while run("shell", "getprop", "sys.boot_completed") != "1":
        assert time.monotonic() < deadline, "Emulator did not boot"
        time.sleep(1)
    if PACKAGE in run("shell", "pm", "list", "packages", PACKAGE):
        run("shell", "pm", "clear", PACKAGE)
    run("shell", "mkdir", "-p", FOLDER)
    run("shell", "touch", FOLDER + "/keep-me.txt")
    run("shell", "input", "keyevent", "KEYCODE_WAKEUP")
    run("shell", "input", "keyevent", "82")

    def files():
        return sorted(name for name in run("shell", "ls", FOLDER).splitlines() if ARCHIVE.fullmatch(name))

    def dump():
        run("shell", "uiautomator", "dump", "/data/local/tmp/companion-test-window.xml")
        raw = run("exec-out", "cat", "/data/local/tmp/companion-test-window.xml")
        start = raw.find("<?xml")
        if start < 0:
            start = raw.find("<hierarchy")
        if start < 0:
            raise RuntimeError(f"No UI hierarchy returned: {raw[:200]}")
        return ET.fromstring(raw[start:])

    def tap_node(tree, labels):
        for node in tree.iter("node"):
            if node.get("text") in labels or node.get("content-desc") in labels:
                bounds = [int(n) for n in re.findall(r"\d+", node.get("bounds", ""))]
                if len(bounds) == 4 and bounds[2] > bounds[0]:
                    run("shell", "input", "tap", str((bounds[0]+bounds[2])//2), str((bounds[1]+bounds[3])//2))
                    return True
        return False

    def choose_folder():
        deadline = time.monotonic() + 45
        entered = False
        while time.monotonic() < deadline:
            try:
                tree = dump()
            except (RuntimeError, ET.ParseError):
                time.sleep(.5)
                continue
            if not entered and tap_node(tree, {"CompanionBackupTest"}):
                entered = True
            elif entered and tap_node(tree, {"USE THIS FOLDER", "Use this folder"}):
                time.sleep(.5)
                tap_node(dump(), {"ALLOW", "Allow"})
                print("Native folder selected", flush=True)
                return
            elif not entered:
                if not tap_node(tree, {"Documents"}):
                    if not tap_node(tree, {"Show roots"}):
                        tap_node(tree, {"Internal storage", "Medium Phone"})
            time.sleep(.5)
        raise AssertionError("Could not select the test folder")

    flutter = shutil.which("flutter")
    assert flutter, "Flutter is not on PATH"
    process = subprocess.Popen([flutter, "drive", "--driver=test_driver/native_backup_driver.dart",
                                "--target=integration_test/lookup_backup_test.dart",
                                "-d", args.device, "--enable-software-rendering", "--keep-app-running"], cwd=root,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               text=True, encoding="utf-8", errors="replace", bufsize=1)
    lines = queue.Queue()

    def reader():
        for line in process.stdout:
            lines.put(line)
        lines.put(None)

    threading.Thread(target=reader, daemon=True).start()
    passed = False
    deadline = time.monotonic() + 900
    log = root / "tool/native-backup-test.log"
    with log.open("w", encoding="utf-8") as output:
        while time.monotonic() < deadline:
            try:
                line = lines.get(timeout=1)
            except queue.Empty:
                continue
            if line is None:
                break
            output.write(line)
            output.flush()
            if any(word in line for word in ("AUTO_BACKUP_", "Exception", "Error", "failed", "passed", "Built", "Installing")):
                print(line.strip(), flush=True)
            if "AUTO_BACKUP_CHOOSE_FOLDER" in line:
                choose_folder()
            if "AUTO_BACKUP_VERIFY" in line:
                names = files()
                assert len(names) == 3, names
                assert "keep-me.txt" in run("shell", "ls", FOLDER)
                raw = run("exec-out", "cat", FOLDER + "/" + names[-1], binary=True)
                verify_archive(raw)
                # Windows adb reads stdin in text mode and can stop at Ctrl+Z.
                # ASCII base64 preserves arbitrary ZIP bytes on every host.
                run("shell", "-T", "run-as", PACKAGE, "sh", "-c", "'base64 -d > files/native-roundtrip.companion.tmp'", input=base64.b64encode(raw))
                copied = run("exec-out", "run-as", PACKAGE, "cat", "files/native-roundtrip.companion.tmp", binary=True)
                assert copied == raw, "Host-to-device archive transfer changed bytes"
                run("shell", "run-as", PACKAGE, "mv", "files/native-roundtrip.companion.tmp", "files/native-roundtrip.companion")
                print("Verified retention, archive checksums, all libraries and cover files", flush=True)
            if "AUTO_BACKUP_FOREGROUND_PASSED" in line:
                passed = True
    assert process.wait(timeout=30) == 0 and passed, f"Integration test failed; see {log}"

    # Terminate the cached UI process without Android's force-stop flag (which
    # intentionally suppresses jobs). JobScheduler must start a new Dart engine.
    before = files()
    run("shell", "input", "keyevent", "3")
    time.sleep(2)
    run("shell", "am", "kill", PACKAGE)
    deadline = time.monotonic() + 30
    while run("shell", "pidof", PACKAGE) and time.monotonic() < deadline:
        time.sleep(1)
        run("shell", "am", "kill", PACKAGE)
    assert not run("shell", "pidof", PACKAGE), "UI process did not exit"
    run("shell", "cmd", "jobscheduler", "run", "-f", PACKAGE, "7342")
    deadline = time.monotonic() + 120
    while time.monotonic() < deadline:
        names = files()
        if names and names[-1] not in before:
            raw = run("exec-out", "cat", FOLDER + "/" + names[-1], binary=True)
            try:
                verify_archive(raw)
                assert len(names) == 3
                print("PASS: cold-process scheduled backup, all libraries, covers and retention", flush=True)
                return
            except (zipfile.BadZipFile, AssertionError):
                pass
        time.sleep(1)
    raise AssertionError("Cold-process scheduled backup did not complete")


if __name__ == "__main__":
    main()
