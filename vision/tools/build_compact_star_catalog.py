#!/usr/bin/env python3
"""Build a deterministic Camerae offline star catalog from a CSV export."""

from __future__ import annotations

import argparse
import csv
import pathlib
import struct


MAGIC = b"CAMCAT01"


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=pathlib.Path)
    parser.add_argument("--output", required=True, type=pathlib.Path)
    parser.add_argument("--id-column", default="source_id")
    parser.add_argument("--ra-column", default="ra")
    parser.add_argument("--dec-column", default="dec")
    parser.add_argument("--magnitude-column", default="phot_g_mean_mag")
    parser.add_argument("--maximum-magnitude", type=float, default=7.0)
    parser.add_argument("--maximum-stars", type=int, default=50_000)
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    stars: list[tuple[float, float, float, str]] = []
    with arguments.input.open(newline="", encoding="utf-8-sig") as stream:
        reader = csv.DictReader(stream)
        required = {
            arguments.id_column,
            arguments.ra_column,
            arguments.dec_column,
            arguments.magnitude_column,
        }
        missing = required.difference(reader.fieldnames or [])
        if missing:
            raise ValueError(f"missing CSV columns: {', '.join(sorted(missing))}")
        for row in reader:
            magnitude = float(row[arguments.magnitude_column])
            if magnitude > arguments.maximum_magnitude:
                continue
            stars.append(
                (
                    magnitude,
                    float(row[arguments.ra_column]) % 360.0,
                    float(row[arguments.dec_column]),
                    row[arguments.id_column],
                )
            )

    stars.sort(key=lambda star: (star[0], star[3]))
    stars = stars[: arguments.maximum_stars]
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    with arguments.output.open("wb") as output:
        output.write(MAGIC)
        output.write(struct.pack("<I", len(stars)))
        for magnitude, right_ascension, declination, identifier in stars:
            encoded_identifier = identifier.encode("utf-8")
            if len(encoded_identifier) > 65_535:
                raise ValueError("catalog identifier exceeds 65535 UTF-8 bytes")
            output.write(
                struct.pack(
                    "<fffH",
                    right_ascension,
                    declination,
                    magnitude,
                    len(encoded_identifier),
                )
            )
            output.write(encoded_identifier)

    print(
        f"[CameraePlateSolve] catalog.completed"
        f" | stars={len(stars)} output={arguments.output}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
