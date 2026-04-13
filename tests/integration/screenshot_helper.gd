## ScreenshotHelper — Captures viewport PNGs and generates an HTML QA report.
## Lives entirely in tests/integration/. Zero modifications to src/.
## Skips PNG capture gracefully when running headless (--headless flag).
extends Node

var _run_dir: String = ""
var _run_id: String = ""
var _captures: Array[Dictionary] = []  ## [{label, path, timestamp}]
var _attached_data: Dictionary = {}    ## {key: any} — arbitrary data for report


# ── Public API ──

## Set the output directory for this test run. Call before any capture().
## Creates: user://test_results/{run_id}/
func begin_run(run_id: String) -> void:
	_run_id = run_id
	var timestamp: String = Time.get_datetime_string_from_system(false, true).replace(":", "-")
	_run_dir = "user://test_results/%s_%s/" % [run_id, timestamp]
	DirAccess.make_dir_recursive_absolute(_run_dir)
	_captures.clear()
	_attached_data.clear()


## Capture the current viewport to a PNG. Silent no-op in headless/dummy renderer.
## label: short identifier, e.g. "after_10_days" or "day_05_settlement"
func capture(label: String) -> void:
	await get_tree().process_frame  # ensure UI has had a frame to render
	var img: Image = _try_get_viewport_image()
	if img == null:
		return  # headless or dummy renderer — silently skip
	var fname: String = "%s_%s.png" % [_captures.size() + 1, label]
	var path: String = _run_dir + fname
	var err: Error = img.save_png(path)
	if err != OK:
		push_warning("ScreenshotHelper: save_png failed (%d) for '%s'" % [err, path])
		return
	_captures.append({
		"label": label,
		"path": path,
		"fname": fname,
		"timestamp": Time.get_ticks_msec(),
	})


## Attach arbitrary data (snapshots, diffs) to the report.
func attach_data(key: String, value: Variant) -> void:
	_attached_data[key] = value


## Generate HTML report to user://test_results/{run_id}_report.html.
## Returns the absolute path to the report file.
func generate_report(
	daily_snaps: Array[Dictionary],
	pre_save: Dictionary,
	post_load: Dictionary,
	issues: Array[Dictionary]
) -> String:
	var report_path: String = _run_dir + "report.html"
	var file: FileAccess = FileAccess.open(report_path, FileAccess.WRITE)
	if file == null:
		push_warning("ScreenshotHelper: cannot write report to %s" % report_path)
		return ""

	var pass_fail: String = "✅ PASS" if issues.is_empty() else "❌ FAIL (%d건)" % issues.size()
	var html: String = _build_html(pass_fail, daily_snaps, pre_save, post_load, issues)
	file.store_string(html)
	file.close()

	# Also write raw JSON snapshots for machine-readable access
	_write_json("pre_save.json", pre_save)
	_write_json("post_load.json", post_load)
	_write_json("daily_snapshots.json", {"days": daily_snaps})
	if not issues.is_empty():
		_write_json("diff_issues.json", {"issues": issues})

	print("ScreenshotHelper: report → %s" % report_path)
	return report_path


# ── Internal ──

## Returns the viewport image, or null if rendering is unavailable.
## Checks DisplayServer and RenderingServer to avoid engine errors in headless/dummy mode.
func _try_get_viewport_image() -> Image:
	# Headless/dummy display servers have no GPU texture backing.
	# Calling ViewportTexture.get_image() on them triggers a C++ engine error.
	var ds_name: String = DisplayServer.get_name().to_lower()
	if ds_name == "headless" or ds_name == "dummy":
		return null
	var vp := get_viewport()
	if vp == null:
		return null
	var tex: ViewportTexture = vp.get_texture()
	if tex == null:
		return null
	var img: Image = tex.get_image()
	if img == null or img.is_empty():
		return null
	return img


func _write_json(fname: String, data: Variant) -> void:
	var path: String = _run_dir + fname
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(data, "  "))
	file.close()


func _build_html(
	pass_fail: String,
	daily_snaps: Array[Dictionary],
	pre_save: Dictionary,
	post_load: Dictionary,
	issues: Array[Dictionary]
) -> String:
	var parts: Array[String] = []
	parts.append("""<!DOCTYPE html>
<html lang="ko"><head><meta charset="utf-8">
<title>QA Report — 10-Day Save/Load Scenario</title>
<style>
  body { font-family: 'Malgun Gothic', sans-serif; margin: 2em; background: #111; color: #ddd; }
  h1 { color: #fff; }
  h2 { color: #aef; border-bottom: 1px solid #333; padding-bottom: 4px; }
  table { border-collapse: collapse; width: 100%%; margin-bottom: 2em; }
  th { background: #223; color: #aef; padding: 6px 10px; text-align: left; }
  td { padding: 5px 10px; border-bottom: 1px solid #222; }
  tr.fail td { background: #400; color: #f88; }
  tr.pass td { background: #040; color: #8f8; }
  .status { font-size: 2em; padding: 12px; border-radius: 6px;
            background: %s; display: inline-block; margin-bottom: 1em; }
  img { max-width: 100%%; border: 2px solid #444; margin: 6px 0; border-radius: 4px; }
  .grid { display: grid; grid-template-columns: 1fr 1fr; gap: 1em; }
  pre { background: #1a1a1a; padding: 1em; border-radius: 4px; overflow-x: auto;
        font-size: 0.85em; color: #bfb; }
</style></head><body>
""" % ("#022" if issues.is_empty() else "#400"))

	parts.append("<h1>QA — 10-Day Save/Load Consistency Test</h1>\n")
	parts.append("<div class='status'>%s</div>\n" % pass_fail)
	parts.append("<p>Run: <code>%s</code></p>\n" % _run_id)

	# Screenshots
	if not _captures.is_empty():
		parts.append("<h2>스크린샷</h2><div class='grid'>\n")
		for cap: Dictionary in _captures:
			parts.append("<div><p><b>%s</b></p><img src='%s'></div>\n" % [
				cap["label"], cap["fname"]])
		parts.append("</div>\n")

	# Diff table
	parts.append("<h2>Save/Load 차이 (%d건)</h2>\n" % issues.size())
	if issues.is_empty():
		parts.append("<p style='color:#8f8'>✅ 모든 시스템 내부 상태 완벽 일치</p>\n")
	else:
		parts.append("<table><tr><th>필드</th><th>유형</th><th>저장 전</th><th>로드 후</th></tr>\n")
		for issue: Dictionary in issues:
			parts.append("<tr class='fail'><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>\n" % [
				issue.get("field", ""), issue.get("type", ""),
				str(issue.get("before", "")), str(issue.get("after", ""))])
		parts.append("</table>\n")

	# Daily progression
	parts.append("<h2>일별 진행 데이터</h2>\n")
	parts.append("<table><tr><th>Day</th><th>현금</th><th>총자산</th><th>수익률</th><th>XP</th><th>레벨</th><th>보유종목</th></tr>\n")
	for snap: Dictionary in daily_snaps:
		parts.append("<tr><td>%d</td><td>%s</td><td>%s</td><td>%.2f%%</td><td>%d</td><td>%d</td><td>%d</td></tr>\n" % [
			snap.get("sim_day_idx", 0) + 1,
			_fmt_cash(snap.get("sim_cash", 0)),
			_fmt_cash(snap.get("total_assets", 0)),
			snap.get("return_rate", 0.0),
			snap.get("xp_total", 0),
			snap.get("xp_level", 1),
			snap.get("holding_count", 0),
		])
	parts.append("</table>\n")

	# Key field comparison table
	parts.append("<h2>저장/로드 핵심 수치 비교</h2>\n")
	parts.append("<table><tr><th>항목</th><th>저장 전</th><th>로드 후</th><th>일치</th></tr>\n")
	var compare_fields: Array[String] = [
		"sim_cash", "portfolio_total_assets", "portfolio_return_rate",
		"xp_total", "xp_level", "xp_available_sp",
		"clock_day", "clock_week",
		"season_return_pct", "season_tier",
		"portfolio_holding_count", "portfolio_tx_count",
	]
	for field: String in compare_fields:
		var b_val: Variant = pre_save.get(field, "N/A")
		var a_val: Variant = post_load.get(field, "N/A")
		var match_str: String = "✅" if b_val == a_val else "❌"
		var row_class: String = "pass" if b_val == a_val else "fail"
		parts.append("<tr class='%s'><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>\n" % [
			row_class, field, str(b_val), str(a_val), match_str])
	parts.append("</table>\n")

	parts.append("</body></html>")
	return "".join(parts)


func _fmt_cash(amount: int) -> String:
	# Simple thousands separator
	var s: String = str(absi(amount))
	var result: String = ""
	var count: int = 0
	for i: int in range(s.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "," + result
		result = s[i] + result
		count += 1
	return ("₩-" if amount < 0 else "₩") + result
