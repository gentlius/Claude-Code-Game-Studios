## UI Theme — Dark trading terminal theme for Seed Money.
## Applied once at startup. All colors/styles defined here.
class_name ThemeSetup
extends RefCounted

# ── Color Palette ──

const BG_DARKEST: Color = Color(0.08, 0.08, 0.10)
const BG_DARK: Color = Color(0.11, 0.11, 0.14)
const BG_PANEL: Color = Color(0.14, 0.14, 0.18)
const BG_CARD: Color = Color(0.17, 0.17, 0.22)
const BG_HOVER: Color = Color(0.22, 0.22, 0.28)
const BG_SELECTED: Color = Color(0.18, 0.22, 0.32)

const BORDER_DIM: Color = Color(0.25, 0.25, 0.32)
const BORDER_BRIGHT: Color = Color(0.35, 0.35, 0.45)

const TEXT_PRIMARY: Color = Color(0.90, 0.90, 0.92)
const TEXT_SECONDARY: Color = Color(0.60, 0.60, 0.65)
const TEXT_DIM: Color = Color(0.40, 0.40, 0.45)

const PROFIT_RED: Color = Color(0.92, 0.25, 0.22)       # Korean convention: profit=red
const LOSS_BLUE: Color = Color(0.22, 0.45, 0.92)         # Korean convention: loss=blue
const NEUTRAL_GRAY: Color = Color(0.55, 0.55, 0.55)

const BTN_NORMAL: Color = Color(0.20, 0.20, 0.26)
const BTN_HOVER: Color = Color(0.28, 0.28, 0.35)
const BTN_PRESSED: Color = Color(0.15, 0.18, 0.28)
const BTN_BUY: Color = Color(0.15, 0.30, 0.18)
const BTN_BUY_HOVER: Color = Color(0.20, 0.40, 0.25)
const BTN_SELL: Color = Color(0.35, 0.15, 0.12)
const BTN_SELL_HOVER: Color = Color(0.45, 0.20, 0.15)
const BTN_ACCENT: Color = Color(0.20, 0.35, 0.55)
const BTN_ACCENT_HOVER: Color = Color(0.25, 0.45, 0.65)

const SEPARATOR: Color = Color(0.22, 0.22, 0.28)

# ── Factory Methods ──

static func make_panel_style(bg: Color = BG_PANEL, radius: int = 4, border: Color = BORDER_DIM, border_width: int = 1) -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.border_color = border
	s.set_border_width_all(border_width)
	s.set_content_margin_all(6)
	return s


static func make_button_style(bg: Color = BTN_NORMAL, radius: int = 4) -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.border_color = BORDER_BRIGHT
	s.set_border_width_all(1)
	s.set_content_margin_all(6)
	return s


static func apply_button_theme(btn: Button, normal_bg: Color = BTN_NORMAL, hover_bg: Color = BTN_HOVER, pressed_bg: Color = BTN_PRESSED) -> void:
	btn.add_theme_stylebox_override("normal", make_button_style(normal_bg))
	btn.add_theme_stylebox_override("hover", make_button_style(hover_bg))
	btn.add_theme_stylebox_override("pressed", make_button_style(pressed_bg))
	btn.add_theme_stylebox_override("focus", make_button_style(normal_bg))
	btn.add_theme_color_override("font_color", TEXT_PRIMARY)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", TEXT_SECONDARY)


static func apply_accent_button(btn: Button) -> void:
	apply_button_theme(btn, BTN_ACCENT, BTN_ACCENT_HOVER, BTN_PRESSED)


static func apply_buy_button(btn: Button) -> void:
	apply_button_theme(btn, BTN_BUY, BTN_BUY_HOVER, BTN_PRESSED)


static func apply_sell_button(btn: Button) -> void:
	apply_button_theme(btn, BTN_SELL, BTN_SELL_HOVER, BTN_PRESSED)


static func style_label_primary(lbl: Label) -> void:
	lbl.add_theme_color_override("font_color", TEXT_PRIMARY)


static func style_label_secondary(lbl: Label) -> void:
	lbl.add_theme_color_override("font_color", TEXT_SECONDARY)


static func style_label_dim(lbl: Label) -> void:
	lbl.add_theme_color_override("font_color", TEXT_DIM)
