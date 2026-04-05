## ToastManager — 뉴스 토스트 알림 스택.
## VBoxContainer 자체가 토스트 컨테이너. TradingScreen이 화면 하단에 배치한다.
## reduced_motion 지원 (TD-07 잔여분). See: design/gdd/trading-screen.md §10
class_name ToastManager
extends VBoxContainer

## Emitted for every non-system news entry shown (caller updates tab badge).
signal news_received

const TOAST_DURATION: float = 3.5
const TOAST_MAX: int = 4
const TOAST_SCOPE_LABELS: Dictionary = {
	"MACRO": "시장",
	"SECTOR": "업종",
	"INDIVIDUAL": "개별",
}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	NewsEventSystem.on_news_display.connect(_on_news_display)


func _on_news_display(entry: Dictionary) -> void:
	if entry.get("is_system_event", false):
		return
	var headline: String = str(entry.get("headline", ""))
	if headline.is_empty():
		return
	var scope: String = str(entry.get("scope", "MACRO"))
	var tag: String = TOAST_SCOPE_LABELS.get(scope, scope)
	_show_toast("[%s] %s" % [tag, headline])
	news_received.emit()


func _show_toast(text: String) -> void:
	while get_child_count() >= TOAST_MAX:
		var oldest: Node = get_child(0)
		remove_child(oldest)
		oldest.queue_free()

	var toast: PanelContainer = _make_toast_node(text)
	add_child(toast)

	if _reduced_motion():
		await get_tree().process_frame
		toast.queue_free()
		return

	toast.modulate.a = 0.0
	var tween: Tween = create_tween()
	tween.tween_property(toast, "modulate:a", 1.0, 0.2)
	tween.tween_interval(TOAST_DURATION)
	tween.tween_property(toast, "modulate:a", 0.0, 0.4)
	tween.tween_callback(toast.queue_free)


func _make_toast_node(text: String) -> PanelContainer:
	var toast: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.10, 0.12, 0.95)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(14)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.border_color = Color.TRANSPARENT
	style.set_border_width_all(0)
	toast.add_theme_stylebox_override("panel", style)
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lbl: Label = Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.add_child(lbl)
	return toast


func _reduced_motion() -> bool:
	return ProjectSettings.get_setting("accessibility/reduced_motion", false)
