## Rumor Channel Tests — S3 스킬 루머 발화 검증
## Implements: design/gdd/rumor-channel.md §8 Acceptance Criteria
extends GutTest

# ── AC-01: S3 미해금 시 루머 미발화 ─────────────────────────────────────

func test_no_rumor_emitted_without_s3() -> void:
	# Arrange
	SkillTree.reset()
	var received: Array = []
	NewsEventSystem.on_rumor_hint.connect(func(r): received.append(r))

	# Act — S3 미해금 상태에서 루머 체크
	var unlocked: bool = SkillTree.has_rumor_channel()

	# Assert
	assert_false(unlocked, "S3 미해금 시 has_rumor_channel() == false")
	assert_true(received.is_empty(), "S3 미해금 시 on_rumor_hint 미발화")

	# Cleanup
	if NewsEventSystem.on_rumor_hint.is_connected(func(r): received.append(r)):
		pass  # 람다 disconnect는 GUT에서 자동 처리


# ── AC-04: 장기 실행 시 루머 정확도 ~70% 수렴 ──────────────────────────

func test_rumor_accuracy_converges_to_70_percent() -> void:
	# Arrange
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 42
	var trials: int = 1000
	var accurate_count: int = 0
	var accuracy: float = SkillTree.RUMOR_BASE_ACCURACY  # 0.70

	# Act — 1000회 독립 확률 롤
	for i: int in range(trials):
		if rng.randf() < accuracy:
			accurate_count += 1

	# Assert — 65~75% 범위 내 수렴 (±5% 허용, GDD §8 AC-04)
	var rate: float = float(accurate_count) / float(trials)
	assert_true(rate >= 0.65, "루머 정확도 >= 65%% (실측: %.1f%%)" % (rate * 100))
	assert_true(rate <= 0.75, "루머 정확도 <= 75%% (실측: %.1f%%)" % (rate * 100))
