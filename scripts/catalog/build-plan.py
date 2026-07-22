#!/usr/bin/env python3
"""Build deterministic GridCatalogV2 registration calldata from reviewed JSON."""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import re
import subprocess
import sys
from typing import Any


ADDRESS = re.compile(r"^0x[0-9a-fA-F]{40}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
MODALITIES = {"text": 1, "image": 2, "video": 4, "audio": 8, "3d": 16}
JOB_TYPE_MODALITIES = {"text": 1, "image": 2, "video": 4, "audio": 8, "3d": 16}
MANIFEST_KEYS = {
    "schema",
    "slug",
    "version",
    "display_name",
    "modalities",
    "worker_model_names",
    "min_vram_mib",
    "artifacts",
    "runtime",
    "license",
}
ARTIFACT_KEYS = {"role", "filename", "sha256", "size_bytes", "source_uri"}
PLAN_KEYS = {"catalog_address", "publisher", "models", "recipes"}
MODEL_ENTRY_KEYS = {"manifest_path", "manifest_uri"}
RECIPE_ENTRY_KEYS = {
    "content_path",
    "content_uri",
    "slug",
    "version",
    "output_modalities",
    "required_model_releases",
}
MODEL_SIGNATURE = "registerModel((bytes32,bytes32,bytes32,bytes32,uint32,uint32,address,string))"
RECIPE_SIGNATURE = "registerRecipe((bytes32,bytes32,bytes32,uint32,address,string,bytes32[]))"


def canonical(value: Any) -> bytes:
    return json.dumps(
        value, sort_keys=True, separators=(",", ":"), ensure_ascii=False, allow_nan=False
    ).encode("utf-8")


def sha256_hex(value: bytes) -> str:
    return "0x" + hashlib.sha256(value).hexdigest()


def keccak_text(value: str) -> str:
    completed = subprocess.run(
        ["cast", "keccak", value], check=True, text=True, capture_output=True
    )
    return completed.stdout.strip()


def calldata(signature: str, value: str) -> str:
    completed = subprocess.run(
        ["cast", "calldata", signature, value], check=True, text=True, capture_output=True
    )
    return completed.stdout.strip()


def require_address(name: str, value: Any) -> str:
    if not isinstance(value, str) or not ADDRESS.fullmatch(value) or int(value, 16) == 0:
        raise ValueError(f"{name} must be a nonzero EVM address")
    return value


def require_uri(name: str, value: Any) -> str:
    if not isinstance(value, str) or not value or len(value.encode("utf-8")) > 256:
        raise ValueError(f"{name} must be a nonempty URI of at most 256 UTF-8 bytes")
    return value


def require_content_uri(name: str, value: Any) -> str:
    uri = require_uri(name, value)
    if not uri.startswith(("ipfs://", "ar://")):
        raise ValueError(f"{name} must use immutable ipfs:// or ar:// addressing")
    return uri


def require_exact_keys(name: str, value: Any, expected: set[str]) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ValueError(f"{name} must be a JSON object")
    actual = set(value)
    if actual != expected:
        missing = sorted(expected - actual)
        unknown = sorted(actual - expected)
        raise ValueError(f"{name} keys mismatch; missing={missing}, unknown={unknown}")
    return value


def modality_mask(values: Any) -> int:
    if not isinstance(values, list) or not values:
        raise ValueError("modalities must be a nonempty array")
    if len(set(values)) != len(values):
        raise ValueError("modalities must not contain duplicates")
    try:
        mask = sum(MODALITIES[value] for value in set(values))
    except (KeyError, TypeError) as exc:
        raise ValueError(f"unsupported modality in {values!r}") from exc
    return mask


def load_json(path: pathlib.Path) -> Any:
    def reject_duplicate(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError(f"duplicate JSON key {key!r} in {path}")
            result[key] = value
        return result

    return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=reject_duplicate)


def validate_manifest(
    manifest: Any, path: pathlib.Path
) -> tuple[str, str, int, int, str, tuple[str, ...]]:
    require_exact_keys(f"{path}: model manifest", manifest, MANIFEST_KEYS)
    if manifest.get("schema") != "aipg.model-manifest.v1":
        raise ValueError(f"{path}: unsupported model manifest schema")
    slug = manifest.get("slug")
    version = manifest.get("version")
    if not isinstance(slug, str) or not re.fullmatch(r"[a-z0-9][a-z0-9._-]{1,63}", slug):
        raise ValueError(f"{path}: slug must be lowercase ASCII and 2-64 characters")
    if not isinstance(version, str) or not version or len(version.encode()) > 64:
        raise ValueError(f"{path}: invalid version")
    display_name = manifest.get("display_name")
    if not isinstance(display_name, str) or not display_name or len(display_name.encode()) > 128:
        raise ValueError(f"{path}: invalid display_name")
    worker_names = manifest.get("worker_model_names")
    if (
        not isinstance(worker_names, list)
        or not worker_names
        or any(not isinstance(value, str) or not value or len(value.encode()) > 128 for value in worker_names)
        or len(set(worker_names)) != len(worker_names)
    ):
        raise ValueError(f"{path}: worker_model_names must be unique nonempty strings")
    if not isinstance(manifest.get("runtime"), dict) or not manifest["runtime"]:
        raise ValueError(f"{path}: runtime metadata is required")
    if not isinstance(manifest.get("license"), dict) or not manifest["license"]:
        raise ValueError(f"{path}: license metadata is required")
    minimum_vram = manifest.get("min_vram_mib")
    if not isinstance(minimum_vram, int) or minimum_vram < 0 or minimum_vram > 2**32 - 1:
        raise ValueError(f"{path}: min_vram_mib must fit uint32")
    artifacts = manifest.get("artifacts")
    if not isinstance(artifacts, list) or not artifacts:
        raise ValueError(f"{path}: at least one artifact is required")
    seen = set()
    for artifact in artifacts:
        require_exact_keys(f"{path}: artifact", artifact, ARTIFACT_KEYS)
        digest = artifact.get("sha256")
        size = artifact.get("size_bytes")
        filename = artifact.get("filename")
        role = artifact.get("role")
        if not isinstance(digest, str) or not SHA256.fullmatch(digest) or int(digest, 16) == 0:
            raise ValueError(f"{path}: artifact sha256 must be a nonzero lowercase digest")
        if not isinstance(size, int) or size <= 0:
            raise ValueError(f"{path}: artifact size_bytes must be positive")
        if not isinstance(filename, str) or not filename or not isinstance(role, str) or not role:
            raise ValueError(f"{path}: artifact filename and role are required")
        key = (role, filename, digest)
        if key in seen:
            raise ValueError(f"{path}: duplicate artifact {filename}")
        seen.add(key)
        require_uri(f"{path}: artifact source_uri", artifact.get("source_uri"))
    artifacts_sorted = sorted(artifacts, key=lambda item: (item["role"], item["filename"], item["sha256"]))
    if artifacts != artifacts_sorted:
        raise ValueError(f"{path}: artifacts must be sorted by role, filename, then sha256")
    return (
        slug,
        version,
        modality_mask(manifest.get("modalities")),
        minimum_vram,
        sha256_hex(canonical(artifacts_sorted)),
        tuple(sorted(worker_names)),
    )


def tuple_value(parts: list[str]) -> str:
    return "(" + ",".join(parts) + ")"


def build(plan_path: pathlib.Path) -> dict[str, Any]:
    source = load_json(plan_path)
    require_exact_keys("registration plan", source, PLAN_KEYS)
    base = plan_path.parent
    catalog_address = require_address("catalog_address", source.get("catalog_address"))
    publisher = require_address("publisher", source.get("publisher"))
    models = []
    releases: dict[str, tuple[str, tuple[str, ...]]] = {}

    model_entries = source["models"]
    recipe_entries = source["recipes"]
    if not isinstance(model_entries, list) or not isinstance(recipe_entries, list):
        raise ValueError("models and recipes must be JSON arrays")

    for entry in model_entries:
        require_exact_keys("model plan entry", entry, MODEL_ENTRY_KEYS)
        path = (base / entry["manifest_path"]).resolve()
        manifest = load_json(path)
        slug, version, mask, min_vram, artifact_root, worker_names = validate_manifest(manifest, path)
        manifest_hash = sha256_hex(canonical(manifest))
        release = f"{slug}@{version}"
        if release in releases:
            raise ValueError(f"duplicate model release {release}")
        releases[release] = (manifest_hash, worker_names)
        uri = require_content_uri("manifest_uri", entry.get("manifest_uri"))
        values = [
            manifest_hash,
            artifact_root,
            keccak_text(slug),
            keccak_text(version),
            str(mask),
            str(min_vram),
            publisher,
            json.dumps(uri),
        ]
        data = calldata(MODEL_SIGNATURE, tuple_value(values))
        models.append(
            {
                "release": release,
                "manifest_path": str(path),
                "model_id": manifest_hash,
                "artifact_root": artifact_root,
                "manifest_uri": uri,
                "calldata": data,
                "ledger_command": f"cast send {catalog_address} --data {data} --ledger --rpc-url $BASE_RPC_URL",
            }
        )

    recipes = []
    recipe_releases = set()
    for entry in recipe_entries:
        require_exact_keys("recipe plan entry", entry, RECIPE_ENTRY_KEYS)
        path = (base / entry["content_path"]).resolve()
        content = load_json(path)
        if not isinstance(content, dict) or not isinstance(content.get("_grid"), dict):
            raise ValueError(f"{path}: recipe must contain a _grid object")
        slug = entry.get("slug")
        version = entry.get("version")
        if not isinstance(slug, str) or not re.fullmatch(r"[a-z0-9][a-z0-9._-]{1,63}", slug):
            raise ValueError(f"{path}: invalid recipe slug")
        if not isinstance(version, str) or not version or len(version.encode()) > 64:
            raise ValueError(f"{path}: invalid recipe version")
        release = f"{slug}@{version}"
        if release in recipe_releases:
            raise ValueError(f"duplicate recipe release {release}")
        recipe_releases.add(release)
        requirements = entry.get("required_model_releases")
        if not isinstance(requirements, list) or not 1 <= len(requirements) <= 8:
            raise ValueError(f"{path}: required_model_releases must contain 1-8 entries")
        try:
            release_records = [releases[value] for value in requirements]
        except KeyError as exc:
            raise ValueError(f"{path}: unknown model release {exc.args[0]}") from exc
        model_ids = [record[0] for record in release_records]
        if len(set(model_ids)) != len(model_ids):
            raise ValueError(f"{path}: duplicate model requirement")
        declared_worker_models = content["_grid"].get("requiredModels")
        expected_worker_models = sorted(
            {name for _, worker_names in release_records for name in worker_names}
        )
        if not isinstance(declared_worker_models, list) or sorted(declared_worker_models) != expected_worker_models:
            raise ValueError(
                f"{path}: _grid.requiredModels must equal manifest worker names {expected_worker_models}"
            )
        model_ids.sort()
        uri = require_content_uri("content_uri", entry.get("content_uri"))
        content_hash = sha256_hex(canonical(content))
        output_mask = modality_mask(entry.get("output_modalities"))
        job_type = content["_grid"].get("jobType")
        if job_type not in JOB_TYPE_MODALITIES:
            raise ValueError(f"{path}: unsupported _grid.jobType {job_type!r}")
        if output_mask & JOB_TYPE_MODALITIES[job_type] == 0:
            raise ValueError(
                f"{path}: output_modalities must include _grid.jobType {job_type!r}"
            )
        array_value = "[" + ",".join(model_ids) + "]"
        values = [
            content_hash,
            keccak_text(slug),
            keccak_text(version),
            str(output_mask),
            publisher,
            json.dumps(uri),
            array_value,
        ]
        data = calldata(RECIPE_SIGNATURE, tuple_value(values))
        recipes.append(
            {
                "release": release,
                "content_path": str(path),
                "recipe_id": content_hash,
                "content_uri": uri,
                "required_model_ids": model_ids,
                "calldata": data,
                "ledger_command": f"cast send {catalog_address} --data {data} --ledger --rpc-url $BASE_RPC_URL",
            }
        )

    return {
        "schema": "aipg.grid-catalog-registration-plan.v1",
        "catalog_address": catalog_address,
        "publisher": publisher,
        "models": models,
        "recipes": recipes,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("plan", type=pathlib.Path)
    args = parser.parse_args()
    try:
        result = build(args.plan.resolve())
    except (KeyError, OSError, ValueError, subprocess.CalledProcessError) as exc:
        print(f"catalog plan error: {exc}", file=sys.stderr)
        return 1
    json.dump(result, sys.stdout, indent=2)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
