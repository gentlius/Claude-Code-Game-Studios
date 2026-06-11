# Microservices Playbook — 게임 백엔드 설계 의사결정 가이드

> 신규 게임 백엔드 프로젝트 킥오프 시, 그리고 운영 중 분해/통합 결정 시 참고하는 실무 문서.
> Reference cases: com2us-roca 의 **DS 라인업** (DarkSword VR / Node.js Polyrepo) 과 **TW 라인업** (HB / Go Monorepo Multi-binary).
> Last updated: 2026-06-10

---

## 목차

1. [Reference Case Study — DS / TW 구조 분석](#1-reference-case-study--ds--tw-구조-분석)
2. [의사결정 트리 — 어떤 분해 전략을 쓸 것인가](#2-의사결정-트리--어떤-분해-전략을-쓸-것인가)
3. [안티패턴 카탈로그](#3-안티패턴-카탈로그)
4. [신규 프로젝트 체크리스트](#4-신규-프로젝트-체크리스트)
5. [비용 / 복잡도 모델](#5-비용--복잡도-모델)
6. [진화 경로 — Modular Monolith → Microservices](#6-진화-경로--modular-monolith--microservices)
7. [기술 스택 매트릭스 — 게임 백엔드 도메인별](#7-기술-스택-매트릭스--게임-백엔드-도메인별)
8. [장애 시나리오 카탈로그](#8-장애-시나리오-카탈로그)
9. [거버넌스 메타](#9-거버넌스-메타)

---

## 1. Reference Case Study — DS / TW 구조 분석

### 1.1 두 가지 분해 전략 비교

| 라인업 | 분해 단위 | 언어 | 배포 |
|---|---|---|---|
| **DS** (DarkSword VR) | **Repo-per-Service** — 6개 독립 레포 + Python 배치 1개 | Node.js / TypeScript + Python | EKS Deployment 1:1 |
| **TW** (HB 코드명) | **Mono-repo Multi-binary** — 4개 서비스 + 별도 C++ 배틀 서버 | Go + C++ | EKS 4개 + EC2/Fleet (배틀) |

같은 회사에서 의도적으로 두 패턴을 병행 — Conway's Law (조직 구조 → 시스템 구조) 측면에서 팀 자율성 실험으로 해석 가능.

### 1.2 DS 라인업 (Domain-Decomposed Microservices)

**서비스 구성**: `ds-server-auth`, `ds-server-game`, `ds-server-log`, `ds-server-mailbox`, `ds-server-shop`, `ds-server-statistics`, `ds-statistics` (Python 배치), `ds-admin-web` (React)

**적용 방법론**:
- **(1) Bounded Context 기반 분해 (DDD)** — Eric Evans의 *Domain-Driven Design*. 도메인 경계 = 서비스 경계.
- **(2) Layered + Clean Architecture 변형** — Routes → Services → Models 3계층. TypeDI 데코레이터 기반 IoC/DI.
- **(3) Shared Kernel** — DDD 공유 커널 패턴. `rocats` (private Node.js lib, v1.1.27/28)을 6개 서비스가 공유. *주의: 정통 마이크로서비스 교리에서는 Shared Library Coupling 안티패턴.*
- **(4) Synchronous REST + JWT Authentication Delegation** — 동기 HTTP 통신, 메시지 브로커 미사용 (Kafka 인프라 모듈은 있으나 클라이언트 사용 미확증).
- **(5) Partial Polyglot Persistence** — MySQL (Sequelize) + Redis. *Database-per-Service 패턴은 부분 적용 — 동일 MySQL 풀에 스키마만 분리.*
- **(6) Polyglot Stack** — Node.js (IO 바운드 비즈니스 로직) + Python (배치/통계) + React (어드민 SPA).

**기술 스택**: Node.js 20, TypeScript, Express, Sequelize + sequelize-auto, TypeDI, Jest + supertest, AWS EKS, Terraform + Ansible, Prometheus + Grafana + Loki + OpenSearch, AWS GameLift.

### 1.3 TW 라인업 (Monorepo Multi-binary)

**서비스 구성**: `tw-api(8080)`, `tw-admin(8082)`, `tw-matchmaker(8083)`, `tw-log(8081)` + `tw-server-battle` (C++ 실시간 배틀, K8s 미사용)

**적용 방법론**:
- **(1) Monorepo Multi-binary** — `cmd/{service}/main.go` 4개 엔트리. Google/Uber 스타일. 공유 도메인 모델/유틸을 패키지로 직접 import — 타입 안전한 내부 공유.
- **(2) Handler → Service → Repository (Hexagonal 변형)** — 도메인 내부 모듈(`internal/user`, `internal/match`, `internal/quest`, ...)이 각자 3계층. **Modular Monolith의 모듈을 그대로 잘라 4개 binary로 묶은 형태**.
- **(3) Context-Propagation DI** — `mysql.Client(ctx)` 패턴, Ambient Context.
- **(4) Code Generation 중심 워크플로우** — Ent ORM (Schema → 타입 안전 클라이언트), `table-parser` (CSV → Go 타입 게임 밸런싱 테이블).
- **(5) Variant Versioning** — 글로벌은 홀수 끝자리, 중국은 짝수 끝자리 (규제권역별 fork-and-merge를 버전 컨벤션으로 표현).
- **(6) Latency-Critical Path 분리** — 실시간 배틀은 C++로 분리, K8s가 아닌 EC2/Fleet 직접 배포.

**기술 스택**: Go, Echo 기반 자체 framework, Ent ORM, Skaffold (로컬 K8s 개발), Make + Jenkins, AWS ECR/EKS, AWS GameLift.

### 1.4 공통 인프라

- **VPC/EKS/RDS/EC2/OpenSearch** Terraform 모듈
- **Observability stack**: Prometheus + Grafana + Loki (메트릭+로그), OpenSearch (로그)
- **Message Bus 후보**: Kafka 모듈 (`ds-infra/modules/k8s_kafka`) — 인프라 존재, 클라이언트 사용 미확증
- **IaC**: Terraform + Ansible (`result` 모듈로 두 계층 간 다리)
- ⚠ Terraform state를 git commit + 동시성 lock 없음 — 거버넌스 리스크

### 1.5 강점·약점 요약

**강점**: 독립 배포 / 장애 격리 / 이질 워크로드 매칭 (Polyglot) / 팀별 오너십 / 독립 스케일링 / 기술 도입 점진성 / 규제권역 분리 / **신작 게임 다발 출시 사업 구조에 적합** (라인업 복제, 인프라/라이브러리 표준 재사용).

**약점**: Shared Library Coupling (rocats v1.1.27 vs v1.1.28 혼재) / Synchronous REST Cascade (circuit breaker 미확증) / 데이터 자율성 부족 (single MySQL pool) / God Service 위험 (ds-server-game 4도메인 보유) / 분산 시스템 운영 복잡도 / SSH-mounted 빌드 의존성 / Distributed Tracing 부재 / 이벤트 백본 부재 / 배틀 서버 별도 운영 패러다임.

---

## 2. 의사결정 트리 — 어떤 분해 전략을 쓸 것인가

```
START — 신규 게임 백엔드 프로젝트
│
├─ Q1. 일일 활성 사용자(DAU) 예상치는?
│   ├─ < 10K       → Modular Monolith 권장 (분해 미적용)
│   ├─ 10K ~ 1M    → Monorepo Multi-binary or Modular Monolith
│   └─ > 1M        → Polyrepo Microservices 고려
│
├─ Q2. 팀 규모는?
│   ├─ 1~5명       → Modular Monolith (Conway's Law: 작은 팀은 단일 코드베이스)
│   ├─ 5~20명      → Monorepo Multi-binary
│   └─ > 20명, 여러 squad → Polyrepo Microservices
│
├─ Q3. 도메인 경계가 명확한가?
│   ├─ 아직 발견 중 → Modular Monolith로 시작, 분해는 나중
│   └─ 명확함      → 다음 질문으로
│
├─ Q4. 워크로드 이질성은? (실시간 vs IO vs 배치)
│   ├─ 동질        → 단일 언어 / 단일 분해 패턴
│   └─ 이질        → Polyglot 고려 (TW의 C++ 배틀 서버 분리 사례)
│
├─ Q5. 규제권역별 운영이 필요한가? (글로벌/중국/EU GDPR 등)
│   ├─ No          → 단일 리전 전략
│   └─ Yes         → 처음부터 multi-region 고려, variant versioning 규약 미리 결정
│
└─ Q6. 다른 게임 라인업으로 복제할 계획이 있는가?
    ├─ No          → 프로젝트 특화 최적화
    └─ Yes         → Boilerplate 표준화 우선 (DS 라인업의 ds-server-* 6개 동형 패턴 참고)
```

### 2.1 분해 전략별 적합도

| 전략 | 적합 | 부적합 |
|---|---|---|
| **Modular Monolith** | 초기 단계, MVP, 도메인 경계 탐색 중, < 10K DAU | 다중 팀 동시 개발, 글로벌 멀티리전, 이질 워크로드 |
| **Monorepo Multi-binary** | 중간 규모, 단일 언어 선호, 강한 타입 공유 필요, 5~20명 팀 | 팀별 독립 배포 사이클, 다국적 분산 팀 |
| **Polyrepo Microservices** | 대규모, 여러 게임 라인업, 다중 팀, > 1M DAU | 초기 단계, 작은 팀, 운영 인력 부족 |
| **Hybrid (DS/TW 같이)** | 회사 차원에서 여러 게임 동시 운영, 라인업별 최적화 | 표준화 거버넌스 부재 시 카오스 |

---

## 3. 안티패턴 카탈로그

DS/TW에서 관찰된 실제 사례 포함.

### 3.1 God Service

**증상**: 하나의 서비스가 너무 많은 도메인을 담당.
**사례**: `ds-server-game`이 game + game-admin + match + party 4도메인 보유.
**원인**: "관련된 것끼리 묶자"는 단기 편의 → 시간 지나면 변경 영향 범위 폭증.
**회피**: Bounded Context 1개당 서비스 1개 원칙. 도메인이 늘어나면 분할 고려.

### 3.2 Distributed Monolith

**증상**: 서비스는 나뉘었으나 강결합 — 한 서비스 변경 시 다른 서비스도 동시 배포 필요.
**사례 위험**: `rocats` 공용 라이브러리 v1.1.27 vs v1.1.28 혼재. breaking change 시 6개 서비스 동시 마이그레이션 필요.
**회피**: Shared library의 SemVer 엄격 준수. Breaking change는 별도 메이저 버전. 가능하면 라이브러리 대신 **서비스로 추출** (예: 공통 로직을 별도 internal service로).

### 3.3 Synchronous REST Cascade

**증상**: 서비스 A → B → C 동기 호출 체인. 하나가 느려지면 전체 지연.
**사례**: `ds-server-game/src/services/user-auth-service.ts`의 단순 `fetch` 호출, circuit breaker / retry budget / timeout 정책 미확증.
**회피**: ① Circuit Breaker 패턴 (Hystrix/Resilience4j 류) ② 비동기 이벤트로 가능한 부분 전환 (예: 통계/로깅) ③ Backend-for-Frontend 패턴으로 fan-out을 클라이언트 가까이.

### 3.4 Shared Database Anti-pattern

**증상**: 여러 서비스가 동일 DB 스키마를 공유 → 스키마 변경이 여러 서비스에 영향.
**사례 의심**: ds-server-* 6개가 단일 MySQL 풀 사용 정황. *Database-per-Service 미적용 가능성.*
**회피**: 서비스별 DB 또는 최소한 스키마 분리. 데이터 동기화는 이벤트 기반(CDC, outbox 패턴).

### 3.5 Magic Codename Sprawl

**증상**: 프로젝트/서비스 명에 미공개 코드명이 박혀 외부 진입장벽이 됨.
**사례**: TW·HB·DS·PSB·TR 등 코드명 다수 사용, 일부는 README/CLAUDE.md에 매핑 명시 없음 (사내 인벤토리 문서 별도 분석으로 확증).
**회피**: 레포 README 상단에 코드명 → 정식명 매핑 한 줄 의무화.

### 3.6 Git-tracked Terraform State

**증상**: `*.tfstate`를 git에 커밋, 동시 apply 시 충돌.
**사례**: ds-infra 명시적 정책 ("`*.tfstate` 파일은 git commit, lock 없이 팀 코디네이션에 의존" — 사내 CLAUDE.md 출처).
**회피**: AWS S3 백엔드 + DynamoDB lock (표준 패턴). 또는 Terraform Cloud / Atlantis.

### 3.7 Untracked DEV Versions

**증상**: DEV 환경에 개발자 개인 태그(`suki` 등)가 배포되어 재현/추적 어려움.
**사례**: `ds-server-game` DEV에 개발자 개인 태그(`suki`) 박힘 (사내 인벤토리 확증).
**회피**: DEV도 SemVer 태그 또는 `branch-shortSHA` 컨벤션 강제.

### 3.8 SSH-mounted Private Dependency

**증상**: Docker 빌드에서 SSH 키 mount해 private 라이브러리 받기 — CI/CD 복잡도, 신규 개발자 마찰.
**사례**: ds-server-* 의 `RUN --mount=type=ssh yarn install`.
**회피**: ① Private NPM/Go Module Registry (예: GitHub Packages, JFrog) ② Build-time만 필요한 패키지는 사전 빌드된 base image에 포함.

### 3.9 Observability Gap

**증상**: 메트릭/로그는 있으나 **Distributed Tracing 부재** — 서비스 간 호출 흐름 추적 불가.
**사례 의심**: DS/TW 모두 Prometheus + Loki는 확증, OpenTelemetry/Jaeger 미확증.
**회피**: 초기부터 OpenTelemetry 표준 도입. 최소한 trace_id를 모든 서비스 로그에 propagate.

### 3.10 Single-Path Failure

**증상**: 인증/매칭 등 critical path가 단일 서비스/단일 외부 의존성에 묶임.
**사례 위험**: AWS GameLift 의존 (DS/TW 모두). GameLift 장애 시 매칭 전체 중단.
**회피**: Fallback 매칭 풀 또는 self-hosted 대체 경로 준비.

---

## 4. 신규 프로젝트 체크리스트

킥오프 첫 1~2 sprint에 결정해야 할 항목들.

### 4.1 분해 전략
- [ ] Modular Monolith / Monorepo Multi-binary / Polyrepo Microservices 중 선택
- [ ] Bounded Context 1차 매핑 (도메인 → 서비스 후보)
- [ ] 코드명 → 정식명 매핑 README 명시 의무화

### 4.2 데이터 계층
- [ ] Database-per-Service 적용 여부 (강결합 트레이드오프 인지)
- [ ] ORM 선택 (Node.js: Sequelize / Prisma / TypeORM, Go: Ent / GORM / sqlc)
- [ ] Schema migration 도구 (Flyway / Liquibase / Atlas / golang-migrate)
- [ ] Read replica 분리 시점 정의
- [ ] BigInt/UUID/PK 전략 (Sequelize의 BigInt-as-string 등 알려진 함정 인지)

### 4.3 서비스 간 통신
- [ ] 동기 (REST / gRPC) vs 비동기 (Kafka / NATS / Redis Streams) 비중 결정
- [ ] Circuit Breaker / Retry / Timeout 정책 라이브러리 표준화
- [ ] API Gateway 도입 여부 (Kong / AWS API Gateway / Envoy)
- [ ] 서비스 디스커버리 (K8s DNS / Consul / etcd)

### 4.4 인증/인가
- [ ] JWT vs Session 결정
- [ ] 토큰 캐시 위치 (Redis 권장)
- [ ] 플랫폼 인증 추상화 인터페이스 (Pico / Oculus / Steam / Apple / Google)
- [ ] Admin 권한 시스템 (RBAC / ABAC)

### 4.5 인프라 / 배포
- [ ] Container orchestrator (EKS / GKE / AKS / Nomad)
- [ ] IaC 도구 (Terraform / Pulumi / CDK)
- [ ] State 백엔드 (S3+DynamoDB lock, Terraform Cloud — git commit 금지)
- [ ] Multi-region 전략 (active-active / active-passive / regional sharding)
- [ ] Variant versioning 규약 (글로벌/중국/검수용 등)

### 4.6 CI/CD
- [ ] CI 도구 (GitHub Actions / Jenkins / GitLab CI / CircleCI)
- [ ] CD 전략 (GitOps with ArgoCD / Flux / 수동 deploy script)
- [ ] 로컬 K8s 개발 (Skaffold / Tilt / Telepresence)
- [ ] Build artifact registry (ECR / GHCR / Harbor)
- [ ] Private dependency 전달 방식 (SSH mount 회피 권장)

### 4.7 관측 / 운영
- [ ] 메트릭 (Prometheus + Grafana)
- [ ] 로그 (Loki / ELK / OpenSearch)
- [ ] **Distributed Tracing (OpenTelemetry + Jaeger/Tempo)** ← 초기부터 권장
- [ ] APM (Datadog / New Relic / Elastic APM)
- [ ] 알람 채널 (PagerDuty / Slack / Discord)
- [ ] 온콜 로테이션 정책

### 4.8 게임 도메인 특화
- [ ] 게임 테이블/밸런싱 데이터 파이프라인 (CSV → 코드 생성? Excel → JSON?)
- [ ] 매치메이킹 (GameLift / Open Match / 자체 구현)
- [ ] 실시간 통신 (WebSocket / TCP / UDP / Photon / Mirror)
- [ ] 안티치트 전략
- [ ] 라이브 이벤트 / 핫픽스 전략 (config server, feature flag)
- [ ] 점검 시 클라이언트 통제 방식

### 4.9 보안
- [ ] Secret 관리 (AWS Secrets Manager / Vault / 1Password CLI)
- [ ] `.env` 파일 git commit 금지 + pre-commit hook
- [ ] 결제 PCI 컴플라이언스 범위
- [ ] PII 처리 / GDPR 대응
- [ ] DDoS 방어 (CloudFlare / AWS Shield)

### 4.10 거버넌스
- [ ] 공용 라이브러리 SemVer 정책
- [ ] 코드 오너십 (CODEOWNERS)
- [ ] Architecture Decision Records (ADR) 도입
- [ ] Sprint별 tech debt 시간 할당

---

## 5. 비용 / 복잡도 모델

**전제**: "마이크로서비스 1개 추가의 한계비용"을 정량 가늠.

> ⚠ **본 섹션의 모든 숫자는 예시 추정값**. 실제 비용은 리전 / 사용량 / 인건비 표준 / Reserved Instance 여부에 따라 **5~50배 차이** 가능. 의사결정 전 자체 비용 계산 필수. 본 모델은 비교 감각용.

### 5.1 서비스 1개 추가 시 발생하는 운영 부담

| 항목 | 1회성 비용 | 지속 비용 (월 기준) |
|---|---|---|
| Git 레포 + CI/CD 파이프라인 셋업 | 4~8 hr | 0.5 hr/월 (maintenance) |
| Dockerfile + K8s manifest | 2~4 hr | 1 hr/월 (upgrade) |
| 모니터링 대시보드 + 알람 | 4 hr | 1 hr/월 |
| 온콜 런북 작성 | 4 hr | 0.5 hr/월 |
| 인프라 (EKS 노드, RDS, ELB, 로그/메트릭 스토리지) | $50~200/월 | 동일 |
| 분산 트레이싱 instrumentation | 4 hr | 0 |
| 문서화 (README, CLAUDE.md, API docs) | 4 hr | 1 hr/월 |
| **합계** | **22~28 hr** | **4 hr/월 + $50~200/월** |

### 5.2 손익분기 추정

10명 백엔드 팀, 시간당 $50 환산:
- 서비스 1개 = 월 $200 (인건비) + $100 (인프라) = **$300/월**
- 10개 서비스 = **$3,000/월** 운영 부담

**언제 가치 있는가** — 다음 중 2개 이상 해당 시:
- 도메인 변경 빈도가 서비스별로 크게 다름 (auth는 안정, shop은 매주 이벤트)
- 팀이 도메인별로 분리되어 있어 동시 작업 충돌 다발
- 스케일링 요구가 도메인별로 비대칭 (game은 100 pod, mailbox는 2 pod)
- 기술 스택이 도메인별로 명확히 다름 (Python ML, Go 게임 로직, Node 어드민)

### 5.3 마이크로서비스 1개 추가 결정 트리거

```
필요한 도메인이 추가됨
    │
    ├─ 기존 서비스에 모듈로 추가 가능? (네임스페이스/패키지 분리)
    │   └─ Yes → Modular Monolith 안에 모듈로
    │
    ├─ 다른 언어/런타임이 더 적합한가?
    │   └─ Yes → 별도 서비스
    │
    ├─ 독립 배포 사이클이 필요한가?
    │   └─ Yes → 별도 서비스
    │
    ├─ 독립 스케일링이 필요한가?
    │   └─ Yes → 별도 서비스
    │
    └─ 위 모두 No → Modular Monolith 안에 모듈로 (분리 비용 회피)
```

---

## 6. 진화 경로 — Modular Monolith → Microservices

### 6.1 Strangler Fig Pattern

Martin Fowler의 *Strangler Fig*: 기존 시스템 옆에 신규를 점진적으로 키워 결국 기존을 대체.

```
Step 0: Modular Monolith
    [ monolith: auth, game, shop, mailbox, log, stats ]

Step 1: 분해 후보 도메인 선정 (예: log 가장 독립적)
    [ monolith + log API client → ] [ log-service ]

Step 2: 트래픽 일부를 분리된 서비스로 (Feature Flag로 전환율 조절)
    [ monolith ] ←→ [ log-service ]

Step 3: 100% 전환 + monolith의 log 코드 제거

Step 4: 다음 후보로 반복 (예: stats, shop, ...)
```

### 6.2 분해 우선순위 — 어떤 도메인부터?

**1순위 후보** (분리 효과 큼, 위험 작음):
- **Log/Telemetry** — 한 방향 쓰기, 강결합 없음
- **Statistics/Analytics** — 배치성, 다른 기술 스택 적합 (Python)
- **Mailbox/Notification** — 비동기성 강함

**2순위 후보**:
- **Shop/IAP** — 트래픽 패턴 다름, 보안 요구 다름
- **Match-making** — 외부 SDK(GameLift) 의존성 격리

**최후 후보** (절대 마지막에):
- **Auth** — 모든 도메인이 의존, 분리 비용 큼
- **Core Game Logic** — 도메인 응집도 높음

### 6.3 통합(다시 묶기) 결정 시점

마이크로서비스를 **줄이는** 것도 valid:
- 두 서비스가 항상 같이 배포되고 있다 → 합쳐도 됨
- 한 서비스가 다른 서비스 호출만 거의 100% 차지 → BFF로 합치기
- 트래픽이 너무 적어 운영 비용이 비즈니스 가치를 초과 → Modular Monolith로 복귀

**참고 사례** — Amazon Prime Video Tech Blog (2023), "Scaling up the Prime Video audio/video monitoring service to reduce costs by 90%": AWS Step Functions + Lambda 기반 영상 모니터링 시스템을 단일 EC2 컨테이너로 통합해 인프라 비용 약 90% 절감. 단 이는 *서버리스 분산 → 모놀리스* 회귀로, 일반적인 마이크로서비스 → 모놀리스 회귀에 직접 일반화할 사례는 아님. 그럼에도 교훈은 분명 — **분산 = 항상 정답 아님**, 도메인별 trade-off 재평가 필요.

---

## 7. 기술 스택 매트릭스 — 게임 백엔드 도메인별

| 도메인 | 권장 1순위 | 권장 2순위 | 사유 |
|---|---|---|---|
| **API Gateway** | Envoy / Kong | AWS API Gateway | L7 라우팅, rate limit, JWT 검증 통합 |
| **인증/인가** | Node.js + JWT + Redis | Go + JWT + Redis | IO 바운드, 표준 라이브러리 풍부 |
| **게임 로직 (turn-based)** | Go + Echo/Gin + Ent | TypeScript + NestJS | 타입 안전 + 동시성 처리 |
| **게임 로직 (real-time)** | C++ / Rust + UDP | C# + Photon / Mirror (Unity 생태계) | 1순위: GC 없는 최소 레이턴시. 2순위: 개발 생산성 + Unity 클라 연계, GC tuning 필요 |
| **매치메이킹** | Go + GameLift (managed) | Go + Open Match (self-hosted, K8s) | 비동기 매칭 큐. ⚠ Erlang/Elixir는 분산 강점이나 한국 게임 회사 인력 풀 한계로 비추천 |
| **상점/IAP** | Node.js + TypeORM + 상점 SDK | Go + Ent | 외부 API 통합 (Apple/Google/Steam) |
| **우편함** | Node.js + Redis Streams | Go + NATS | 비동기 fan-out |
| **로깅/이벤트** | Node.js → Kafka → Loki/Elastic | Vector + Loki | 한 방향 쓰기, throughput 중시 |
| **통계/분석 (배치)** | Python + Airflow + dbt → BigQuery / ClickHouse | Spark (대규모 회사 한정) | 배치 + SQL warehouse. ⚠ Spark는 클러스터 운영 부담 큼. 중소 규모는 BigQuery/ClickHouse + dbt가 현실적 |
| **어드민 백엔드** | Node.js + Express | Go + Echo | CRUD 중심, 빠른 개발 |
| **어드민 프론트** | React + TanStack Query | Vue + Pinia | 컴포넌트 생태계 |
| **배틀 서버 (FPS/MOBA)** | C++ / Unreal Dedicated Server | Go (단순 게임 한정) | UDP, 100Hz tick. ⚠ Rust + Bevy는 학술적 후보지만 dedicated 서버 프로덕션 사례 적음, 신중 선택 |
| **메시지 브로커** | Kafka | NATS JetStream / Redis Streams | 게임 이벤트 throughput |
| **캐시** | Redis Cluster | KeyDB / DragonflyDB | 표준, 광범위 라이브러리 |
| **OLTP DB** | MySQL (Aurora) / PostgreSQL | CockroachDB / TiDB | 게임 데이터 특성 (read-heavy) |
| **OLAP DB** | ClickHouse | BigQuery / Redshift | 통계 쿼리 |
| **Object Storage** | S3 (AWS) / GCS (GCP) | MinIO (self-hosted) | 빌드 산출물, 유저 콘텐츠 |
| **CDN** | CloudFront / Cloudflare | Akamai | 게임 빌드/패치 배포 |
| **IaC** | Terraform + Atlantis | Pulumi | 팀 친숙도, 모듈 생태계 |
| **CD** | ArgoCD + Helm | Flux + Kustomize | GitOps |
| **관측** | Prometheus + Grafana + Loki + Tempo | Datadog | OSS 표준, OpenTelemetry 호환 |
| **시크릿** | AWS Secrets Manager | Vault | 라이프사이클 관리 |
| **CI** | GitHub Actions | Jenkins / GitLab CI | 게임 회사 표준 |

### 7.1 게임 백엔드 특화 고려사항

- **데이터 파이프라인** — 게임 밸런싱 테이블(CSV/Excel) → 코드 생성 도구가 거의 필수. tw-server의 `table-parser` 사례 참고. table_id 기반 hot reload 메커니즘.
- **점검 시스템** — config server로 점검 플래그 전파, 클라이언트 강제 종료 메시지 표시.
- **버전 호환성** — 클라이언트 버전과 서버 버전 매칭 검증 필수. DS는 `BuildVersionFilter` 미들웨어로 처리.
- **레이턴시 SLO** — 매치메이킹 응답 < 2s, 게임 액션 응답 < 100ms 같은 도메인별 budget 명시.

### 7.2 Reference Case와 §7 권장의 차이

§1의 DS/TW 실제 스택과 §7 권장이 일부 다른 이유:

| 항목 | DS/TW 실제 | §7 권장 1순위 | 차이 이유 |
|---|---|---|---|
| CI | Jenkins | GitHub Actions | DS/TW는 자체 Jenkins 인프라(레거시 결정). 신규는 GitHub Actions가 운영 부담 적고 OSS 생태계 풍부 |
| 통계 스택 | Python 단순 배치 (DS) | Python + dbt + BigQuery/ClickHouse | 신규는 SQL warehouse 통합 운영 권장, 분석가 협업 쉬움 |
| Auth 언어 | Node.js (DS), Go (TW) | Node.js | IO 바운드 인증 처리에 Node.js 표준 라이브러리 풍부. Go도 무방 |
| 매치메이킹 | GameLift (managed) | GameLift (managed) | 일치 |

**원칙**: Reference case는 *해당 시점의 합리적 선택*, §7 권장은 *2026년 시점 신규 프로젝트 합리적 출발점*. 기존 레거시 마이그레이션 시는 별도 비용 분석 필요.

---

## 8. 장애 시나리오 카탈로그

### 8.1 인증 서버 다운

**증상**: 모든 도메인이 토큰 검증 실패, 신규 로그인/세션 갱신 불가.
**영향 범위**: 전체.
**완화책**:
- 토큰 검증 결과 짧은 TTL 캐시 (게임 서버에서 5~30초)
- Auth read replica 분리
- Graceful degradation: 기존 세션은 만료까지 허용

### 8.2 매치메이킹 SDK (GameLift 등) 장애

**증상**: 매치 풀로 들어가지만 진입 후 무한 대기.
**완화책**:
- 매치메이킹 큐에 타임아웃 + 사용자에게 재시도 안내
- Self-hosted fallback 매칭 풀 (단순 FIFO 매칭)
- Region failover (Asia 장애 시 US-West로)

### 8.3 단일 DB Primary 장애

**증상**: 쓰기 전체 실패.
**완화책**:
- Multi-AZ + automatic failover (Aurora 기본)
- Read replica를 임시 read-only 모드로 가동
- 비결제 도메인은 read-only로 운영 지속

### 8.4 카스케이딩 지연

**증상**: 한 서비스의 응답 지연이 호출자들의 connection pool 고갈로 전파.
**완화책**:
- **Circuit Breaker** — 실패율 임계 초과 시 즉시 fail-fast
- **Bulkhead** — 도메인별 connection pool 분리
- **Timeout 정책 표준화** — 모든 outbound 호출에 명시적 timeout

### 8.5 게임 테이블 데이터 손상

**증상**: 잘못된 테이블 배포로 아이템 가격 0원, 보상 무한 등.
**완화책**:
- 테이블 배포에 검증 단계 (스키마 + 비즈니스 룰 체크)
- 즉시 rollback 가능한 버전 관리 (table_version)
- Hot reload 도구로 무중단 복구
- Staging 환경에서 24h soak 테스트

### 8.6 시크릿 누출

**증상**: AWS 키, DB 패스워드, API 토큰이 git 또는 로그에 노출.
**완화책**:
- pre-commit hook으로 `.env` / 키 패턴 검출 (truffleHog / gitleaks)
- 로그에서 민감 패턴 자동 마스킹 (Logger 레벨에서)
- Secret rotation 정책 (90일 등)
- IAM Access Analyzer로 노출된 권한 탐지

### 8.7 클라이언트 버전 분기

**증상**: 일부 유저가 구버전 클라이언트로 API 호출, 신규 응답 스키마와 불일치.
**완화책**:
- API 버저닝 (`/v1/`, `/v2/`)
- BuildVersionFilter 같은 미들웨어로 최소 버전 강제
- 점진적 deprecation (구버전 90일 유지 → 안내 → 차단)

### 8.8 라이브 이벤트 트래픽 폭증

**증상**: 점검 종료 직후 / 신규 캐릭터 출시 시 트래픽 5~10배.
**완화책**:
- HPA (Horizontal Pod Autoscaler) 사전 설정
- 점검 종료를 시간차 단계적으로 (region/cohort별)
- Queue 기반 진입 통제 (대기열 시스템)
- 게임 서버 워밍업 절차 (커넥션 풀, 캐시 사전 로드)

### 8.9 외부 플랫폼 API (Steam, Apple) 장애

**증상**: 로그인 검증, IAP 영수증 검증 실패.
**완화책**:
- 검증 결과 캐시 (IAP는 1회 검증 후 자체 DB로)
- Retry with exponential backoff
- 사용자에게 명확한 에러 메시지 + 재시도 안내

### 8.10 K8s 클러스터 장애

**증상**: 노드 그룹 전체 다운, 전체 서비스 응답 불가.
**완화책**:
- Multi-AZ node group
- 별도 클러스터로 standby (cold or warm)
- 배틀 서버는 K8s 밖(EC2)으로 분리하는 사례 (TW) — critical path 격리

---

## 9. 거버넌스 메타

### 9.1 공용 라이브러리 SemVer 정책

DS의 `rocats` 사례에서 본 문제 회피:

| 변경 유형 | 버전 증가 | 소비 서비스 대응 |
|---|---|---|
| Patch (버그 수정, 내부 리팩토링) | 1.1.27 → 1.1.28 | 자동 업데이트 가능 |
| Minor (호환 가능한 신기능) | 1.1.x → 1.2.0 | 선택적 업데이트 |
| Major (Breaking change) | 1.x.x → 2.0.0 | **모든 서비스 동시 마이그레이션 계획** 필수 |

**규칙**: Major bump 시 마이그레이션 가이드 문서화 + 마이그레이션 기한 명시 (예: "구버전 6개월 후 지원 종료").

### 9.2 Monorepo vs Polyrepo 코드 오너십

**Monorepo (TW 스타일)**:
- `CODEOWNERS` 파일로 디렉토리별 리뷰어 지정
- 통합 CI: 영향받는 서비스만 빌드/테스트 (Bazel, Nx, Turborepo)
- 장점: 원자적 변경 (스키마+서비스+클라이언트 한 PR)
- 단점: CI 시간 폭증, 빌드 시스템 복잡도

**Polyrepo (DS 스타일)**:
- 레포별 메인테이너 명확
- 독립 릴리즈 사이클
- 장점: 팀 자율성, 운영 단순
- 단점: Cross-repo 변경 시 PR fan-out, 의존성 버전 분기

### 9.3 Architecture Decision Records (ADR)

신규 프로젝트는 `docs/adr/` 디렉토리에 ADR 기록 권장:

```markdown
# ADR-001: Database-per-Service vs Shared Database

## Status
Accepted

## Context
6개 서비스(auth/game/shop/mailbox/log/stats)가 데이터 공유 필요.

## Decision
스키마는 분리하되 동일 MySQL 클러스터 사용. 향후 ds-server-stats만 별도 OLAP DB로 분리.

## Consequences
- (+) 운영 단순, 분산 트랜잭션 회피
- (-) 데이터 자율성 부족, 스키마 변경 영향 확산
- (-) 향후 stats 분리 시 마이그레이션 비용
```

ADR은 결정 자체보다 **결정의 이유**를 보존 — 6개월 후 "왜 그렇게 결정했지?"에 답하기 위함.

### 9.4 Sprint별 Tech Debt 시간 할당

DS/TW 모두 명시적 tech debt 시간 확보 정책 미확증. 권장:
- Sprint의 **15~20%**를 tech debt에 할당 (산업 표준 아닌 권장 가이드. 팀별 5~30% 범위 다양)
- 분기별 tech debt 백로그 리뷰
- 큰 마이그레이션(예: rocats v1 → v2)은 별도 mini-project로 분리

### 9.5 코드명 정책

**규칙**: 모든 신규 레포 README 첫 줄에 다음 명시 필수:
```
# TW Server (HB Project)
TW = Tower Wars (가칭). HB = Heroes' Battle (정식 출시명).
```

코드명 도입 자체는 보안/마케팅 사유로 정당하지만, **매핑 문서화는 의무**.

---

## 부록

### A. 참고 문헌

- Eric Evans, *Domain-Driven Design* (2003) — Bounded Context, Shared Kernel
- Martin Fowler, *Microservices* (martinfowler.com) — 정의, Strangler Fig
- Sam Newman, *Building Microservices* (O'Reilly, 2nd ed) — 분해 패턴
- Chris Richardson, *Microservices Patterns* (Manning) — Saga, Event Sourcing, CQRS
- Google SRE Book — Error Budget, Observability
- Kelsey Hightower, *Kubernetes Up & Running* — K8s 운영
- Conway, M., "How Do Committees Invent?" (1968) — Conway's Law 원전

### B. 게임 백엔드 특화 자료

- AWS GameLift Documentation — 매치메이킹/세션 관리
- Google Open Match — Open source matchmaking framework
- Photon Engine Documentation — 실시간 통신
- Mirror Networking (Unity) — 자체 호스팅 게임 서버

### C. Reference Case 출처 (사내 문서)

본 문서의 DS/TW 분석은 사내 com2us-roca 레포의 README, CLAUDE.md, 인벤토리 분석 문서, 인프라 모듈 정의를 기반. **외부 공개 불가**, 사내 작업 환경에서만 접근 가능.

주요 분석 대상 (사내 환경에서 참조):
- `repo-inventory.md` — DS/TW/JS 라인업 인벤토리
- `ds-server-*/CLAUDE.md` — DS 표준 패턴
- `tw-server/CLAUDE.md` — TW 모노레포 패턴
- `ds-infra/CLAUDE.md` — IaC 구조

### D. 용어집

- **Bounded Context** — DDD의 도메인 경계. 한 모델이 일관성을 갖는 범위
- **Strangler Fig** — 기존 시스템을 옆에서 점진적으로 대체하는 마이그레이션 패턴
- **Conway's Law** — "조직의 의사소통 구조가 시스템 구조에 반영된다"
- **Polyglot Persistence** — 도메인별로 다른 DB 기술 사용
- **Polyglot Programming** — 도메인별로 다른 프로그래밍 언어 사용
- **Database-per-Service** — 마이크로서비스 패턴, 각 서비스가 독립 DB 보유
- **Circuit Breaker** — 호출 실패율 임계 초과 시 즉시 fail-fast하는 패턴
- **Bulkhead** — 자원 풀을 격리해 한 영역 장애가 다른 영역에 전파되지 않게 하는 패턴
- **Saga** — 분산 트랜잭션을 보상 트랜잭션 chain으로 처리하는 패턴
- **CQRS** — Command Query Responsibility Segregation, 쓰기/읽기 모델 분리
- **Event Sourcing** — 상태 대신 이벤트 시퀀스를 저장하는 패턴
- **BFF (Backend-for-Frontend)** — 클라이언트 타입별 전용 백엔드 레이어
- **ADR (Architecture Decision Record)** — 아키텍처 결정을 짧은 마크다운으로 기록하는 관행
- **SLO/SLA/SLI** — Service Level Objective/Agreement/Indicator
- **SemVer** — Semantic Versioning, `MAJOR.MINOR.PATCH`

---

*문서 끝. 신규 프로젝트 진행 중 발견되는 새로운 패턴/안티패턴은 본 문서에 계속 추가 권장.*
