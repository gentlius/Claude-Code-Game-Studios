> **Status**: Draft
> **Sprint**: S7-09
> **Owner**: audio-director

# 오디오 플랜 — 시드머니 (Seed Money)

## 오디오 방향

**콘셉트**: "집중과 긴장의 트레이딩 룸"  
화려한 게임 BGM 아닌 실제 트레이딩 환경의 긴장감. 전자음 기반 미니멀.
플레이어가 수치에 집중할 수 있도록 배경음은 존재감을 낮게 유지.

---

## BGM — 시장 상태별 테마

### PRE_MARKET (장 전)

- **분위기**: 차분한 대기, 집중 준비
- **장르**: 로우파이 일렉트로닉 앰비언스
- **BPM**: 70~80
- **악기**: 신시사이저 패드, 가벼운 하이햇, 베이스라인 없음
- **참고**: 아침 거래소 개장 전 정적

### MARKET_OPEN (장 중)

- **분위기**: 집중, 리듬감, 긴장 유지
- **장르**: 미니멀 테크노 / 일렉트로닉
- **BPM**: 110~125
- **악기**: 클릭 퍼커션, 신스 리드, 반복 아르페지오, 낮은 베이스 펄스
- **참고**: Toss 앱 거래 화면의 에너지감. 과하지 않게.

### PAUSED (일시정지)

- **처리**: MARKET_OPEN BGM에 로우패스 필터 적용 + 볼륨 -6dB
- **별도 트랙 불필요**: AudioStreamPlayer pitch_scale 또는 AudioEffectLowPassFilter

### MARKET_CLOSED (장 마감)

- **분위기**: 하루 마무리, 성찰, 결산
- **장르**: 앰비언트 / 다운템포
- **BPM**: 80~90
- **악기**: 피아노 또는 신스 패드, 느린 리버브, 퍼커션 없음
- **참고**: EOD 리포트를 읽는 차분한 느낌

---

## SFX 완성 현황

`assets/audio/DOWNLOAD_GUIDE.md` 참조.

| ID | 파일 | 상태 |
|----|------|------|
| S-01 | `bgm_start_screen.ogg` | ✅ 완료 |
| S-02 | `sfx_logo_sting.ogg` | ✅ 완료 |
| S-03 | `sfx_save_complete.ogg` | ✅ 완료 |
| S-04 | `sfx_slot_select.ogg` | ✅ 완료 |
| S-05 | `sfx_slot_hover.ogg` | ✅ 완료 |
| S-06 | `sfx_delete_confirm.ogg` | ✅ 완료 |
| S-07 | `sfx_profit_small.wav` | ✅ 완료 (자체 생성) |
| S-08 | `sfx_profit_medium.wav` | ✅ 완료 (자체 생성) |
| S-09 | `sfx_profit_large.wav` | ✅ 완료 (자체 생성) |
| S-10 | `sfx_profit_jackpot.wav` | ✅ 완료 (자체 생성) |
| S-11 | `sfx_order_filled.wav` | ✅ 완료 (자체 생성) |
| S-12 | `sfx_level_up.wav` | ✅ 완료 (자체 생성) |
| S-13 | `sfx_vi_alert.wav` | ✅ 완료 (자체 생성) |
| S-14 | `sfx_news_alert.wav` | ✅ 완료 (자체 생성) |

---

## 믹싱 가이드

| 카테고리 | 볼륨 기준 | 비고 |
|---------|---------|------|
| BGM | -12dB (마스터 대비) | 배경이므로 낮게 |
| SFX 일반 | -6dB | 체결음, 알림 |
| SFX 경보 | -3dB | VI 경보 — 가장 크게 |
| SFX 수익 | -6 ~ -3dB | 잭팟은 -3dB |

- BGM ↔ SFX 버스 분리 (`AudioServer`)
- 플레이어 볼륨 설정: BGM / SFX 독립 조절 (설정 화면 구현 시)

---

## 미구현 (폴리시 단계)

- 시장 상태별 BGM 트랙 (S7에서 방향만 확정, 실제 트랙은 Beta 후반)
- BGM 페이드 전환 (MARKET_OPEN ↔ PRE_MARKET 크로스페이드)
- 동적 음악 레이어링 (수익률에 따라 BGM 강도 변화) — 고려 중
