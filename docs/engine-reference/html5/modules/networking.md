# HTML5 / PixiJS — Networking Module

**Last verified:** 2026-06-11

WebSocket, WebRTC, multiplayer architectures, and leaderboard / cloud save
patterns for HTML5 games.

---

## Decision Tree

```
Need multiplayer?
├── No (single-player)         → REST for leaderboards/saves
└── Yes
    ├── Realtime, > 2 players  → Authoritative server (Colyseus / custom Node)
    ├── Realtime, 2 players    → WebRTC P2P (no server) or Colyseus (server)
    ├── Turn-based             → REST polling or WebSocket
    └── Async (Wordle-class)   → REST + daily snapshot
```

---

## REST — Leaderboards, Saves, IAP

Plain `fetch()` for almost everything. Don't reach for libraries.

```ts
async function postScore(score: number, name: string) {
  const res = await fetch('/api/score', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ score, name }),
  });
  return await res.json();
}
```

For game backends, **don't** trust the client. Validate:
- Time elapsed since session start (client can fake but adds friction)
- Action counts (clicks, taps) match score plausibility
- HMAC signature with shared secret (still fakeable but raises bar)

For high-stakes leaderboards, **replay validation** on the server is the only
robust approach: client uploads input log, server replays the game.

---

## WebSocket — Custom Realtime

```ts
const ws = new WebSocket('wss://your-server.example/game');

ws.addEventListener('open', () => {
  ws.send(JSON.stringify({ type: 'join', room: 'lobby' }));
});

ws.addEventListener('message', (e) => {
  const msg = JSON.parse(e.data);
  switch (msg.type) {
    case 'state': applyState(msg.state); break;
    case 'event': handleEvent(msg.event); break;
  }
});

ws.addEventListener('close', () => {
  // reconnect with backoff
});

function send(payload: object) {
  if (ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify(payload));
  }
}
```

### Protocol Design

Use a tagged union for messages:

```ts
type ClientMessage =
  | { type: 'join'; room: string }
  | { type: 'input'; tick: number; keys: number }
  | { type: 'leave' };

type ServerMessage =
  | { type: 'state'; state: GameState }
  | { type: 'event'; event: GameEvent }
  | { type: 'error'; code: string };
```

For high-frequency input (>10/s), use binary (`ArrayBuffer` + DataView) instead
of JSON to save bandwidth.

### Reconnection with Backoff

```ts
class ReconnectingSocket {
  private ws: WebSocket | null = null;
  private attempts = 0;

  connect(url: string) {
    this.ws = new WebSocket(url);
    this.ws.addEventListener('open', () => { this.attempts = 0; });
    this.ws.addEventListener('close', () => {
      const delay = Math.min(30_000, 1000 * 2 ** this.attempts);
      this.attempts++;
      setTimeout(() => this.connect(url), delay);
    });
  }
}
```

---

## Colyseus — Authoritative Multiplayer

Server-authoritative state sync with delta encoding. Best fit for room-based
realtime games (party games, .io-style).

```ts
import { Client } from 'colyseus.js';

const client = new Client('wss://your-server.example');
const room = await client.joinOrCreate<RoomState>('battle');

room.onStateChange((state) => {
  // sync sprites to state.players, state.bullets, etc.
});

room.onMessage('hit', (msg) => {
  // play SFX, show hit effect
});

room.send('input', { x: stick.vector.x, y: stick.vector.y });
```

**Why Colyseus over raw WebSocket**:
- State diffing built-in (only changed fields sent)
- Schema-based message format (binary, typed)
- Room lifecycle handled (matchmaking, idle cleanup)

**Tradeoff**: Server is Node.js — requires hosting (Fly.io, Railway, custom VPS).

---

## WebRTC — Peer-to-Peer (No Server)

Use for 1v1 games where matchmaking can be solved externally (shareable URL,
discord bot, etc.).

```ts
const pc = new RTCPeerConnection({
  iceServers: [{ urls: 'stun:stun.l.google.com:19302' }],
});

const dc = pc.createDataChannel('game', { ordered: false, maxRetransmits: 0 });

dc.addEventListener('open', () => { dc.send('hello'); });
dc.addEventListener('message', (e) => { handleMessage(e.data); });

// Signaling (offer/answer exchange) still needs a server or out-of-band channel
const offer = await pc.createOffer();
await pc.setLocalDescription(offer);
// ... exchange SDP via Firebase, shareable URL, etc.
```

### Caveats
- Signaling requires SOMETHING — even if game itself is P2P, you need a way to
  exchange the initial offer/answer
- NAT traversal fails on some networks (~15% of consumer networks need TURN
  servers — STUN alone insufficient)
- Not suitable for > 4 players (mesh becomes O(n²) connections)

---

## Cloud Save Patterns

### Anonymous Persistent ID

```ts
function getOrCreatePlayerId(): string {
  let id = localStorage.getItem('player_id');
  if (!id) {
    id = crypto.randomUUID();
    localStorage.setItem('player_id', id);
  }
  return id;
}

async function saveProgress(progress: SaveData) {
  await fetch('/api/save', {
    method: 'POST',
    body: JSON.stringify({ playerId: getOrCreatePlayerId(), progress }),
  });
}
```

### Last-Write-Wins (Simple)

Server stores the most recent payload per player. Acceptable for single-device
players. Loses data if player plays on two devices simultaneously.

### Version Vectors (Robust)

Each save bumps a `version` counter. Server rejects writes with stale version.
Client merges or prompts user on conflict.

---

## IAP — Web Monetization

For HTML5 games sold via:

- **Itch.io**: built-in payment, you receive a postback
- **Self-hosted with Stripe/Paddle**: standard checkout flow, verify webhook on backend
- **Mobile app wrappers (Capacitor, Cordova)**: native IAP through StoreKit/Play Billing
- **Coil / Web Monetization**: micropayments (niche, low adoption)

**Never** trust the client to confirm purchase. Always verify the webhook
signature server-side before granting entitlements.

---

## Analytics

For HTML5 games, prefer:
- **PostHog** (self-hosted optional, GDPR-friendlier)
- **Plausible** (lightweight, no cookies)
- **Custom endpoint** posting to your own backend

Avoid Google Analytics for game telemetry — it's optimized for marketing
funnels, not gameplay events. The "event volume" for an active gameplay
session can exceed GA's reasonable limits.

---

## Latency Mitigation

For realtime games at 50ms+ latency:

| Technique | Effect |
|-----------|--------|
| Client-side prediction | Apply input locally immediately, reconcile on server confirm |
| Server reconciliation | Server periodically sends authoritative state; client lerps |
| Lag compensation | Server rewinds time for hit detection (FPS-style) |
| Interpolation | Show remote players slightly delayed but smooth |

For a 2D party game, simple client prediction + last-known-position
interpolation handles 200ms latency acceptably.

---

## See Also

- [`../PLUGINS.md`](../PLUGINS.md) — Colyseus, PartyKit
- [`../current-best-practices.md`](../current-best-practices.md) — Testing strategy
