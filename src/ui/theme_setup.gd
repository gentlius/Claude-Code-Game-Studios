## UI Theme — Clean white-base theme inspired by Toss Securities.
## Applied once at startup. All colors/styles defined here.
## Call ThemeSetup.apply_base_theme(tree) in _ready() to set global defaults.
class_name ThemeSetup
extends RefCounted

# ── Color Palette (White Base — Toss Securities Style) ──

const BG_DARKEST: Color = Color(0.96, 0.96, 0.97)   # #F5F5F8 page background
const BG_DARK: Color = Color(0.98, 0.98, 0.99)       # #FAFAFC section bg
const BG_PANEL: Color = Color(1.0, 1.0, 1.0)          # #FFFFFF card/panel
const BG_CARD: Color = Color(1.0, 1.0, 1.0)           # #FFFFFF
const BG_HOVER: Color = Color(0.95, 0.95, 0.97)       # #F2F2F8
const BG_SELECTED: Color = Color(0.91, 0.94, 1.0)     # #E8F0FF blue tint

const BORDER_DIM: Color = Color(0.90, 0.90, 0.92)     # #E6E6EB subtle
const BORDER_BRIGHT: Color = Color(0.82, 0.82, 0.85)  # #D1D1D9

const TEXT_PRIMARY: Color = Color(0.13, 0.13, 0.15)    # #212126 near-black
const TEXT_SECONDARY: Color = Color(0.35, 0.35, 0.40)  # #5A5A66 readable gray
const TEXT_DIM: Color = Color(0.50, 0.50, 0.53)        # #808087 softer but visible

const PROFIT_RED: Color = Color(0.92, 0.22, 0.20)      # #EB3833 Korean: profit=red
const LOSS_BLUE: Color = Color(0.18, 0.42, 0.90)       # #2E6BE6 Korean: loss=blue
const NEUTRAL_GRAY: Color = Color(0.55, 0.55, 0.58)    # #8C8C94

## Market price color scheme — parameterizable for DLC markets.
## KRX default: price up = red, price down = blue.
## Call set_market_colors() at market initialization to override.
static var PRICE_UP: Color = PROFIT_RED
static var PRICE_DOWN: Color = LOSS_BLUE

static func set_market_colors(up: Color, down: Color) -> void:
	PRICE_UP = up
	PRICE_DOWN = down

const BTN_NORMAL: Color = Color(0.88, 0.88, 0.91)      # #E0E0E8 visible gray
const BTN_HOVER: Color = Color(0.82, 0.82, 0.86)       # #D1D1DB
const BTN_PRESSED: Color = Color(0.76, 0.76, 0.80)     # #C2C2CC
const BTN_BUY: Color = Color(0.92, 0.22, 0.20)         # #EB3833 red solid
const BTN_BUY_HOVER: Color = Color(0.82, 0.18, 0.16)   # #D12E29 darker red
const BTN_SELL: Color = Color(0.18, 0.42, 0.90)         # #2E6BE6 blue solid
const BTN_SELL_HOVER: Color = Color(0.14, 0.35, 0.78)   # #2459C7 darker blue
const BTN_ACCENT: Color = Color(0.20, 0.20, 0.22)       # #333338 dark accent
const BTN_ACCENT_HOVER: Color = Color(0.30, 0.30, 0.33) # #4D4D54

const SEPARATOR: Color = Color(0.92, 0.92, 0.93)        # #EBEBEE

# Dark layout — main frame background and tab bar (HTS-style dark chrome).
# Content panels use the white-base palette above; only the outer frame is dark.
const LAYOUT_BG: Color = Color(0.08, 0.08, 0.09)            # #141416 page frame
const LAYOUT_PANEL: Color = Color(0.12, 0.12, 0.13)          # #1F1F21 tab bar / inactive
const LAYOUT_TAB_ACTIVE_BG: Color = Color(0.18, 0.18, 0.20)  # #2E2E33 active tab bg
const LAYOUT_TAB_BORDER: Color = Color(0.3, 0.6, 1.0)        # #4D99FF active tab underline
const LAYOUT_EXIT_HOVER_BG: Color = Color(0.22, 0.12, 0.12)  # #381F1F exit button danger hover
const LAYOUT_TAB_TEXT: Color = Color(0.7, 0.7, 0.7)          # #B3B3B3 inactive tab label
const LAYOUT_EXIT_TEXT: Color = Color(0.55, 0.55, 0.55)       # #8C8C8C exit button normal text
const LAYOUT_EXIT_TEXT_HOVER: Color = Color(0.85, 0.5, 0.5)   # #D98080 exit button hover text

# Tab button states — active tab uses dark accent, inactive uses default
const TAB_ACTIVE_BG: Color = Color(0.20, 0.20, 0.22)    # #333338 same as BTN_ACCENT
const TAB_ACTIVE_HOVER: Color = Color(0.30, 0.30, 0.33)  # #4D4D54
const TAB_INACTIVE_BG: Color = Color(0.94, 0.94, 0.95)   # #F0F0F2 subtle
const TAB_INACTIVE_HOVER: Color = Color(0.90, 0.90, 0.92) # #E6E6EB

# Alert severity backgrounds — subtle tints on white base
const ALERT_BG_MEGA: Color = Color(0.98, 0.94, 0.94)     # soft red tint
const ALERT_BG_LARGE: Color = Color(0.98, 0.96, 0.92)    # soft warm tint
const ALERT_BORDER_MEGA: Color = Color(0.92, 0.22, 0.20)  # PROFIT_RED
const ALERT_BORDER_LARGE: Color = Color(0.85, 0.55, 0.05) # orange/amber

# ── Factory Methods ──

static func make_panel_style(bg: Color = BG_PANEL, radius: int = 8, border: Color = BORDER_DIM, border_width: int = 0) -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.border_color = border
	s.set_border_width_all(border_width)
	s.set_content_margin_all(8)
	return s


static func make_button_style(bg: Color = BTN_NORMAL, radius: int = 8) -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.border_color = Color.TRANSPARENT
	s.set_border_width_all(0)
	s.set_content_margin_all(8)
	return s


static func apply_button_theme(btn: Button, normal_bg: Color = BTN_NORMAL, hover_bg: Color = BTN_HOVER, pressed_bg: Color = BTN_PRESSED) -> void:
	btn.add_theme_stylebox_override("normal", make_button_style(normal_bg))
	btn.add_theme_stylebox_override("hover", make_button_style(hover_bg))
	btn.add_theme_stylebox_override("pressed", make_button_style(pressed_bg))
	btn.add_theme_stylebox_override("focus", make_button_style(normal_bg))
	btn.add_theme_color_override("font_color", TEXT_PRIMARY)
	btn.add_theme_color_override("font_hover_color", TEXT_PRIMARY)
	btn.add_theme_color_override("font_pressed_color", TEXT_SECONDARY)


static func apply_accent_button(btn: Button) -> void:
	apply_button_theme(btn, BTN_ACCENT, BTN_ACCENT_HOVER, BTN_PRESSED)
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)


static func apply_buy_button(btn: Button) -> void:
	apply_button_theme(btn, BTN_BUY, BTN_BUY_HOVER, BTN_PRESSED)
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)


static func apply_sell_button(btn: Button) -> void:
	apply_button_theme(btn, BTN_SELL, BTN_SELL_HOVER, BTN_PRESSED)
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)


## Style a tab button as active (selected) — dark bg, white text.
static func apply_tab_active(btn: Button) -> void:
	apply_button_theme(btn, TAB_ACTIVE_BG, TAB_ACTIVE_HOVER, BTN_PRESSED)
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color(0.85, 0.85, 0.88))


## Style a tab button as inactive — subtle bg, dark text.
static func apply_tab_inactive(btn: Button) -> void:
	apply_button_theme(btn, TAB_INACTIVE_BG, TAB_INACTIVE_HOVER, BTN_PRESSED)
	btn.add_theme_color_override("font_color", TEXT_SECONDARY)
	btn.add_theme_color_override("font_hover_color", TEXT_PRIMARY)
	btn.add_theme_color_override("font_pressed_color", TEXT_PRIMARY)


static func style_label_primary(lbl: Label) -> void:
	lbl.add_theme_color_override("font_color", TEXT_PRIMARY)


static func style_label_secondary(lbl: Label) -> void:
	lbl.add_theme_color_override("font_color", TEXT_SECONDARY)


static func style_label_dim(lbl: Label) -> void:
	lbl.add_theme_color_override("font_color", TEXT_DIM)


## Apply global base theme so all controls default to dark text on light bg.
## Call once from the main scene's _ready().
static func apply_base_theme(tree: SceneTree) -> void:
	var theme: Theme = Theme.new()

	# Font colors — every control type that can display text
	var text_types: Array[String] = [
		"Label", "Button", "LineEdit", "RichTextLabel",
		"CheckBox", "CheckButton", "OptionButton", "MenuButton",
		"SpinBox", "TextEdit", "ItemList", "Tree", "TabBar",
	]
	for type_name: String in text_types:
		theme.set_color("font_color", type_name, TEXT_PRIMARY)

	# Button states
	theme.set_color("font_hover_color", "Button", TEXT_PRIMARY)
	theme.set_color("font_pressed_color", "Button", TEXT_SECONDARY)
	theme.set_color("font_disabled_color", "Button", TEXT_DIM)

	# LineEdit specifics
	theme.set_color("font_placeholder_color", "LineEdit", TEXT_DIM)
	theme.set_color("caret_color", "LineEdit", TEXT_PRIMARY)
	theme.set_color("selection_color", "LineEdit", BG_SELECTED)

	# LineEdit — light input field with subtle border
	theme.set_stylebox("normal", "LineEdit", _make_input_style(BG_DARKEST, BORDER_DIM))
	theme.set_stylebox("focus", "LineEdit", _make_input_style(Color.WHITE, BORDER_BRIGHT))
	theme.set_stylebox("read_only", "LineEdit", _make_input_style(BG_HOVER, BORDER_DIM))

	# Button — light background, no border
	theme.set_stylebox("normal", "Button", make_button_style(BTN_NORMAL))
	theme.set_stylebox("hover", "Button", make_button_style(BTN_HOVER))
	theme.set_stylebox("pressed", "Button", make_button_style(BTN_PRESSED))
	theme.set_stylebox("focus", "Button", make_button_style(BTN_NORMAL))

	# Panel backgrounds
	theme.set_stylebox("panel", "PanelContainer", make_panel_style(BG_PANEL, 8, Color.TRANSPARENT, 0))
	theme.set_stylebox("panel", "Panel", make_panel_style(BG_DARKEST, 0, Color.TRANSPARENT, 0))

	# Separator
	theme.set_color("separator", "HSeparator", SEPARATOR)
	theme.set_color("separator", "VSeparator", SEPARATOR)

	tree.root.theme = theme

	# Fallback color — catches ANY control not matched by the theme above
	ThemeDB.fallback_base_scale = 1.0


static func _make_input_style(bg: Color, border: Color) -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(6)
	s.border_color = border
	s.set_border_width_all(1)
	s.set_content_margin_all(6)
	return s


## Style a SpinBox to match the white-base theme.
static func apply_spinbox_theme(spin: SpinBox) -> void:
	var line_edit: LineEdit = spin.get_line_edit()
	line_edit.add_theme_stylebox_override("normal", _make_input_style(BG_DARKEST, BORDER_DIM))
	line_edit.add_theme_stylebox_override("focus", _make_input_style(Color.WHITE, BORDER_BRIGHT))
	line_edit.add_theme_color_override("font_color", TEXT_PRIMARY)
	line_edit.add_theme_color_override("caret_color", TEXT_PRIMARY)



## Accessibility: returns true if the "reduce motion" setting is enabled.
## Single source for all UI animations. Callers skip Tween/animation when true.
## See: ProjectSettings > accessibility/reduced_motion (TD-07).
static func is_reduced_motion() -> bool:
	return ProjectSettings.get_setting("accessibility/reduced_motion", false)
