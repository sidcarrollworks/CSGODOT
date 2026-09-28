"""Summarize profile_combat --output CSVs without third-party dependencies.

python scripts/summarize_frame_audit.py .godot/frame-audit --output summary.json
The CSVs contain end-of-process intervals, not OS presentation timestamps.
Percentiles use nearest rank. A maximum describes this recording only.
"""
import argparse
from bisect import bisect_left
import csv
import json
import math
from pathlib import Path
from statistics import mean


def stats(values):
    values = sorted(values)
    if not values:
        return {"count": 0}
    result = {"count": len(values), "mean": mean(values), "max": values[-1]}
    for name, percentile in (("p50", .5), ("p95", .95), ("p99", .99), ("p999", .999)):
        result[name] = values[max(0, math.ceil(len(values) * percentile) - 1)]
    return {key: round(value, 4) if isinstance(value, float) else value for key, value in result.items()}


def focused_stable_rows(rows, guard_seconds=.25):
    """Retain whole frame intervals clear of observed/ambiguous focus loss."""
    bad = []
    prior_focused = True
    for row in rows:
        focused = bool(row["focused"])
        if not focused or not prior_focused:
            # A flag describes the interval's endpoint. The first refocused
            # interval can contain a long background pause, even if its end
            # is seconds away from the previous unfocused sample.
            end = row["seconds"]
            start = end - row["frame_ms"] / 1000
            bad.append((start - guard_seconds, end + guard_seconds))
        prior_focused = focused
    merged = []
    for start, end in sorted(bad):
        if merged and start <= merged[-1][1]:
            merged[-1] = (merged[-1][0], max(merged[-1][1], end))
        else:
            merged.append((start, end))
    bad_ends = [end for _, end in merged]
    selected = []
    for row in rows:
        end = row["seconds"]
        start = end - row["frame_ms"] / 1000
        candidate = bisect_left(bad_ends, start)
        if candidate == len(merged) or merged[candidate][0] > end:
            selected.append(row)
    return selected


def summarize(path):
    with path.open(newline="", encoding="utf-8-sig") as source:
        rows = [{k: float(v) for k, v in row.items()} for row in csv.DictReader(source)]
    metadata = json.loads(path.with_suffix(".json").read_text(encoding="utf-8-sig"))
    ticks = metadata.pop("tick_callbacks_us", [])
    result = {"name": path.stem, "metadata": metadata}
    # Exclude focus transitions plus a 250 ms guard on both sides, retaining
    # all raw samples and their separate statistics for an honest audit.
    focused_stable = focused_stable_rows(rows)
    for name, selection in {
        "all": rows,
        "no_tick": [r for r in rows if r["ticks"] == 0],
        "one_tick": [r for r in rows if r["ticks"] == 1],
        "catchup_ticks": [r for r in rows if r["ticks"] > 1],
        "combat": [r for r in rows if r["combat"]],
        "no_combat": [r for r in rows if not r["combat"]],
        "first_30s": [r for r in rows if r["seconds"] < 30],
        "after_30s": [r for r in rows if r["seconds"] >= 30],
        "unfocused": [r for r in rows if not r["focused"]],
        "focused_stable": focused_stable,
    }.items():
        result[name] = stats([r["frame_ms"] for r in selection])
    result["thresholds"] = {
        str(limit): {"frames": sum(r["frame_ms"] > limit for r in rows),
                     "percent": round(100 * sum(r["frame_ms"] > limit for r in rows) / max(1, len(rows)), 3)}
        for limit in (6, 8, 16.667, 33.333, 50, 100)
    }
    result["focused_thresholds"] = {
        str(limit): {"frames": sum(r["frame_ms"] > limit for r in focused_stable),
                     "percent": round(100 * sum(r["frame_ms"] > limit for r in focused_stable) / max(1, len(focused_stable)), 3)}
        for limit in (6, 8, 16.667, 33.333, 50, 100)
    }
    for name in ("gpu_ms", "render_cpu_ms", "render_setup_cpu_ms", "tick_callbacks_ms", "frame_callbacks_ms", "draw_calls", "triangles", "video_mib"):
        result[name] = stats([r[name] for r in rows])
    result["tick_callbacks_per_tick_ms"] = stats([v / 1000 for v in ticks])
    result["avg_fps"] = round(1000 / result["all"]["mean"], 2)
    result["alive_range"] = [int(min(r["alive"] for r in rows)), int(max(r["alive"] for r in rows))]
    result["shots_end"] = int(rows[-1]["shots"])
    buckets = {}
    for row in rows:
        second = int(row["seconds"])
        buckets[second] = max(buckets.get(second, 0), row["frame_ms"])
    result["one_second_bucket_max_ms"] = stats(list(buckets.values()))
    # Only complete recorded seconds with every sampled interval eligible;
    # CS2 documents a recent-window maximum, not a fixed one-second bin.
    focused_ids = {id(r) for r in focused_stable}
    invalid_seconds = {int(r["seconds"]) for r in rows if id(r) not in focused_ids}
    valid_buckets = [v for k, v in buckets.items() if k not in invalid_seconds and k < int(rows[-1]["seconds"])]
    result["focused_one_second_bucket_max_ms"] = stats(valid_buckets)
    result["worst_frames"] = sorted(rows, key=lambda r: r["frame_ms"], reverse=True)[:12]
    result["worst_focused_frames"] = sorted(focused_stable, key=lambda r: r["frame_ms"], reverse=True)[:12]
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    results = []
    for path in sorted(args.directory.glob("*.csv")):
        if path.with_suffix(".json").exists():
            results.append(summarize(path))
    if args.output:
        args.output.write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")
    print("| Run | Frames | Avg FPS | p50 | p95 | p99 | p99.9 | Max ms | GPU mean | Tick mean | >6 ms |")
    print("|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
    for result in results:
        t = result["all"]
        print(f'| {result["name"]} | {t["count"]} | {result["avg_fps"]:.0f} | '
              f'{t["p50"]:.2f} | {t["p95"]:.2f} | {t["p99"]:.2f} | {t["p999"]:.2f} | '
              f'{t["max"]:.2f} | {result["gpu_ms"]["mean"]:.2f} | '
              f'{result["tick_callbacks_per_tick_ms"].get("mean", 0):.2f} | '
              f'{result["thresholds"]["6"]["percent"]:.1f}% |')


if __name__ == "__main__":
    main()
