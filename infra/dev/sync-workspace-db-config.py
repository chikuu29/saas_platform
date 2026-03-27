from __future__ import annotations

import argparse
import json
import os
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from dotenv import load_dotenv
from pymongo import MongoClient
from pymongo.collection import Collection
from pymongo.database import Database


REPO_ROOT = Path(__file__).resolve().parents[2]
WORKSPACE_BACKEND_DIR = REPO_ROOT / "apps" / "work_space" / "backend"
DB_CONFIG_DIR = REPO_ROOT / "apps" / "work_space" / "web" / "DB_CONFIG"
APP_CONFIG_DIR = DB_CONFIG_DIR / "APP_CONFIG"
TEMPLATE_DIR = DB_CONFIG_DIR / "TEMPLATE"


@dataclass
class SyncStats:
    scanned: int = 0
    synced: int = 0
    skipped: int = 0
    pruned: int = 0


class SyncError(RuntimeError):
    pass


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Sync workspace web DB_CONFIG JSON files into MongoDB collections."
    )
    parser.add_argument(
        "--mongo-uri",
        help="MongoDB connection string. Defaults to apps/work_space/backend .env values.",
    )
    parser.add_argument(
        "--db-name",
        help="Mongo database name. Defaults to apps/work_space/backend .env values.",
    )
    parser.add_argument(
        "--example-folder-mode",
        choices=["skip", "base", "strict", "active"],
        default="skip",
        help=(
            "How to handle TEMPLATE/exmple files: "
            "skip = ignore them, "
            "base = store as non-queryable base docs under templateDocument, "
            "strict = sync only when no live template has the same appName+pageName, "
            "active = sync them as normal live templates."
        ),
    )
    parser.add_argument(
        "--prune",
        action="store_true",
        help="Delete previously synced documents for missing source files in app_config and template collections.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print what would change without writing to MongoDB.",
    )
    return parser.parse_args()


def load_workspace_env() -> tuple[str, str]:
    load_dotenv(WORKSPACE_BACKEND_DIR / ".env")
    load_dotenv(WORKSPACE_BACKEND_DIR / ".env.development", override=True)

    uri = os.environ.get("MONGO_URI", "mongodb://localhost:27017")
    db_name = os.environ.get("DATABASE_NAME") or os.environ.get("MONGO_DB_NAME") or "workspace_saas"
    return uri, db_name


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def relative_posix(path: Path) -> str:
    return path.relative_to(REPO_ROOT).as_posix()


def read_json(path: Path) -> dict[str, Any]:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise SyncError(f"Invalid JSON in {path}: {exc}") from exc


def ensure_indexes(db: Database[Any], dry_run: bool) -> None:
    if dry_run:
        print("[dry-run] Would ensure unique indexes on _sync.sourcePath")
        return

    db["app_config"].create_index("_sync.sourcePath", unique=True, sparse=True)
    db["template"].create_index("_sync.sourcePath", unique=True, sparse=True)


def build_sync_meta(path: Path, source_type: str) -> dict[str, Any]:
    return {
        "sourceType": source_type,
        "sourcePath": relative_posix(path),
        "fileName": path.name,
        "syncedAt": utc_now(),
    }


def build_app_config_document(path: Path) -> dict[str, Any]:
    document = read_json(path)
    document["_sync"] = build_sync_meta(path, "app_config")
    return document


def build_template_document(
    path: Path,
    example_folder_mode: str,
    live_template_keys: set[tuple[str, str]],
) -> dict[str, Any] | None:
    raw_document = read_json(path)
    relative_template_path = path.relative_to(TEMPLATE_DIR)
    folder_name = relative_template_path.parts[0] if len(relative_template_path.parts) > 1 else ""
    is_example_folder = folder_name.lower() == "exmple"

    if is_example_folder and example_folder_mode == "skip":
        return None

    app_name = str(raw_document.get("appName") or "").strip()
    page_name = str(raw_document.get("pageName") or "").strip()
    template_key = (app_name, page_name)

    if is_example_folder and example_folder_mode == "strict" and template_key in live_template_keys:
        raise SyncError(
            "Example template conflict for "
            f"appName='{app_name}', pageName='{page_name}' at {relative_posix(path)}. "
            "Use --example-folder-mode base to store examples safely or active to allow live collisions."
        )

    sync_meta = build_sync_meta(path, "template")
    common_meta = {
        "templateFolder": folder_name,
        "templateFile": path.stem,
        "templateMode": "active",
        "_sync": sync_meta,
    }

    if is_example_folder and example_folder_mode == "base":
        return {
            "templateFolder": folder_name,
            "templateFile": path.stem,
            "templateMode": "base",
            "baseAppName": app_name,
            "basePageName": page_name,
            "baseRoute": raw_document.get("route"),
            "templateDocument": raw_document,
            "_sync": sync_meta,
        }

    document = dict(raw_document)
    document.update(common_meta)
    if is_example_folder and example_folder_mode == "strict":
        document["templateMode"] = "strict"
    return document


def collect_live_template_keys() -> set[tuple[str, str]]:
    live_keys: set[tuple[str, str]] = set()
    for path in TEMPLATE_DIR.rglob("*.json"):
        relative_template_path = path.relative_to(TEMPLATE_DIR)
        folder_name = relative_template_path.parts[0] if len(relative_template_path.parts) > 1 else ""
        if folder_name.lower() == "exmple":
            continue
        data = read_json(path)
        app_name = str(data.get("appName") or "").strip()
        page_name = str(data.get("pageName") or "").strip()
        if app_name or page_name:
            live_keys.add((app_name, page_name))
    return live_keys


def upsert_document(collection: Collection[Any], document: dict[str, Any], dry_run: bool) -> None:
    source_path = document["_sync"]["sourcePath"]
    if dry_run:
        print(f"[dry-run] Would upsert {collection.name}: {source_path}")
        return

    collection.replace_one({"_sync.sourcePath": source_path}, document, upsert=True)


def prune_removed_documents(
    collection: Collection[Any],
    source_type: str,
    source_paths: set[str],
    dry_run: bool,
) -> int:
    query = {"_sync.sourceType": source_type, "_sync.sourcePath": {"$nin": sorted(source_paths)}}
    existing = list(collection.find(query, {"_id": 1, "_sync.sourcePath": 1}))
    if not existing:
        return 0

    if dry_run:
        for item in existing:
            sync_meta = item.get("_sync") or {}
            print(f"[dry-run] Would prune {collection.name}: {sync_meta.get('sourcePath', '<unknown>')}")
        return len(existing)

    result = collection.delete_many(query)
    return int(result.deleted_count)


def sync_app_configs(db: Database[Any], dry_run: bool, prune: bool) -> SyncStats:
    stats = SyncStats()
    source_paths: set[str] = set()
    collection = db["app_config"]

    for path in sorted(APP_CONFIG_DIR.rglob("*.json")):
        stats.scanned += 1
        document = build_app_config_document(path)
        source_path = document["_sync"]["sourcePath"]
        source_paths.add(source_path)
        upsert_document(collection, document, dry_run)
        stats.synced += 1

    if prune:
        stats.pruned = prune_removed_documents(collection, "app_config", source_paths, dry_run)

    return stats


def sync_templates(db: Database[Any], example_folder_mode: str, dry_run: bool, prune: bool) -> SyncStats:
    stats = SyncStats()
    source_paths: set[str] = set()
    collection = db["template"]
    live_template_keys = collect_live_template_keys()

    for path in sorted(TEMPLATE_DIR.rglob("*.json")):
        stats.scanned += 1
        document = build_template_document(path, example_folder_mode, live_template_keys)
        if document is None:
            print(f"[skip] template: {relative_posix(path)} (example folder mode = skip)")
            stats.skipped += 1
            continue

        source_path = document["_sync"]["sourcePath"]
        source_paths.add(source_path)
        upsert_document(collection, document, dry_run)
        stats.synced += 1

    if prune:
        stats.pruned = prune_removed_documents(collection, "template", source_paths, dry_run)

    return stats


def print_summary(app_stats: SyncStats, template_stats: SyncStats, dry_run: bool) -> None:
    label = "DRY RUN SUMMARY" if dry_run else "SYNC SUMMARY"
    print(f"\n{label}")
    print(
        f"app_config: scanned={app_stats.scanned}, synced={app_stats.synced}, "
        f"skipped={app_stats.skipped}, pruned={app_stats.pruned}"
    )
    print(
        f"template: scanned={template_stats.scanned}, synced={template_stats.synced}, "
        f"skipped={template_stats.skipped}, pruned={template_stats.pruned}"
    )


def main() -> int:
    args = parse_args()
    env_mongo_uri, env_db_name = load_workspace_env()
    mongo_uri = args.mongo_uri or env_mongo_uri
    db_name = args.db_name or env_db_name

    if not APP_CONFIG_DIR.exists():
        raise SyncError(f"APP_CONFIG directory not found: {APP_CONFIG_DIR}")
    if not TEMPLATE_DIR.exists():
        raise SyncError(f"TEMPLATE directory not found: {TEMPLATE_DIR}")

    client: MongoClient[Any] | None = None
    try:
        if args.dry_run:
            print(f"[dry-run] Mongo URI: {mongo_uri}")
            print(f"[dry-run] Database: {db_name}")
            client = MongoClient(mongo_uri, connect=False)
            db = client[db_name]
            ensure_indexes(db, dry_run=True)
        else:
            client = MongoClient(mongo_uri)
            db = client[db_name]
            ensure_indexes(db, dry_run=False)

        app_stats = sync_app_configs(db, dry_run=args.dry_run, prune=args.prune)
        template_stats = sync_templates(
            db,
            example_folder_mode=args.example_folder_mode,
            dry_run=args.dry_run,
            prune=args.prune,
        )
        print_summary(app_stats, template_stats, dry_run=args.dry_run)
        return 0
    except SyncError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1
    finally:
        if client is not None:
            client.close()


if __name__ == "__main__":
    raise SystemExit(main())
