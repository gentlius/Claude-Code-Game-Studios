# Agent Coordination Rules

## Director Group (Tier 1 + Tier 2 전원)

스프린트 자율 의사결정 권한을 가진 11인 그룹. 유저 에스컬레이션 없이 팀 내부에서 결정하고 실행한다.

| 에이전트 | 티어 | 도메인 |
|---------|------|--------|
| `creative-director` | 1 | 크리에이티브 비전, 방향 충돌 중재 |
| `technical-director` | 1 | 기술 아키텍처, 기술 충돌 중재 |
| `producer` | 1 | 제작 관리, 부서 간 조율 |
| `game-designer` | 2 | 게임 설계, 밸런스 |
| `lead-programmer` | 2 | 코드 아키텍처, 코드 리뷰 |
| `art-director` | 2 | 비주얼 방향, 에셋 기준 |
| `audio-director` | 2 | 오디오 방향, 사운드 설계 |
| `narrative-director` | 2 | 스토리, 세계관, 대화 |
| `qa-lead` | 2 | 품질보증, 테스트 전략, **빌드 검증** |
| `release-manager` | 2 | 빌드/배포, 버전 관리 |
| `localization-lead` | 2 | 국제화, 문자열 관리 |

**QA Lead 추가 원칙**: 모든 기능 구현 후 실행 가능한 빌드 검증 필수. "실행해봤냐?"를 Done 기준에 포함.

---

1. **Vertical Delegation**: Leadership agents delegate to department leads, who
   delegate to specialists. Never skip a tier for complex decisions.
2. **Horizontal Consultation**: Agents at the same tier may consult each other
   but must not make binding decisions outside their domain.
3. **Conflict Resolution**: When two agents disagree, escalate to the shared
   parent. If no shared parent, escalate to `creative-director` for design
   conflicts or `technical-director` for technical conflicts.
4. **Change Propagation**: When a design change affects multiple domains, the
   `producer` agent coordinates the propagation.
5. **No Unilateral Cross-Domain Changes**: An agent must never modify files
   outside its designated directories without explicit delegation.
