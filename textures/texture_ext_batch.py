from __future__ import annotations

import argparse
from texture_ext import (
    DEFAULT_BATCH_STATE_FILE,
    DEFAULT_FEATURE_SIZE,
    DEFAULT_OUTPUT_NAME,
    DEFAULT_OUTPUT_SIZE,
    DEFAULT_WEBP_QUALITY,
    run_batch_manual,
)


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description=(
            "Compatibility wrapper around `texture_ext.py --batch-manual`."
        )
    )
    p.add_argument("--output-name", type=str, default=DEFAULT_OUTPUT_NAME)
    p.add_argument("--output-size", type=int, default=DEFAULT_OUTPUT_SIZE)
    p.add_argument("--feature-size", type=int, default=DEFAULT_FEATURE_SIZE)
    p.add_argument("--quality", type=int, default=DEFAULT_WEBP_QUALITY)
    p.add_argument(
        "--single-face",
        dest="single_face_features",
        action="store_true",
        default=False,
        help="Front-only feature mode for back face.",
    )
    p.add_argument(
        "--full-sphere",
        dest="single_face_features",
        action="store_false",
        help="Mirror full feature detail between faces (default).",
    )
    p.add_argument(
        "--state-file",
        type=str,
        default=str(DEFAULT_BATCH_STATE_FILE),
        help="Local file storing the last processed marble folder name.",
    )
    p.add_argument(
        "--from-start",
        action="store_true",
        help="Ignore saved progress and start from the first marble folder.",
    )
    return p.parse_args()


def main() -> None:
    raw = parse_args()
    args = argparse.Namespace(
        output_name=raw.output_name,
        output_size=raw.output_size,
        feature_size=raw.feature_size,
        quality=raw.quality,
        single_face_features=raw.single_face_features,
        state_file=raw.state_file,
        from_start=raw.from_start,
        batch_manual=True,
    )
    run_batch_manual(args)


if __name__ == "__main__":
    main()
