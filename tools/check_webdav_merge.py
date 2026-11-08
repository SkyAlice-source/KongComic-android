#!/usr/bin/env python3
"""Offline regression guard for the WebDAV favorites merge path.

The WebDAV round trip needs a live server, which CI / local checks do not have.
This guard does two things instead:

1. Static assertions on the Dart source: downloads must use the merge path,
   uploads must always use the sanitized snapshot, and the import must not
   trigger an immediate re-upload.
2. Executes the *actual* INSERT ... SELECT statements extracted from
   LocalFavoritesManager.mergeFrom against a real in-memory sqlite database,
   so a wrong column name, a missing table guard, or a silently lost
   folder_order / display_order is caught without a device.
"""
import re
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def dart(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def fail(msg):
    print("FAIL: " + msg)
    sys.exit(1)


def collapse(sql):
    return re.sub(r"\s+", " ", sql).strip()


def main():
    favorites = dart("lib/foundation/favorites.dart")
    sync = dart("lib/utils/data_sync.dart")
    data = dart("lib/utils/data.dart")
    appdata = dart("lib/foundation/appdata.dart")

    # 1. Download must merge, not replace local databases wholesale.
    if not re.search(
        r"importAppData\(\s*localFile\s*,\s*false\s*,\s*true\s*,\s*true\s*\)", sync
    ):
        fail("downloadData no longer calls importAppData(..., merge=true, syncAssets=true)")

    # 2. Manual merge keeps its old semantics; only WebDAV continues past it.
    if "if (!syncAssets)" not in data:
        fail("importAppData merge branch lost the !syncAssets early return")

    # 3. Folder-internal manual ordering survives the merge.
    if "row['display_order']" not in favorites:
        fail("mergeFrom no longer passes backup display_order into addComic")

    # 4. Uploads always use the sanitized snapshot, and syncdata.json is always
    #    written (old behavior leaked the WebDAV password in appdata.json).
    if "exportAppData(true)" not in sync:
        fail("uploadData no longer exports the sanitized syncdata.json")
    if "if (disableSyncFields.isNotEmpty)" in appdata:
        fail("syncdata.json is still generated only for custom skip fields")
    if "for (var field in _disableSync)" not in appdata:
        fail("built-in device fields are no longer stripped from syncdata.json")

    # 5. Import must not trigger an immediate re-upload (version ping-pong).
    if "syncData(data, !syncAssets)" not in data:
        fail("WebDAV import can still trigger a re-upload via syncData/saveData")
    if "_isImporting" not in sync:
        fail("DataSync lost the _isImporting guard")

    # 6. Run the real merge SQL against sqlite.
    con = sqlite3.connect(":memory:")
    con.execute("ATTACH DATABASE ':memory:' AS backup")
    for schema in ("main", "backup"):
        con.execute(
            f"CREATE TABLE {schema}.folder_order "
            "(folder_name TEXT PRIMARY KEY, order_value INT)"
        )
        con.execute(
            f"CREATE TABLE {schema}.folder_sync "
            "(folder_name TEXT PRIMARY KEY, source_key TEXT, source_folder TEXT)"
        )

    con.execute(
        "INSERT INTO main.folder_order VALUES ('Local Only', 0)"
    )
    con.execute(
        "INSERT INTO backup.folder_order VALUES "
        "('Local Only', 99), ('From Remote', 7)"
    )
    con.execute(
        "INSERT INTO backup.folder_sync VALUES "
        "('From Remote', 'baozimh', 'Favorites')"
    )

    for table in ("folder_order", "folder_sync"):
        match = re.search(
            r"INSERT\s+OR\s+IGNORE\s+INTO\s+" + table + r"\s*\([^)]*\)\s*"
            r"SELECT[^;]*;",
            favorites,
            re.IGNORECASE | re.DOTALL,
        )
        if not match:
            fail(f"could not extract the merge SQL for {table}")
        try:
            con.execute(collapse(match.group(0)))
        except sqlite3.Error as exc:
            fail(f"{table} merge SQL is invalid: {exc}")

    orders = dict(con.execute("SELECT folder_name, order_value FROM folder_order"))
    if orders != {"Local Only": 0, "From Remote": 7}:
        fail(f"folder_order merge result is wrong: {orders}")
    links = con.execute(
        "SELECT folder_name, source_key, source_folder FROM folder_sync"
    ).fetchall()
    if links != [("From Remote", "baozimh", "Favorites")]:
        fail(f"folder_sync merge result is wrong: {links}")

    print("PASS: WebDAV merge path, sanitized upload and merge SQL are intact")


if __name__ == "__main__":
    main()
