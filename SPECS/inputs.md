# Joystick Tester 64 — input spec

How the app reads the two controller ports, how the GUI64 runtime
co-opts them, and how tests inject synthetic joystick state. Evidence
levels: DOC / SRC / EMU / HW (see SPECS/README.md).

C64 hardware facts (DOC, standard references; **corrected** — the
first revision of this file had the two ports swapped, which
transposed the app's panels): joystick **port 2** lines are CIA1 data
port A ($DC00) bits 0–4, joystick **port 1** lines are CIA1 data port
B ($DC01) bits 0–4, all **active low** (bit order: 0 = up, 1 = down,
2 = left, 3 = right, 4 = fire). $DD00 is CIA2 (VIC bank / serial),
*not* a joystick register. Port 2 lines double as keyboard matrix
columns (driven by writes to $DC00, DDR $DC02 = $FF), port 1 lines
double as keyboard matrix rows (read side, DDRB $DC03 = 0).

Three independent confirmations of the mapping: PEEK(56320) = $DC00
reads port 2; c64-wiki's keyboard-matrix note that port 1's *left*
direction is hardwired to the CTRL key (CTRL sits on a PRB/row line);
and the GUI64 documentation "Joystick in Port #2 (right click with
Commodore key + fire)" with the runtime's JoyDecoder reading $DC00 —
the UI joystick is port 2 (HW: THEC64, user observed the pointer
moving while the panel labelled "Joy 1" reacted — rev 1–4 bug).

## SPEC-JT-101 — Port 2 read: masked, column-release dance — NORMATIVE

The app reads port 2 ($DC00) in its timer handler (GUI64 main-loop
context, 10 Hz), in a short IRQ-blocked window (SRC: the GUI64 IRQ
driver rewrites $DC00 every frame — keyboard scan and mouse driver —
so unmasked reads race the IRQ):

        sei
        lda #$ff
        sta $dc00      ; release all keyboard columns
        lda $dc00      ; bits 0-4 = joystick state (low=on)
        tax
        lda #$7f
        sta $dc00      ; restore the driver's steady-state latch
        cli
        txa

- The window spans ~20 cycles and contains no API calls
  (SPEC-ZP-001 / SPEC-JT-011). It is atomic against the runtime's
  own $DC00 traffic (both the runtime's reads and the app's happen
  with IRQs blocked).
- **Never touch $DC00 from IRQ context** (no frame handler): whether
  `$dc00` addresses the CIA at all depends on $01's CHAREN bit at
  that moment, which is runtime-owned and build-dependent. HW: the
  THEC64 crash + glyph corruption (SPEC-JT-006 NOTE) is attributed to
  exactly this — an earlier build's frame handler wrote $DC00 inside
  the raster IRQ.
- Restore value #$7f is the IRQ driver's own steady-state latch (SRC:
  the keyscan's final row pattern and `Mouse`'s post-`GetClicks` write,
  KeyMouseJoy.asm) so the POT mux bits 6/7 end up exactly as the
  runtime left them. Restoring the read value instead would drive
  pressed bits (0s) low across the whole keyboard column set.
- Bits 5–7 are masked off (pot-select/paddle lines, irrelevant here).
- Evidence for the race: SRC `keyscan`/`Mouse` write $DC00
  (KeyMouseJoy.asm); EMU: `8D 00 DC` write sites located in the
  shipped cart's driver RAM ($0400–$0FFF), e.g. $0666, $0691.

## SPEC-JT-102 — Port 1 read: direct, no writes — NORMATIVE

The app reads $DC01 (port 1) directly and masks bits 0–4. It
**never writes** $DC01 or DDRB ($DC03): rows are inputs (DDRB = 0 on
stock setups, SRC: nothing in the GUI64 v2.1 source writes $DC03), so
the read reflects the pins and there is no scan-race for the app to
mask (the keyboard scan drives columns, not rows). EMU: static
readback of $DC01 is stable while the CPU runs (injection test
T-INF-002).

## SPEC-JT-103 — Port 2 is the UI joystick: the runtime co-opts it — CONFORMS — DOC, SRC, EMU

The GUI64 runtime monitors the port-2 joystick *as an alternative
mouse* (DOC: "Joystick in Port #2 (right click with Commodore key +
fire)"):

- SRC: `JoyDecoder` reads **$DC00** = port 2 (KeyMouseJoy.asm:718) and
  decodes directions and fire every frame (`jsr Joystick` in
  IRQ_win.asm:53). EMU: the shipped cart's driver contains this exact
  decoder at $0AC9 (`lda $DC00` + shift-decode chain, disassembled).
  (An earlier revision of this file called the source comments "stale"
  — that was wrong; they were correct and my port mapping was not.)
- SRC: port-2 fire feeds `GetClicks` → `IsLBtnPressed` ($7d) /
  `bFirePressed` ($7e); DOC: `GUI_GetLBtnFirePressed` reports "left
  mouse button and joystick fire button".

Consequences the app accepts (and the README must document):

- With a joystick in port 2, pressing fire acts as a GUI right click
  (Commodore key + fire per DOC; fire alone = left click), and
  directions move the GUI pointer. The tester still displays the raw
  lines truthfully; the desktop reacting is runtime behaviour, not a
  fault. HW: THEC64 user observed exactly this (pointer moved while
  the panel reacted) — which exposed the rev 1–4 label transposition.
- With the usual mouse in port 1, panel 1 shows the mouse's button
  line (fire = left button); direction lines stay high (an 1351-style
  mouse does not drive them).

## SPEC-JT-104 — Port 1 crosses the keyboard matrix — CONFORMS (inherent) — SRC; EMU/HW pending

Port 1 lines are keyboard *rows*. Two inherent cross-effects:

1. Direction held → the row is pulled low → the runtime's keyboard
   scan sees phantom keys in every column while the direction is
   held; GUI64 will receive `EC_KEYPRESS` events. The app ignores
   keys (SPEC-JT-009); panels are unaffected. Classic C64 behaviour.
2. Keys held while a scan column is driven → the connected row reads
   low → a *single* $DC01 sample may show phantom directions. At 10 Hz
   sampling this can flicker an arrow while keys are pressed.
   Mitigation deferred (future: 2-of-N debounce); document in README.

Both effects are SRC-level matrix reasoning; pin down EMU/HW evidence
in tests T-JY1-004 and a hardware session before claiming them.

## SPEC-JT-105 — Unconnected ports — CONFORMS — EMU; HW pending

EMU: with no control-port device attached, all port lines read high:
an unconnected port displays all-dim, deterministically. HW: floating
lines can flicker on some machines (no pull-ups on these lines);
pin down during the hardware session — if flicker is observed, a
hold-time ("latch last lit state for n ticks") display option is the
candidate fix, out of scope for v1.

## SPEC-JT-106 — Poll cadence — CONFORMS — DOC, EMU (final)

Polling runs from the runtime's **10 Hz timer** (TOD-based, working
both in VICE and on real hardware) inside the GUI64 main loop. The
interim frame-handler heartbeat (~50 Hz) was **removed** (HW: THEC64
crash — see SPEC-JT-006 and the NOTE in the source; no app code in
IRQ context). State-change latency is one to two timer ticks
(≤ 200 ms), within the test allowance of 300 ms.

## SPEC-JT-107 — The app is display-only — NORMATIVE

The app never writes $DC00 outside SPEC-JT-101's read dance and never
writes $DC01/$DC03/$DD00. It does not use GUI_MapOutIO/GUI_MapInIO
(charset registration goes through GUI_RegisterChars, which maps IO
internally — SRC: `App_RegisterChars`). No poke of the CIA can leak
into the desktop.

## SPEC-JT-110 — Quirk exposure (input side) — CONFORMS (by design)

- The masked port-1 read (SPEC-JT-101) is unaffected by the runtime's
  own $DC00 traffic because it is atomic against the IRQ (sei/cli) —
  unlike the runtime's own unmasked reads.
- Q-EVT-001 (lost input events during repaints): the runtime may drop
  a mouse release while the tester repaints after a state change
  (SPEC-JT-008 rate note). The app has no pressed-state to get stuck;
  the loss, if it hits the user's next click, is runtime behaviour
  reported upstream (GUI64 issue #22) — nothing for this app to work
  around.

## SPEC-JT-120 — EMU test injection mechanisms — TEST INFRA — EMU (verified end-to-end)

The gui64test harness drives VICE's remote monitor. **Monitor
semantics matter**: every monitor command (`m`, `r`, `>`, `d`, ...)
*stops* the CPU; the emulator only runs after an explicit `g` and
until the next stop-causing command. Any test that pokes state and
then wants the guest to react **must issue `g` after the pokes** —
observation windows are the sleeps *between* a `g` and the next
command. (Failure to resume silently fakes "the guest did nothing";
this cost most of a debugging day and is pinned here for posterity.)

- **Port 1 (state injection):** poke DDRB $DC03 = $1F, then $DC01 =
  complement of the desired bits 0–4, then `g`. CIA readback then
  returns the latch for bits 0–4 deterministically (EMU: readback
  254/251 for latches $FE/$FB). Restore $DC03 = 0 afterwards.
  - `JoyDevice2` (VICE resource) must be **"0"** (none): a control
    port device on port 2 drives the $DC00 *pins* every frame and the
    CPU then reads pin state, not the injected latch. Set it via
    `resset "JoyDevice2" "0"` (both arguments quoted; the value must
    be a string). Note the CPU may still observe device-driven pin
    values while a device is attached — e.g. the 1351 mouse's
    extra-button protocol constantly drives $DC01 with $14 in this
    configuration.
  - Side effect: the keyscan sees phantom keys (SPEC-JT-104.1);
    tests that must not see keyboard side effects can NOP the
    keyscan's `sta exit_code` write site (byte pattern
    `A9 0A 85 39` in driver RAM), mirroring patch_runtime.
- **Port 2 (window injection):** the app re-drives $DC00 inside its
  read dance, so the latch cannot be pre-loaded. Set a monitor
  breakpoint on the timer handler's `LDA $DC00` instruction (located
  by the dance byte pattern `A9 FF 8D 00 DC AD 00 DC 8D 00 DC` in the
  loaded app), and on each hit poke $DC00 = complement of the desired
  state, then `g` — the read captures the injected value. EMU:
  verified end-to-end with the earlier (IRQ) handler — 40
  hit/poke/resume cycles held up+left. With the timer handler the
  dance executes at 10 Hz, so a held direction needs a few breakpoint
  cycles (~2-3) rather than ~40.
- **Dispatch kick (synthetic dirty/repaint tests):** the runtime's
  `exit_code2` is **$5CEC** on the v2.1 WIN cart (runtime data area,
  not zero page; found via the Data_win neighbourhood: OldMenuItem
  $5CEA, DialogResult $5CED, ModalAddress $5CEE; confirmed by the main
  loop's `ldx $5CEC / jsr App_TimerHandler` at $0419). Writing $01
  there dispatches one timer-handler pass. The app itself no longer
  writes this address at all (the kick/frame-handler architecture was
  removed — SPEC-JT-006); this remains a test-only mechanism and is
  cart-build-specific (verify the pattern first).

These mechanisms are emulator-only; real-hardware testing needs no
injection (the joysticks are real).