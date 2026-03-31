## Data structure for a market event pushed from News/Events system to PriceEngine.
class_name MarketEvent
extends RefCounted

enum EventType { INSTANT_SHOCK, GRADUAL_SHIFT }
enum EventScope { MACRO, SECTOR, INDIVIDUAL }
enum DecayCurve { LINEAR, EXPONENTIAL }

var event_type: EventType
var base_impact: float          ## 0.01~0.20
var direction: int              ## +1 (good news) or -1 (bad news)
var scope: EventScope
var target_stock_ids: Array[String]
var decay_ticks: int = 0        ## GRADUAL_SHIFT duration
var decay_curve: DecayCurve = DecayCurve.LINEAR


static func instant_shock(
	impact: float, dir: int, sc: EventScope, targets: Array[String]
) -> MarketEvent:
	var evt := MarketEvent.new()
	evt.event_type = EventType.INSTANT_SHOCK
	evt.base_impact = impact
	evt.direction = dir
	evt.scope = sc
	evt.target_stock_ids = targets
	return evt


static func gradual_shift(
	impact: float, dir: int, sc: EventScope, targets: Array[String],
	ticks: int, curve: DecayCurve = DecayCurve.LINEAR
) -> MarketEvent:
	var evt := MarketEvent.new()
	evt.event_type = EventType.GRADUAL_SHIFT
	evt.base_impact = impact
	evt.direction = dir
	evt.scope = sc
	evt.target_stock_ids = targets
	evt.decay_ticks = ticks
	evt.decay_curve = curve
	return evt
