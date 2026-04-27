extends GutTest
## IntroSequence 유닛 테스트 — GDD intro-sequence.md AC-06, AC-07
## 정적 메서드(has_been_seen, clear_seen_flag)와 상수만 테스트.
## UI 노드 생성 없이 순수 로직만 검증.

## preload: class_name 글로벌 등록이 GUT 헤드리스에서 지연될 수 있어 명시적 로드.
const IntroSequence = preload("res://src/ui/intro_sequence.gd")

const SEEN_FLAG_PATH: String = "user://intro_seen.flag"


func before_each() -> void:
	_remove_flag()


func after_each() -> void:
	_remove_flag()


func _remove_flag() -> void:
	if FileAccess.file_exists(SEEN_FLAG_PATH):
		var da := DirAccess.open("user://")
		if da:
			da.remove("intro_seen.flag")


# ── AC-06: has_been_seen() ──

func test_has_been_seen_returns_false_when_flag_absent() -> void:
	# Arrange: before_each에서 플래그 제거됨
	# Act + Assert
	assert_false(IntroSequence.has_been_seen(),
		"플래그 파일 없을 때 has_been_seen()은 false여야 함")


func test_has_been_seen_returns_true_when_flag_present() -> void:
	# Arrange
	var f := FileAccess.open(SEEN_FLAG_PATH, FileAccess.WRITE)
	f.store_string("1")
	f.close()

	# Act + Assert
	assert_true(IntroSequence.has_been_seen(),
		"플래그 파일 있을 때 has_been_seen()은 true여야 함")


# ── AC-07: clear_seen_flag() ──

func test_clear_seen_flag_removes_existing_flag() -> void:
	# Arrange
	var f := FileAccess.open(SEEN_FLAG_PATH, FileAccess.WRITE)
	f.store_string("1")
	f.close()

	# Act
	IntroSequence.clear_seen_flag()

	# Assert
	assert_false(IntroSequence.has_been_seen(),
		"clear_seen_flag() 후 has_been_seen()은 false여야 함")


func test_clear_seen_flag_no_error_when_flag_absent() -> void:
	# Arrange: 플래그 없음 (before_each 처리)
	assert_false(FileAccess.file_exists(SEEN_FLAG_PATH))

	# Act: 플래그 없는 상태에서 호출 — 오류 없이 완료되어야 함 (EC-02)
	IntroSequence.clear_seen_flag()

	# Assert: 여기까지 왔으면 통과
	assert_false(IntroSequence.has_been_seen())


# ── 상수 검증 ──

func test_card_texts_count_is_five() -> void:
	assert_eq(IntroSequence._build_card_texts().size(), 5,
		"카드는 정확히 5장이어야 함")


func test_card_texts_none_empty() -> void:
	var texts: Array[String] = IntroSequence._build_card_texts()
	for i: int in range(texts.size()):
		assert_ne(texts[i], "",
			"카드 %d 텍스트가 비어있음" % i)


func test_typewriter_speed_is_positive() -> void:
	# EC-05: TYPEWRITER_SPEED는 반드시 양수
	assert_gt(IntroSequence.TYPEWRITER_SPEED, 0.0,
		"TYPEWRITER_SPEED는 양수여야 함")


func test_card_fade_duration_is_positive() -> void:
	assert_gt(IntroSequence.CARD_FADE_DURATION, 0.0,
		"CARD_FADE_DURATION은 양수여야 함")


func test_finish_fade_duration_is_positive() -> void:
	assert_gt(IntroSequence.FINISH_FADE_DURATION, 0.0,
		"FINISH_FADE_DURATION은 양수여야 함")
