#!/usr/bin/env python3
"""Validate a BeerJSON file against the official schema.

Usage: python3 tools/validate_beerjson.py <path-to-beerjson-repo> <file.json>
(the schema lives in the repo's json/ folder: https://github.com/beerjson/beerjson)
"""
import json
import os
import sys

from jsonschema import Draft202012Validator
from referencing import Registry, Resource


def main(schema_repo, path):
    folder = os.path.join(schema_repo, "json")
    registry = Registry()
    for name in os.listdir(folder):
        if name.endswith(".json"):
            with open(os.path.join(folder, name), encoding="utf-8") as f:
                schema = json.load(f)
            resource = Resource.from_contents(schema)
            registry = registry.with_resource(name, resource)
            if "$id" in schema:
                registry = registry.with_resource(schema["$id"], resource)
    with open(os.path.join(folder, "beer.json"), encoding="utf-8") as f:
        root = json.load(f)
    validator = Draft202012Validator(root, registry=registry)
    with open(path, encoding="utf-8") as f:
        document = json.load(f)
    errors = sorted(validator.iter_errors(document), key=lambda e: list(e.absolute_path))
    for error in errors:
        print(f"{'/'.join(map(str, error.absolute_path)) or '<root>'}: {error.message}")
    if errors:
        sys.exit(f"{len(errors)} schema error(s)")
    print(f"{path}: valid BeerJSON")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
