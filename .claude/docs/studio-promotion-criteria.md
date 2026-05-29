# Studio Promotion Criteria

이 템플릿은 살아있는 스튜디오 자산이다. 각 프로젝트에서 얻은 skill·규칙·메모리·agent
수정 중 **스튜디오 전체에 가치가 있는 것만** 골라 템플릿으로 역전파한다. 무차별 흡수는
템플릿을 한두 프로젝트의 특수성으로 오염시키므로, 모든 변경은 아래 게이트를 통과해야
한다.

이 문서는 `/studio-promote` skill의 판단 기준이며, Director Group(특히 producer +
technical-director)의 승인 기준이기도 하다.

---

## 1. Promotable Source Types

다음 자산만 승격 후보가 될 수 있다. 그 외(소스 코드, GDD, ADR, 프로덕션 산출물)는
프로젝트 자산이지 템플릿 자산이 아니다.

| Type | Project Location | Template Target |
|------|------------------|-----------------|
| Auto-memory 항목 | `~/.claude/projects/<project>/memory/*.md` | `.claude/studio-memory/` (신규 디렉토리) |
| 신규 skill | `.claude/skills/<name>/SKILL.md` | 동일 경로 |
| 신규 규칙/표준 | `.claude/docs/*.md` diff | 동일 경로 |
| Agent 수정 | `.claude/agents/*.md` diff | 동일 경로 |
| Hook | `.claude/hooks/*.{sh,ps1}` diff | 동일 경로 |
| `CLAUDE.md` 추가 행 | 프로젝트 `CLAUDE.md` diff | 템플릿 `CLAUDE.md` |

> **참고**: 프로젝트에서 검증 전 자산을 자유롭게 실험할 수 있는 영역은
> `.claude/local/` (gitignore 처리)다. 여기 있는 것은 승격 대상이 아니며, 사용자가
> 명시적으로 정식 경로로 옮긴 자산만 후보가 된다.

---

## 2. Promotion Gates (G1 ~ G6)

전 게이트 PASS 또는 명시적 면제(waiver) 시에만 승격된다. UNCLEAR 1개라도 있으면
DEFER, FAIL 1개라도 있으면 REJECT.

### G1 — Generality (일반성)
**기준**: 특정 엔진 버전·장르·팀 구성·IP에 비종속이어야 한다.

- ❌ "Godot 4.6.2의 Jolt 회피 패턴" → 엔진별 docs로 분기, 템플릿 본체 불가
- ❌ "Seed Money 프로젝트의 종목 표시 포맷" → 프로젝트 잔류
- ✅ "ADR 작성 시 alternatives 섹션 필수" → 일반 원칙

엔진별/장르별이지만 유용한 자산은 별도 디렉토리(`.claude/docs/engine-specific/`,
`.claude/docs/genre-specific/`)로 격리하여 승격할 수 있다. 본체 오염은 막되 유실은
방지한다.

### G2 — Validation (검증, **waivable**)
**기본 기준**: 2개 이상 프로젝트에서 동일하게 유용했음.

**면제 조건**: Director Group(최소 producer + technical-director) 합의로 면제 가능.
면제 시 제안서 G2 칸에 사유 명시 필수.

- 단일 프로젝트 검증인데 producer + technical-director가 일반성을 인정 → 면제 가능
- 면제 표기: `G2⚠️ (waived: <사유>)`
- 면제된 항목은 다음 프로젝트 회고에서 우선 재검증 대상으로 등재

### G3 — Non-Conflict (비충돌)
**기준**: 기존 템플릿 규칙·skill·agent 정의와 명시적으로 모순되지 않아야 한다.

- 충돌하는 항목이 있으면 둘 중 하나를 폐기·상위 규칙으로 통합해야 함
- 충돌을 그대로 두고 승격 불가
- 의도적 대체인 경우 → 기존 규칙을 Superseded로 표기하는 ADR을 동반 PR로 등록

### G4 — Non-Duplication (비중복)
**기준**: 기존 skill·docs로 이미 커버되는 영역이 아니어야 한다.

- 기존 skill의 한 phase로 흡수 가능 → 그쪽으로 통합 PR (신규 skill 승격 불가)
- 기존 문서에 한 섹션 추가로 충분 → 문서 patch로 승격
- 진짜로 새 도메인일 때만 신규 skill·문서로 승격

### G5 — Stability (안정성)
**기준**: 출처 프로젝트에서 최소 1개월간 수정 없이 사용되었음.

- 빠르게 변하는 자산은 아직 형태가 굳지 않은 것 → 템플릿 오염 위험
- 1개월 미만이지만 사용자가 안정성을 확신하면 → G2처럼 Director Group 면제 가능
- 면제 표기: `G5⚠️ (waived: <사유>)`

### G6 — Maintenance Cost (유지비용)
**기준**: 향후 유지 부담이 그 가치보다 작다는 명시적 판단.

- skill의 경우: 의존하는 외부 도구·인덱스가 많을수록 비용 증가
- 문서의 경우: 자주 갱신해야 하는 표·통계가 포함되면 비용 증가
- 자동화 가능한 부분이 있는지 검토하고, 없으면 유지 책임자 명시 (`Owner: producer` 등)

---

## 3. Anti-Promotion Signals (즉시 REJECT)

다음 패턴이 후보 안에 발견되면 게이트 결과와 무관하게 REJECT한다. `/studio-promote`는
정규식/키워드로 자동 매칭한다.

| Signal | 예시 |
|--------|------|
| 특정 IP·캐릭터·내러티브 이름 | "Sera의 대사 스타일", "Project Lumen의 경제" |
| 특정 개발자 개인 선호 | "Tone: dry humor preferred (joywoni)" |
| 특정 엔진 버전 픽스 | "Godot 4.6.2 한정 버그 회피" |
| 단일 버그용 일회성 워크어라운드 | "Issue #142 임시 가드" |
| `type: user` Auto-memory 전체 | 사용자 개인 프로파일 |
| 비공개·민감 정보 | 라이선스 키, 내부 URL, 미공개 사양 |
| 외부 의존 (계정·서비스) | 특정 Slack 워크스페이스, 특정 Linear 프로젝트 ID |

Auto-memory 중 `type: feedback` / `type: project` / `type: reference`는 후보가 될 수
있으나 위 신호가 포함되면 REJECT한다. 일부 라인만 문제이면 redaction 후 재제출 가능.

---

## 4. Process

### 4.1 Trigger (언제 실행하나)

- 프로젝트 **마일스톤 종료 시** (강제)
- 분기별 1회 (강제)
- 사용자 임의 시점 (선택)

마일스톤 종료 시 누락은 producer가 `/milestone-review`에서 체크하고 보고한다.

### 4.2 Execution

1. 프로젝트 repo에서 `/studio-promote` 실행
2. 후보 자동 수집 → 게이트 평가 → 분류(PROMOTE/DEFER/REJECT)
3. DEFER 항목은 사용자와 대화로 판정
4. `docs/studio-promotion-proposal-YYYY-MM-DD.md` 생성

### 4.3 Review

Director Group이 제안서를 검토한다. 최소 서명:

- **PROMOTE 항목 일반**: producer + 해당 도메인 director (예: skill→lead-programmer)
- **G2 면제 항목**: producer + technical-director 추가 서명 필수
- **G3 충돌 해소 동반 ADR**: technical-director 서명 필수

### 4.4 Apply

두 경로 중 택일:

- **수동**: 사용자가 스튜디오 템플릿 repo에서 제안서를 보고 직접 반영 후 PR
- **자동**: `/studio-promote --apply <studio-template-path>`로 PROMOTE 항목만 자동
  적용. 사전 조건: 로컬 클론 존재, `gh auth status` 통과, 워킹 트리 클린

머지 후:
- 출처 프로젝트 명시: 템플릿 repo `CHANGELOG.md`에 "Promoted from <project> on <date>" 기록
- 검증 ledger 갱신: `.claude/studio-memory/promotion-ledger.yaml`에 해당 항목 등록
  (어느 프로젝트에서 검증되었는지 추적 — G2 자동화의 기반)

---

## 5. Storage Layout

```
스튜디오 템플릿 repo (이 repo):
  .claude/
    skills/                      # 정식 skill (승격된 것만)
    docs/                        # 정식 규칙/표준
    agents/                      # 정식 agent 정의
    hooks/                       # 정식 hook
    studio-memory/               # 승격된 메모리 항목 (신규)
      promotion-ledger.yaml      # 검증 ledger (어느 프로젝트에서 통과됐는지)
      <category>/<item>.md       # 카테고리별 메모리

프로젝트 repo:
  .claude/
    local/                       # gitignore. 실험 영역. 승격 후보 아님.
    skills/                      # 템플릿 상속분 + 프로젝트 추가분
    docs/                        # 템플릿 상속분 + 프로젝트 추가분
  docs/
    studio-promotion-proposal-YYYY-MM-DD.md   # /studio-promote 출력
```

`.claude/studio-memory/`는 본 PR 시점에는 존재하지 않을 수 있다. 최초 승격 시
`/studio-promote --apply`가 디렉토리 생성을 포함한다.

---

## 6. Decision Quick-Reference

```
후보 → Anti-promotion signal 검사
  └─ 매칭 → REJECT (끝)
  └─ 통과 → G1 ~ G6 평가
       └─ 전 게이트 PASS (또는 명시적 waiver) → PROMOTE
       └─ UNCLEAR 1개 이상 → DEFER (대화로 해소)
       └─ FAIL 1개 이상 → REJECT
```

---

## 7. Maintenance

- 이 문서 자체의 변경은 ADR을 요구한다 (게이트가 곧 거버넌스이므로)
- 게이트 추가·제거는 technical-director + producer 공동 서명
- 분기별 회고에서 "현재 게이트가 실제 판단을 잘 반영하는가" 검토 권장
