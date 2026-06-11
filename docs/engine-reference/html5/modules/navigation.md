# HTML5 / PixiJS — Navigation & Pathfinding Module

**Last verified:** 2026-06-11

Pathfinding (A*, flow fields), 2D navigation patterns for grid and freeform
spaces. PixiJS has no built-in navigation system — this module documents
common patterns.

---

## Decision Tree

```
Movement style?
├── Grid-based (chess, roguelike)        → A* on grid
├── Tile-based (RTS, top-down)           → A* + path smoothing
├── Continuous (boids, large crowd)      → Flow field
├── Click-to-move (point-and-click)      → A* + Bezier smoothing
└── Free-roam with simple obstacles      → Raycast + steering
```

---

## A* on Grid

Classic A* for grid-based pathfinding:

```ts
interface Node { x: number; y: number; g: number; h: number; f: number; parent?: Node; }

function astar(start: {x:number;y:number}, goal: {x:number;y:number}, grid: number[][]): Node[] {
  const open: Node[] = [];
  const closed = new Set<string>();
  const startNode: Node = { ...start, g: 0, h: manhattan(start, goal), f: 0 };
  startNode.f = startNode.g + startNode.h;
  open.push(startNode);

  while (open.length > 0) {
    open.sort((a, b) => a.f - b.f);
    const current = open.shift()!;
    if (current.x === goal.x && current.y === goal.y) {
      return reconstructPath(current);
    }
    closed.add(`${current.x},${current.y}`);

    for (const [dx, dy] of [[1,0],[-1,0],[0,1],[0,-1]]) {
      const nx = current.x + dx;
      const ny = current.y + dy;
      if (nx < 0 || ny < 0 || nx >= grid[0].length || ny >= grid.length) continue;
      if (grid[ny][nx] === 1) continue;  // wall
      if (closed.has(`${nx},${ny}`)) continue;

      const g = current.g + 1;
      const h = manhattan({ x: nx, y: ny }, goal);
      const node: Node = { x: nx, y: ny, g, h, f: g + h, parent: current };

      const existing = open.find((n) => n.x === nx && n.y === ny);
      if (existing && existing.g <= g) continue;
      if (existing) open.splice(open.indexOf(existing), 1);
      open.push(node);
    }
  }

  return [];  // no path
}

function manhattan(a: {x:number;y:number}, b: {x:number;y:number}): number {
  return Math.abs(a.x - b.x) + Math.abs(a.y - b.y);
}

function reconstructPath(end: Node): Node[] {
  const path: Node[] = [];
  let current: Node | undefined = end;
  while (current) { path.unshift(current); current = current.parent; }
  return path;
}
```

**Use `manhattan` heuristic for 4-direction grids, `octile` for 8-direction.**

### Performance Notes

- Use a **binary heap** for `open` if maps exceed 50×50 (linear `sort()` becomes O(n²) over the search)
- Cache the path; don't re-run A* every frame
- Re-path only when destination changes or path becomes blocked

---

## A* on Hex Grid

Hex requires either offset or axial coordinates. Axial is more elegant:

```ts
type Hex = { q: number; r: number };

function hexDistance(a: Hex, b: Hex): number {
  return (Math.abs(a.q - b.q) + Math.abs(a.q + a.r - b.q - b.r) + Math.abs(a.r - b.r)) / 2;
}

const HEX_NEIGHBORS = [
  { q: 1, r: 0 }, { q: 1, r: -1 }, { q: 0, r: -1 },
  { q: -1, r: 0 }, { q: -1, r: 1 }, { q: 0, r: 1 },
];
```

Reuse the A* skeleton with `hexDistance` and `HEX_NEIGHBORS`.

---

## Flow Fields

For many units chasing the same goal (RTS, tower defense crowds), compute
ONE flow field instead of N A* paths:

```ts
// 1. BFS from goal, computing distance to every walkable tile
function buildIntegrationField(grid: number[][], goal: {x:number;y:number}): number[][] {
  const dist: number[][] = grid.map((row) => row.map(() => Infinity));
  dist[goal.y][goal.x] = 0;
  const queue: {x:number;y:number}[] = [goal];

  while (queue.length > 0) {
    const { x, y } = queue.shift()!;
    for (const [dx, dy] of [[1,0],[-1,0],[0,1],[0,-1]]) {
      const nx = x + dx, ny = y + dy;
      if (nx < 0 || ny < 0 || nx >= grid[0].length || ny >= grid.length) continue;
      if (grid[ny][nx] === 1) continue;
      if (dist[ny][nx] !== Infinity) continue;
      dist[ny][nx] = dist[y][x] + 1;
      queue.push({ x: nx, y: ny });
    }
  }
  return dist;
}

// 2. For each tile, point toward the lowest-distance neighbor
function buildFlowField(dist: number[][]): {dx:number;dy:number}[][] {
  return dist.map((row, y) => row.map((_, x) => {
    let best = { dx: 0, dy: 0, d: dist[y][x] };
    for (const [dx, dy] of [[1,0],[-1,0],[0,1],[0,-1]]) {
      const nx = x + dx, ny = y + dy;
      if (nx < 0 || ny < 0 || nx >= dist[0].length || ny >= dist.length) continue;
      if (dist[ny][nx] < best.d) { best = { dx, dy, d: dist[ny][nx] }; }
    }
    return { dx: best.dx, dy: best.dy };
  }));
}

// 3. Each unit reads its current tile's flow vector
function updateUnit(unit: { x: number; y: number; vx: number; vy: number }, flow: {dx:number;dy:number}[][]) {
  const tx = Math.floor(unit.x / TILE);
  const ty = Math.floor(unit.y / TILE);
  const f = flow[ty]?.[tx];
  if (f) {
    unit.vx = f.dx * SPEED;
    unit.vy = f.dy * SPEED;
  }
}
```

Re-build the field only when the goal moves or the map changes.

---

## Path Smoothing

A* paths are blocky (orthogonal turns). For natural movement, smooth:

```ts
// Catmull-Rom spline through path waypoints
function catmullRom(p0: P, p1: P, p2: P, p3: P, t: number): P {
  const t2 = t * t, t3 = t2 * t;
  return {
    x: 0.5 * (2*p1.x + (-p0.x + p2.x)*t + (2*p0.x - 5*p1.x + 4*p2.x - p3.x)*t2 + (-p0.x + 3*p1.x - 3*p2.x + p3.x)*t3),
    y: 0.5 * (2*p1.y + (-p0.y + p2.y)*t + (2*p0.y - 5*p1.y + 4*p2.y - p3.y)*t2 + (-p0.y + 3*p1.y - 3*p2.y + p3.y)*t3),
  };
}
```

Or use Pixi's `SmoothGraphics` for visual paths.

---

## Click-to-Move

Pattern: convert pointer to world coords → run A* → follow waypoints.

```ts
app.stage.eventMode = 'static';
app.stage.on('pointertap', (e) => {
  const local = world.toLocal(e.global);
  const targetTile = { x: Math.floor(local.x / TILE), y: Math.floor(local.y / TILE) };
  const playerTile = { x: Math.floor(player.x / TILE), y: Math.floor(player.y / TILE) };
  const path = astar(playerTile, targetTile, gridData);
  player.followPath(path);
});
```

For `player.followPath`, advance one waypoint per arrival:

```ts
class Player {
  private path: Node[] = [];
  private waypoint = 0;

  followPath(p: Node[]) {
    this.path = p;
    this.waypoint = 1;  // skip starting tile
  }

  update(dt: number) {
    if (this.waypoint >= this.path.length) return;
    const target = this.path[this.waypoint];
    const tx = target.x * TILE + TILE / 2;
    const ty = target.y * TILE + TILE / 2;
    const dx = tx - this.x;
    const dy = ty - this.y;
    const dist = Math.hypot(dx, dy);
    const step = SPEED * dt;
    if (dist <= step) {
      this.x = tx;
      this.y = ty;
      this.waypoint++;
    } else {
      this.x += dx / dist * step;
      this.y += dy / dist * step;
    }
  }
}
```

---

## Steering Behaviors

For crowds, mixing flow fields with steering:

| Behavior | Vector | Use |
|----------|--------|-----|
| Seek | target - position, normalized * speed | Move toward goal |
| Flee | position - target | Move away |
| Arrival | seek with slowdown radius | Stop smoothly at target |
| Wander | random angle delta, biased forward | Idle / patrol |
| Separation | sum of (position - neighbor) for nearby | Avoid clumping |
| Alignment | average of neighbor velocities | Move with the group |
| Cohesion | toward average position of neighbors | Stay in group |

Combine with weighted sum: `final_velocity = 1.0*seek + 0.3*separation + 0.1*wander`.

---

## Pathfinding Libraries

For non-trivial cases, prefer libraries:

- **pathfinding** (npm) — A*, Dijkstra, JPS on grids. Mature.
- **easystar.js** — A* with weighted tiles. Simpler API.
- **PathFinding.js** (different package) — same name conflict; check the actual package

Most casual mobile games can get by with the inline A* above; libraries shine
when you need JPS (Jump Point Search — 5-10x faster A*) on big maps.

---

## Common Pitfalls

| Symptom | Cause | Fix |
|---------|-------|-----|
| Path runs A* every frame | Re-pathing on every input | Cache path; re-run only on target/map change |
| Long pause at click | A* on big map blocks main thread | Move to a Web Worker; or use JPS |
| Units jitter at waypoint | Threshold for "arrived" too small | Use `dist <= step` not `dist === 0` |
| Diagonal paths illegal | Map only allows orthogonal | Filter diagonal neighbors in A* |

---

## See Also

- [`physics.md`](physics.md) — Collision detection
- [`animation.md`](animation.md) — Smooth movement interpolation
