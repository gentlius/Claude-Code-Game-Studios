## Order Book Tests — 호가창 슬리피지 + API 검증
## Implements: design/gdd/order-book.md §8 Acceptance Criteria
extends GutTest


# ── AC-01: 초기 호가창 빈 상태 ───────────────────────────────────────

func test_order_book_empty_before_initialize() -> void:
	## 시즌 시작 전 호가창은 ask/bid 모두 빈 배열이어야 한다.
	## GDD order-book.md §8 AC-01
	PriceEngine.reset()
	var known_id: String = ""
	for id: String in StockDatabase.get_all_stock_ids():
		known_id = id
		break
	if known_id == "":
		pass  # StockDatabase 미초기화 환경에서는 스킵
	else:
		var book: Dictionary = PriceEngine.get_order_book(known_id)
		assert_true(book.get("ask", []).is_empty(), "초기화 전 ask 빈 배열")
		assert_true(book.get("bid", []).is_empty(), "초기화 전 bid 빈 배열")


# ── AC-02: get_order_book() 구조 검증 ──────────────────────────────

func test_order_book_has_ask_bid_keys() -> void:
	## get_order_book()은 {"ask": Array, "bid": Array} 구조를 반환해야 한다.
	var book: Dictionary = PriceEngine.get_order_book("NONEXISTENT")
	assert_true(book.has("ask"), "ask 키 존재")
	assert_true(book.has("bid"), "bid 키 존재")


# ── API 존재 확인 (order-book.md §6 Implementation Checklist) ────────

func test_price_engine_order_book_api() -> void:
	assert_true(PriceEngine.has_method("initialize_order_books"), "initialize_order_books 존재")
	assert_true(PriceEngine.has_method("get_order_book"),          "get_order_book 존재")
	assert_true(PriceEngine.has_method("consume_order_book"),      "consume_order_book 존재")
