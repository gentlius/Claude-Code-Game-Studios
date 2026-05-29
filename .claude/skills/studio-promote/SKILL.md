---
name: studio-promote
description: "Identifies project-local assets (skills, rules, memories, agents, hooks, CLAUDE.md additions) that diverged from the studio template, scores them against the studio promotion gates (G1-G6 + anti-promotion signals), and generates a dated promotion proposal. Optionally applies PROMOTE-classified items to a local studio template clone and opens a PR. Run at milestone end or quarterly. Defined by `.claude/docs/studio-promotion-criteria.md`."
argument-hint: "[scope: full | memory | skills | rules | agents | hooks] [--apply <studio-template-path>]"
user-invocable: true
allowed-tools: Read, Glob, Grep, Write, Edit, Bash, AskUserQuestion
model: sonnet
agent: producer
---

# Studio Promote — Project → Template Promotion

이 skill은 프로젝트에서 누적된 자산 중 **스튜디오 템플릿으로 역전파할 가치가 있는
것**을 식별하고, `.claude/docs/studio-promotion-criteria.md`의 G1~G6 게이트로 분류하여
검토 가능한 제안서로 만든다.

**입력**: 현재 디렉토리(프로젝트 repo)
**기준**: `.claude/docs/studio-promotion-criteria.md`
**출력**: `docs/studio-promotion-proposal-YYYY-MM-DD.md`
**선택적 사이드 이펙트**: `--apply <path>` 지정 시 스튜디오 템플릿 로컬 클론에 PR 브랜치 생성

이 skill은 **결정하지 않는다.** 분류·근거·diff를 제시하고, 최종 승인은 Director Group
(또는 사용자)이 수행한다.

---

## Phase 0: Detect Mode

먼저 한 줄 알림: `"Detecting promotion source..."`

### 0.1 현재 repo 판별

`.claude/docs/technical-preferences.md`의 Engine 필드를 읽는다. 이 필드는
업스트림 템플릿에서 `[TO BE CONFIGURED — run /setup-engine]` placeholder로 시작하며,
프로젝트에서 `/setup-engine` 실행 시 실제 엔진명(예: `Godot 4.6.2`)으로 채워진다.

Grep 패턴:
```
Grep pattern="^- \*\*Engine\*\*:" path=".claude/docs/technical-preferences.md"
```

- 매칭된 값이 `[TO BE CONFIGURED` 또는 `[CHOOSE:` 또는 `[SPECIFY`로 시작 → **이 repo는 스튜디오 템플릿**
  → 사용자에게 보고: "이 repo는 스튜디오 템플릿입니다 (Engine 미설정 상태). `/studio-promote`는
  `/setup-engine`이 실행된 프로젝트 repo에서 실행해야 합니다." → 종료
- 매칭된 값이 실제 엔진명으로 채워짐 → **프로젝트로 간주**, 진행
- 파일이 없거나 Engine 필드 라인이 없음 → 사용자에게 확인 질문 후 진행/종료 결정

> **변경 기록**: 이전에는 `CLAUDE.md` 첫 줄로 판별했으나, 템플릿과 프로젝트 모두 동일한
> 헤더를 유지하므로 신뢰할 수 없었다. Engine 필드 상태는 `/setup-engine`이 실행됐는지의
> 단일 권위 신호이므로 더 정확하다.

### 0.2 비교 기준(upstream) 결정

`git remote -v`로 upstream을 찾는다.

- 기본 우선순위: `upstream` → `studio-template` → `origin` (이름 기준)
- 어느 것도 스튜디오 템플릿이 아니면 `AskUserQuestion`으로 사용자에게 묻는다:
  "스튜디오 템플릿 git URL을 입력하거나, 로컬 경로를 알려주세요."
- 결정된 upstream을 `STUDIO_UPSTREAM` 변수에 저장 (이 세션 한정)

### 0.3 인자 파싱

`$ARGUMENTS`에서:
- 첫 번째 위치 인자: scope (기본 `full`)
- `--apply <path>`: 자동 PR 모드 활성화. `<path>`는 스튜디오 템플릿 로컬 클론 경로

scope 유효값: `full`, `memory`, `skills`, `rules`, `agents`, `hooks`. 그 외는 종료.

---

## Phase 1: Enumerate Candidates

scope에 따라 후보를 수집한다. 각 후보는 다음 구조로 메모리에 보관한다:

```
{
  id: <고유 식별자>,
  type: memory | skill | rule | agent | hook | claudemd,
  source_path: <프로젝트 내 경로>,
  target_path: <템플릿 내 예상 경로>,
  content: <전체 또는 diff>,
  metadata: { ... }
}
```

### 1.1 Memory 후보 (scope ∈ {full, memory})

- 경로: `~/.claude/projects/<현재-프로젝트-경로>/memory/MEMORY.md`
  - Windows에서는 `C:\Users\<user>\.claude\projects\<sanitized-path>\memory\MEMORY.md`
  - 경로 sanitize 규칙: `/`와 `\`를 `-`로, `:`을 `-`로 (실제 경로 존재 여부로 검증)
- `MEMORY.md` 라인 파싱 → 각 항목의 메모리 파일 read
- 메모리 파일의 frontmatter `type`이 `user`이면 자동 제외 (anti-signal #5)
- 나머지(`feedback`, `project`, `reference`)는 후보 등록

### 1.2 Skill 후보 (scope ∈ {full, skills})

```bash
git diff $STUDIO_UPSTREAM/main...HEAD -- .claude/skills/ --name-status
```

- `A`(추가) 또는 `M`(수정)인 SKILL.md 식별
- 각 skill 디렉토리 전체를 후보로 등록 (SKILL.md + 보조 파일)

### 1.3 Rule 후보 (scope ∈ {full, rules})

```bash
git diff $STUDIO_UPSTREAM/main...HEAD -- .claude/docs/ --name-status
```

- `A` → 신규 문서 전체가 후보
- `M` → diff hunk 단위로 후보 분리 (한 문서에서 일부 섹션만 일반화될 수 있음)

### 1.4 Agent 후보 (scope ∈ {full, agents})

```bash
git diff $STUDIO_UPSTREAM/main...HEAD -- .claude/agents/ --name-status
```

같은 방식으로 처리.

### 1.5 Hook 후보 (scope ∈ {full, hooks})

```bash
git diff $STUDIO_UPSTREAM/main...HEAD -- .claude/hooks/ --name-status
```

같은 방식으로 처리.

### 1.6 CLAUDE.md 추가 행 (scope ∈ {full, rules})

```bash
git diff $STUDIO_UPSTREAM/main...HEAD -- CLAUDE.md
```

- `+` 라인만 추출하여 hunk별로 후보 등록

후보가 0건이면 사용자에게 "승격 대상 변경사항이 없습니다." 보고 후 종료.

---

## Phase 2: Apply Anti-Promotion Signals

각 후보의 content에 대해 다음 패턴을 검사한다. 매칭 시 후보를 **REJECT**로 즉시 마킹하고
G1~G6 평가에서 제외한다.

| Signal ID | 검사 방법 |
|-----------|-----------|
| AS-1 IP/캐릭터/내러티브 | `design/gdd/*.md`에서 추출한 고유명사 사전 + 후보 content 매칭 |
| AS-2 개인 선호 | 정규식 `\((joywoni\|<git user.name>)\)`, `(personal preference)` |
| AS-3 엔진 버전 픽스 | 정규식 `(Godot\|Unity\|Unreal)\s*\d+\.\d+\.\d+` + 주변 50자에 "fix\|workaround\|bug\|회피" |
| AS-4 일회성 워크어라운드 | 정규식 `Issue\s*#\d+`, `temporary`, `임시 가드` |
| AS-5 type:user 메모리 | frontmatter `type: user` (Phase 1.1에서 이미 제외했지만 재검증) |
| AS-6 민감 정보 | 정규식 `(api[_-]?key\|secret\|password\|token)\s*[:=]`, 사내 URL 패턴 |
| AS-7 외부 의존 | 정규식 `slack\.com`, `linear\.app`, 특정 워크스페이스 ID 패턴 |

매칭 결과는 후보 metadata에 `anti_signals: [AS-N, ...]` 형태로 누적. 1개 이상이면 REJECT.

---

## Phase 3: Score Against Gates G1–G6

REJECT되지 않은 각 후보를 6개 게이트에 대해 PASS / FAIL / UNCLEAR로 평가한다.

### G1 — Generality

자동 휴리스틱:
- 엔진별 제한 키워드(`gd_script`, `gdscript`, `godot`, `unity`, `unreal`, `c#`, `blueprint`) 등장 빈도 측정
- 프로젝트 IP 사전과 교차 검색
- 결과: 키워드 ≥ 3 → UNCLEAR / 키워드 ≥ 1 → UNCLEAR(weak) / 0 → PASS

엔진별이라도 유용하면 PASS 처리하되 target_path를 `.claude/docs/engine-specific/<engine>/`로 자동 조정.

### G2 — Validation (waivable)

자동 판정 불가. 다음 방식:
- `.claude/studio-memory/promotion-ledger.yaml`이 존재하면 해당 항목의 검증 프로젝트 수 조회
- ≥ 2 → PASS / 1 → UNCLEAR (Phase 4에서 waiver 질문) / 0 → UNCLEAR

ledger 부재 시 모두 UNCLEAR로 두고 Phase 4에서 처리.

### G3 — Non-Conflict

각 후보의 target_path가 가리키는 템플릿 파일이 이미 존재하면:
- skill: `name` 중복 → FAIL (병합 PR로 전환 필요)
- 문서: 같은 섹션 헤더 중복 → UNCLEAR (병합 가능 여부 사용자 확인)
- agent: 같은 agent 정의 중복 → FAIL

기존 ADR과 명시적 모순 여부는 자동 검사 불가 → Phase 4 질문.

### G4 — Non-Duplication

- `.claude/skills/` 디렉토리에서 후보와 description 유사도 ≥ 70% (단순 키워드 overlap)인 기존 skill이 있으면 UNCLEAR
- `.claude/docs/`에서 동일 주제 문서 검색 동일

### G5 — Stability

- 후보 파일의 `git log --oneline -- <path>` 마지막 수정일 조회
- 30일 이상 무수정 → PASS / 7~30일 → UNCLEAR / 7일 미만 → UNCLEAR(weak)

### G6 — Maintenance Cost

자동 판정 불가. 모두 UNCLEAR로 두고 Phase 4에서 사용자에게 owner 지정 요청.

---

## Phase 4: Interactive Adjudication

UNCLEAR가 1개 이상인 후보들을 한 항목씩 사용자에게 제시한다. `AskUserQuestion` 사용.

질문 형식:

```
[1/N] <type>: <source_path>
  G1 Generality:    PASS
  G2 Validation:    UNCLEAR (ledger 미존재 또는 단일 프로젝트)
  G3 Non-Conflict:  PASS
  G4 Non-Dup:       UNCLEAR (기존 /xxx skill과 유사도 72%)
  G5 Stability:     PASS
  G6 Maint Cost:    UNCLEAR (owner 미지정)

  필요한 결정:
  - G2 waiver? (Director Group 합의로 면제) [yes / no / split]
  - G4 병합 대상? (기존 /xxx에 흡수) [merge / keep-separate]
  - G6 owner? [producer / technical-director / lead-programmer / ...]
```

응답을 후보 metadata에 기록. 응답 후:
- 모든 UNCLEAR 해소 + FAIL 없음 → **PROMOTE**
- waiver 거부 또는 FAIL 남음 → **REJECT**
- 사용자가 "skip" 선택 → **DEFER** (제안서에 남고 다음 회차 재검토)

---

## Phase 4.5: Conflict-Bundled ADR Detection

PROMOTE 처리 중 G3에서 기존 규칙을 대체(supersede)하는 경우, 동반 ADR이 필요하다고
사용자에게 알리고 ADR 초안 파일명을 제안한다 (`docs/architecture/NNN-<topic>.md`).
실제 ADR 작성은 별도 skill(`/architecture-decision`) 권장. 제안서에 "동반 ADR 필요"
표시.

---

## Phase 5: Generate Proposal

### 5.1 승인 게이트 (Write 전 필수)

제안서를 작성하기 전에 다음을 사용자에게 제시하고 명시적 승인을 받는다:

1. 작성할 파일 경로 (`docs/studio-promotion-proposal-YYYY-MM-DD.md`, 같은 날 존재 시 `-2`/`-3` 접미사)
2. 제안서 구조 요약 (총 후보 N건 — PROMOTE x / DEFER y / REJECT z, Summary Table 헤더만)
3. 질문 형식: **"위 내용으로 제안서를 `<path>`에 작성합니다. 승인하시겠습니까?"**

사용자가 거부하면 작업을 중단하고 콘솔에 요약만 출력 후 종료. 수정 요청이 있으면 요청 반영 후 동일 게이트 재요청.

### 5.2 제안서 작성

승인을 받은 후에만 Write 도구로 파일 생성. 파일이 같은 날 이미 존재하면 `-2`, `-3` 접미사.

### 제안서 구조

```markdown
# Studio Promotion Proposal — YYYY-MM-DD

**Source Project**: <project name from CLAUDE.md or repo name>
**Source Commit**: <git rev-parse HEAD>
**Upstream Reference**: <STUDIO_UPSTREAM>/main @ <sha>
**Scope**: <scope arg>
**Total Candidates**: N (PROMOTE: x, DEFER: y, REJECT: z)

---

## Summary Table

| ID | Type | Source | Verdict | Notes |
|----|------|--------|---------|-------|
| P-01 | skill | .claude/skills/foo/ | PROMOTE | G2 waived (producer+TD) |
| P-02 | rule | .claude/docs/bar.md | DEFER | G4 unresolved |
| P-03 | memory | feedback_test_db.md | REJECT | AS-3 (engine version) |

---

## PROMOTE Items

### P-01: <name>
- **Source**: <path>
- **Target**: <template path>
- **Gates**: G1✅ G2⚠️(waived: <사유>) G3✅ G4✅ G5✅ G6✅(owner: producer)
- **Anti-signals**: none
- **Rationale**: <한 단락 — 왜 이게 일반적으로 유용한가>
- **Companion ADR needed**: no
- **Diff**:
  ```diff
  <unified diff or full content>
  ```

(... 이하 PROMOTE 항목 반복)

---

## DEFER Items

(... 동일 구조, 미해소 게이트 명시)

---

## REJECT Items

| ID | Source | Anti-signals / Failed gates | Suggested action |
|----|--------|-----------------------------|------------------|
| R-01 | ... | AS-3 | 엔진 버전 의존 제거 후 재제출 |

---

## Next Actions

1. Director Group 검토 (서명 필요: producer + <도메인 director>)
2. PROMOTE 항목 적용:
   - 수동: 스튜디오 템플릿 repo에서 직접 반영
   - 자동: `/studio-promote --apply <studio-template-path>` 재실행
3. DEFER 항목은 다음 마일스톤 회고에서 재평가
4. 적용 후 `.claude/studio-memory/promotion-ledger.yaml` 갱신
5. 적용 후 템플릿 `CHANGELOG.md`에 출처 기록
```

---

## Phase 6: Optional Apply

`--apply <path>` 인자가 있을 때만 실행.

### 6.1 사전 검증

다음을 순서대로 확인. 하나라도 실패하면 **즉시 중단**하고 Phase 5 제안서만 남긴다.

1. `<path>`가 존재하는 디렉토리인가
2. `<path>/CLAUDE.md` 첫 줄이 `Claude Code Game Studios` 매칭 (스튜디오 템플릿 확인)
3. `<path>`에서 `git status --porcelain` 결과 empty (워킹 트리 클린)
4. `<path>`에서 `git rev-parse --abbrev-ref HEAD`가 main 또는 사용자 지정 base
5. `gh auth status` 통과 (`gh` CLI 설치 + 인증)

실패 시 사용자에게 어떤 검증이 왜 실패했는지 보고.

### 6.2 적용 계획 승인 게이트 (브랜치/커밋/푸시 전 필수)

사전 검증(6.1)을 통과한 직후, 실제 git 조작을 시작하기 전에 다음을 사용자에게 제시한다:

1. 생성할 브랜치명: `promotion/<source-project-slug>-YYYY-MM-DD`
2. 적용할 PROMOTE 항목 전체 목록 (ID + 파일 경로 + target_path)
3. 디렉토리 신규 생성 여부 (target_path별)
4. 커밋 메시지 초안 전문 (아래 6.2.1 참조)
5. 푸시 대상: `origin/<branch>` + PR 본문 초안 (6.3)
6. 질문 형식: **"위 계획대로 스튜디오 템플릿 repo에 PR을 생성합니다. 진행하시겠습니까?"**

거부 시 즉시 중단(Phase 5 제안서는 남김). 항목별 부분 적용 요청이 있으면
선택 항목만 반영한 새 계획으로 다시 게이트.

### 6.2.1 PR 브랜치 생성 및 파일 적용

승인을 받은 후에만 실행:

```bash
cd <path>
git checkout -b promotion/<source-project-slug>-YYYY-MM-DD
```

각 PROMOTE 항목에 대해:
- target_path 디렉토리가 없으면 생성
- 파일 복사 (또는 diff인 경우 patch 적용)
- skill의 경우 SKILL.md만이 아니라 디렉토리 전체 복사

```bash
git add <적용한 파일들>
git commit -m "$(cat <<'EOF'
chore(promotion): import N items from <source-project> (YYYY-MM-DD)

Source project: <name>
Source commit: <sha>
Proposal: docs/studio-promotion-proposal-YYYY-MM-DD.md (in source repo)

Items:
- P-01: <name>
- P-02: <name>
...

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

### 6.3 Push & PR

```bash
git push -u origin promotion/<source-project-slug>-YYYY-MM-DD
gh pr create --title "Promotion: N items from <source-project> (YYYY-MM-DD)" --body "$(cat <<'EOF'
## Source
- Project: <name>
- Commit: <sha>
- Proposal: <link or path>

## Promoted Items
<summary table from proposal>

## Reviewer Checklist
- [ ] Verify each item against G1-G6 in studio-promotion-criteria.md
- [ ] G2 waivers signed by producer + technical-director
- [ ] Companion ADRs included if listed
- [ ] CHANGELOG.md updated with promotion record
- [ ] promotion-ledger.yaml updated

🤖 Generated with /studio-promote
EOF
)"
```

### 6.4 Ledger 갱신 (승인 게이트 포함)

`<path>/.claude/studio-memory/promotion-ledger.yaml`에 추가할 entry를 사용자에게
보여주고 명시적 승인을 받은 후에만 PR diff에 포함한다:

1. ledger 파일 존재 여부 (신규 생성인지, 추가인지 명시)
2. 추가할 entry 전체 YAML 텍스트 (아래 형식)
3. 질문 형식: **"위 entry를 ledger에 추가합니다. 승인하시겠습니까?"**

거부 시 ledger 부분은 건너뛰고 PR은 그대로 진행 (ledger는 사용자가 수동 갱신).

추가할 entry 형식:

```yaml
- item: <name>
  type: <type>
  target_path: <path>
  promoted_at: YYYY-MM-DD
  source_project: <name>
  source_commit: <sha>
  validated_in: [<source-project>]
  g2_waived: <true/false>
  g2_waiver_signers: [producer, technical-director]  # waived인 경우만
```

ledger 파일이 없으면 신규 생성.

---

## Phase 7: Report

사용자에게 최종 요약:

```
Studio Promotion 완료

후보: N건
  PROMOTE: x건
  DEFER:   y건
  REJECT:  z건

제안서: docs/studio-promotion-proposal-YYYY-MM-DD.md

[--apply 모드인 경우]
PR: <gh pr URL>
검토자: <소집 대상 director들>

[기본 모드인 경우]
다음 액션: 스튜디오 템플릿 repo에서 제안서 검토 후 수동 반영
또는: /studio-promote --apply <path>로 재실행
```

---

## Failure Modes

| 상황 | 처리 |
|------|------|
| upstream remote 없음 | 사용자에게 묻고, 응답 없으면 종료 |
| git diff 비어있음 | "승격 대상 변경사항이 없습니다." 후 종료 |
| `gh` CLI 부재 (--apply 시) | 기본 모드로 자동 폴백, 제안서만 생성 |
| 워킹 트리 dirty (--apply 시) | 검증 단계에서 중단, 정리 후 재실행 안내 |
| 같은 날짜 제안서 존재 | `-2`, `-3` 접미사로 분기 |
| AskUserQuestion 응답 거부 | 해당 항목 DEFER로 처리, 다음 후보로 진행 |

---

## Related Skills & Docs

- 기준: `.claude/docs/studio-promotion-criteria.md`
- 마일스톤 트리거: `/milestone-review` (producer가 promotion 누락 체크)
- 동반 ADR: `/architecture-decision`
- 검증 ledger 위치: 스튜디오 템플릿 repo `.claude/studio-memory/promotion-ledger.yaml`
