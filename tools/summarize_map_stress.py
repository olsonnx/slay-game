"""Summarize native stress samples without discarding frame-time outliers."""
import csv
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
rows = []
for path in sorted((ROOT / "artifacts").glob("map_stress_*.json")):
    data = json.loads(path.read_text(encoding="utf-8-sig"))
    for result in data.get("results", []):
        if "fps_mean" not in result:
            continue
        row = {key: value for key, value in result.items()
               if key not in ("frame_intervals_ms", "generation_stages_ms")}
        row["run"] = path.stem.removeprefix("map_stress_")
        row["p95_pass_240"] = result["frame_ms_p95"] <= 1000 / 240
        row["p99_pass_240"] = result["frame_ms_p99"] <= 1000 / 240
        rows.append(row)
fields = sorted({key for row in rows for key in row})
with (ROOT / "artifacts/map_stress_summary.csv").open("w", newline="", encoding="utf-8") as out:
    writer = csv.DictWriter(out, fieldnames=fields)
    writer.writeheader()
    writer.writerows(rows)
for row in rows:
    print(f"{row['run']:12} {str(row['target_tiles']):10} {row['tiles']:5} "
          f"{row['seed']:3} {row['case']:15} mean={row['fps_mean']:6.1f} "
          f"p95={row['frame_ms_p95']:5.2f} p99={row['frame_ms_p99']:5.2f} "
          f"over={row['over_budget_percent']:5.2f}%")
