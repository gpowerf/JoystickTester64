# Joystick Tester 64 — test plan

Acceptance suite: `test_gui64.py`, built on
[GUI64dev](https://github.com/gpowerf/GUI64dev)'s `gui64test` harness
(VICE `x64sc`, remote monitor, shipped GUI64 v2.1 cart), following the
Calculator64 pattern. Set `GUI64_CART` if the cart is not at the
default path. Injection mechanisms and monitor semantics (CPU stops
between commands; `g` to resume) per SPEC-JT-120.

Assertions on lit/unlit indicators read the screen buffer chars and
colours at the panel cell positions (SPEC-JT-003 glyph indices). The
general latency allowance is ≤ 300 ms (polling at the 10 Hz timer,
SPEC-JT-106). Panel↔port mapping: left box "Joy 2" = $DC00 (port 2,
the GUI64 UI port), right box "Joy 1" = $DC01 (port 1) — SPEC-JT-101/
102.

## Infrastructure

| ID         | Pins                                                                 |
| ---------- | -------------------------------------------------------------------- |
| T-INF-001  | Boot cart + harness connects; runtime write-site patches apply        |
| T-INF-002  | Port-1 injection end-to-end: JoyDevice2="0", DDRB $DC03=$1F + $DC01 latch poke + `g` → app mirror shows the state, release clears it |
| T-INF-003  | Port-2 injection: breakpoint loop on the timer handler's `LDA $DC00` → injected state captured by the app mirror |
| T-INF-004  | Dispatch kick (test-only): `exit_code2` ($5CEC on the v2.1 WIN cart) = $01 → one TimerHandler pass (dirty flag cleared, repaint) |

## Window and static UI

| ID         | Pins                                                                 |
| ---------- | -------------------------------------------------------------------- |
| T-UI-001   | App loads, window paints (initial repaint after creation!), title/menubar present, 5 controls in heap |
| T-UI-002   | Idle display: all markers dim (dark green discs / brown fire), frames + labels intact |
| T-UI-003   | Second launch selects the existing window (single instance)           |
| T-UI-004   | MAC-design cart: height adjusted, layout intact (needs mac cart)      |

## Port 2 panel (left box, "Joy 2" — $DC00)

| ID         | Pins                                                                 |
| ---------- | -------------------------------------------------------------------- |
| T-JY2-001  | up held → up disc lit ≤ 300 ms; release → dim again                   |
| T-JY2-002  | fire held → fire disc lit; release → dim                              |
| T-JY2-003  | up+left held → both discs lit simultaneously (raw-line semantics)     |
| T-JY2-004  | runtime co-opting observed and tolerated: pointer/menu reaction to port-2 input does not corrupt the panels (SPEC-JT-103) |
| T-JY2-005  | mouse still works while the app polls (the timer handler's dance leaves no side effects) |

## Port 1 panel (right box, "Joy 1" — $DC01)

| ID         | Pins                                                                 |
| ---------- | -------------------------------------------------------------------- |
| T-JY1-001  | down held → down disc lit ≤ 300 ms; release → dim                     |
| T-JY1-002  | fire held → fire disc lit; release → dim                              |
| T-JY1-003  | right+down held → both discs lit                                      |
| T-JY1-004  | phantom-key storm (SPEC-JT-104.1) while a direction is held: panels stay correct, app does not act on the key events |

## Event integration

| ID         | Pins                                                                 |
| ---------- | -------------------------------------------------------------------- |
| T-EVT-001  | Menu open while state changes → no repaint under the menu; after menu closes, panel catches up ≤ 300 ms (SPEC-JT-008.2) |
| T-EVT-002  | About dialog open + state change → deferred; after OK, catches up     |
| T-EVT-003  | Window unfocused + state change → no repaint of foreign window; on refocus panel is correct (dirty flag, SPEC-JT-008.3) |
| T-EVT-004  | File → Quit closes the window; timer stopped (EC_SHUTDOWN path) — no further panel updates after close |
| T-EVT-005  | Burst of rapid state changes → final state correct, no charset corruption or stale glyphs (Q-PNT-001 stays N/A, SPEC-JT-004) |

## Hardware session (HW evidence, not automated)

Planned checks against a real C64/THEC64: real stick on port 2
(directions, fire, diagonals, stuck-line diagnosis — the box labelled
"Joy 2" reacts AND the GUI pointer moves: SPEC-JT-103), stick in
port 1 with mouse swapped out ("Joy 1" reacts, desktop does not),
unconnected port stability (SPEC-JT-105), key/joystick cross-effects
(SPEC-JT-104), no visible mouse degradation from the timer handler's
$DC00 dance. Record results as HW evidence lines in the SPECS files.