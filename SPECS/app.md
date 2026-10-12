# Joystick Tester 64 — app spec

Behaviour spec for the Joystick Tester 64 app, per subsystem. Evidence
levels: DOC / SRC / EMU / HW as defined in SPECS/README.md. Runtime
behaviour statements (SPEC-EVT-*, SPEC-CTL-*, SPEC-PNT-*, SPEC-ZP-*,
Q-*) refer to [GUI64dev](https://github.com/gpowerf/GUI64dev) SPECS.

The sketch this spec implements: a GUI64 window titled "Joystick
Tester" with a File and Help menu, two labelled panels (Joy 1,
Joy 2), each showing a fire-button indicator and four direction
markers that light up while the corresponding joystick line is
active.

## SPEC-JT-001 — Purpose — NORMATIVE

A live joystick diagnostic: both C64 controller ports are polled
continuously and their raw switch state is displayed. It runs on
emulators and real C64s; on a real machine it must be usable to
diagnose faulty sticks (stuck lines, dead fire, phantom diagonals).
The app is display-only: it has no interactive controls besides its
menus, and it never writes to the joystick lines.

## SPEC-JT-002 — Window — NORMATIVE (design rev 2)

- Window type `WT_JOYTEST = 50`, title "Joystick Tester", created
  with `GUI_CreateWindowEx` from a static control list.
- Window bits: `BIT_WND_HASMENU | BIT_WND_CANMINIMIZE`
  (same class as Calculator64's window).
- Window 20×11 at (7,2) — height 11 (not 10) leaves a content row of
  white space below the 7×7 boxes in the WIN design, and still one
  after the MAC design's height decrement (user feedback: boxes must
  not sit at the window's bottom edge). Controls (indices fixed,
  referenced by tests):

  | idx | type        | contents                                     |
  | --- | ----------- | -------------------------------------------- |
  | 0   | CT_MENUBAR  | "File", "Help"                               |
  | 1   | CT_FRAME    | "Joy 1" label in top border, (1,1) 7×7       |
  | 2   | CT_JOYPANEL | indicator square for port 1, (2,2) 5×5       |
  | 3   | CT_FRAME    | "Joy 2" label in top border, (12,1) 7×7      |
  | 4   | CT_JOYPANEL | indicator square for port 2, (13,2) 5×5      |

  Port mapping (corrected in rev 5 — was transposed): panel index 2
  reads $DC01 = **port 1** ("Joy 1"), panel index 4 reads $DC00 =
  **port 2** ("Joy 2", the GUI64 UI port). Confusion source: the
  runtime's JoyDecoder reads $DC00 for the UI stick, which *is* port 2
  exactly as the DOC says ("Joystick in Port #2").

- Design (user brief: "a square around each joystick, the button to
  the top left as the classic CX-40 arrangement"): each stick lives
  in a `CT_FRAME` square whose title carries the label (SRC:
  `PaintFrame` prints the string into the top border line; the frame
  string must be ≤ width−2 chars). The indicator square is a custom
  control inside the frame.
- Frames are true 7×7 squares (a top view of a CX-40, per the user's
  brief): `PaintFrame` prints its string from border x+1, so "Joy 1"
  (5 chars) fits within w=7, and the 5×5 indicator panel fills the
  interior exactly (design rev 5 — rev 4 used 8×7 frames which left an
  asymmetric dead column; user feedback "why did you not make them 7×7").
- Below the boxes: h=11 leaves a white content row between the frame
  bottoms and the window border in both designs (design rev 6; user
  feedback that rev 5's h=10 put the boxes at the window edge).

## SPEC-JT-003 — Indicators and glyphs — NORMATIVE (design rev 4)

- Each panel paints a 5×5 cell block in the CX-40 arrangement, the
  cross centred on the middle column/row:

      F . U . .
      . . . . .
      L . . . R
      . . . . .
      . . D . .

  (fire top left — per the user's sketch and the classic CX-40. Rev
  2 used a 4-wide grid; the user rejected it because up/down were not
  aligned with left/right — hence the odd-width centre.)
- **Every cell is painted**: indicators as "keycap" glyphs, the rest
  as solid window-colour tiles (runtime char 4; a space char would
  show the global black background inside the panel).
- **Disc glyphs (user brief: "simple circles that light up; green
  for joystick directions and red for the button")**: 2 glyph chars
  registered via `GUI_RegisterChars` (APP chars 224–225): 224
  direction disc (shared by all four positions — the position
  conveys the direction), 225 fire disc. Solid discs (no OFF bits
  inside the shape → no black holes).
- Colours: directions dim `CL_DARKGREEN` / lit `CL_LIGHTGREEN`;
  fire dim `CL_BROWN` / lit `CL_RED`. (The keycap design of rev 3
  was rejected by the user as "utter shit".)
- Rationale (SRC, char-cell limitation): one cell = one colour; ON
  bits take the cell colour, OFF bits always show the global
  background (black). Therefore a light tile + coloured arrow in one
  cell is impossible; the keycap (coloured chip, black arrow) is the
  cleanest lit rendering, and dim-as-invisible avoids black boxes
  entirely.
- Panels are custom controls (`CT_JOYPANEL = 50`, both instances same
  type), painted by the app's `PaintCtrls` routine registered via
  `GUI_SetPaintCtrlsRoutine` (DOC; SRC: `PaintControl`
  ControlPaintFunctions_win.asm dispatches CT ≥ 50 to `(App_PaintCtrls)`
  with X = control type, paint buffer at $fd/$fe and colour buffer at
  $02/$03). The panel instance is distinguished by `ControlIndex`
  (2 → port 1, 4 → port 2).
- Because a custom type has no standard behaviour, a void
  `CtrlActions` routine (rts) is registered via
  `GUI_SetCtrlActionsRoutine` before the window is created (SRC:
  `App_CtrlActions` is called unconditionally for CT ≥ 50;
  ControlFunctions.asm). Both registration calls happen before
  `GUI_CreateWindowEx`.
- Window colour for the tiles comes from `GUI_GetCSTMWindowColor`
  (DOC), read once at startup into `WndColour`. (A rejected shortcut:
  reading the runtime's `CSTM_WindowClr` directly — internal, not
  API; the API call is one jsr.)
- Paint-size note: the paint routine must write exactly the control's
  WxH cells; writing more overwrites the frame's bottom border
  (caught in EMU during rev 2).

## SPEC-JT-004 — Indicator semantics — NORMATIVE

An indicator is lit if and only if the corresponding raw CIA line of
that port is currently active (low); lit indicators show as coloured
keycaps, unlit ones as dim grey keycaps (always visible). All five indicators are
independent and may be lit in any combination, including diagonals,
all four directions, and all five at once (shorted stick). There is no
debounce, no edge detection, no runtime pressed-state involvement:
the display mirrors the lines. (This is what makes it a diagnostic.)

Consequence for the shared pressed-charset quirk: the app never sets
`BIT_CTRL_ISPRESSED` on any control and has no CT_BUTTON controls, so
Q-PNT-001 and Q-EVT-001 cannot apply to it — see SPEC-JT-110.

## SPEC-JT-005 — Menus — NORMATIVE

- File → Quit (`ID_MENU_FILE = 10`, item "Quit"):
  `GUI_KillCurWindow` + `GUI_Repaint` (Calculator64 pattern). The
  EC_SHUTDOWN handler stops the timer (SPEC-JT-006).
- Help → About (`ID_MENU_HELP = 11`, item "About"): `GUI_ShowMessage`
  with plain text — name/version and author, no icon glyphs (user
  decision; the Calculator64-style logo prefix was tried and removed):
  `!pet "Joystick Tester 64 v0.1"` / `!byte 28` (PETSCII line
  separator) / `!pet " by Guillermo Power",0`.
- Menu behaviour in menu mode only reacts to `EC_LBTNPRESS` in the
  current menu (Calculator64 pattern).

## SPEC-JT-006 — Polling lifecycle — NORMATIVE (final: runtime timer only)

The app polls via the GUI64 timer — `GUI_InitTimer` +
`GUI_StartTimer`, repaint from the timer handler, `GUI_StopTimer` on
`EC_SHUTDOWN` (Sweepy pattern). **The app runs no code of its own in
IRQ context.**

Two earlier architectures were implemented, verified in VICE, and then
**rejected after the THEC64 hardware failure** (HW: crash + taskbar
corruption, 2026-10-11):

1. *Frame-handler heartbeat*: a `GUI_SetFrameHandler` IRQ routine
   polled the ports and wrote `EC2_TIMER` into the runtime's
   `exit_code2` (then believed dead — see SPEC-JT-007). Root cause of
   the HW crash (analysis): the cart's frame-handler call site executes
   with a runtime-owned $01 value; where CHAREN is clear, `$dc00` is
   **charset RAM**, so the handler's `sta $dc00` keyboard-column dance
   wrote `$ff`/`$7f` bytes into the charset — matching the corrupted
   taskbar glyphs in the HW photo. VICE never shows this because its
   frame call site happens to run in a safe banking window.
2. *Self-modifying kick locator*: scanning runtime RAM for the
   dispatch pattern with a self-patching scan; it also self-corrupted
   the app image (772 bytes) and was abandoned for the verify-only
   design, then removed entirely with the frame handler.

Lessons pinned: **no app code in IRQ context** (banking of $D000-$FFF
and even whether `$dc00` addresses the CIA is runtime-owned per $01);
**no hardcoded runtime data addresses across builds**; **no
self-modifying code**; **no ZP indirect pointers across an IRQ** (the
runtime clobbers $5f despite gui64.inc.asm listing it as free — EMU).

Polling at 10 Hz (SPEC-JT-106/107) is ample for a diagnostic; the
initial `TimerHandler` call also primes the mirrors before the first
repaint. `GUI_CreateWindowEx` does **not** paint (EMU), so the app
calls `GUI_RepaintCurWindow` once after creation.

`GUI_RepaintCurWindow` **returns normally** to its caller (EMU), so
both `jsr` uses are safe.

## SPEC-JT-007 — The GUI64 timer: documented behaviour — CONFORMS — DOC, SRC, EMU

The timer fires every 1/10 s, TOD-based (DOC; SRC: `App_StartTimer`
syncs to CIA1 TOD $DC08, the IRQ writes `EC2_TIMER` to `exit_code2`,
the main loop calls the registered `App_TimerHandler` — on the v2.1
WIN cart `exit_code2` = $5CEC, a runtime data variable). Ticks are not
queued: a tick landing while one is pending is lost (SRC), and
delivery may be delayed (DOC). Both are acceptable — the handler
polls the ports and displays the *current* state; the app never counts
ticks.

**History of a wrong conclusion**: an earlier revision declared "the
GUI64 timer is dead" from VICE evidence. The TOD only *appeared*
frozen because every monitor command stops the CPU between register
reads (SPEC-JT-120). With the CPU genuinely running, the TOD ticks and
timer events dispatch (EMU: TimerOn=1, handler fires, panels update
via the timer path alone).

## SPEC-JT-008 — Repaint policy — NORMATIVE

Two repaint triggers:

1. **Initial paint**: `GUI_CreateWindowEx` does **not** paint the
   window (EMU: the screen stays bare until the app repaints; the
   Calculator only appears because `ShowNumber` repaints). After
   creation and mirror initialisation the app calls
   `GUI_RepaintCurWindow` once.
2. **State updates**: the main-loop `TimerHandler` repaints when all
   of:
   - the mirrored state changed since the last repaint (dirty flag),
     or the app has become focused again while dirty (see 3);
   - `ProgramMode == PM_NORMAL` — while a menu or dialog is open the
     update is deferred to a later frame (the About dialog is the
     common case; joystick state may change freely under it);
   - the app's own window is the current window (`CurrentWindow` ==
     the handle stored at creation) — the app must not
     `GUI_RepaintCurWindow` a foreign window.

The repaint is `GUI_RepaintCurWindow` (buffered window repaint,
SPEC-PNT-001; returns to its caller, SPEC-JT-006). There is no lighter
public per-control repaint: `GUI_UpdateControl` only copies the
zero-page control struct back to the heap (SRC: `UpdateControl`,
ControlFunctions.asm) and does not paint.

Rate: at most ~50 repaints/s and only while the state changes. Cost
note: a window repaint takes several frames, during which the runtime
may lose concurrent input events (Q-EVT-001, SPEC-EVT-002) — inherent
to the runtime, not specific to this app; the tester's target user is
holding a joystick, not mousing, so this is acceptable and must be
documented in the README.

## SPEC-JT-009 — Keyboard — NORMATIVE

`EC_KEYPRESS` is ignored beyond calling `GUI_StdWndProc` first. The
app has no keyboard equivalents: it mirrors hardware lines, which a
keyboard cannot drive. (Phantom-key side effects of joystick input are
SPEC-JT-104 in SPECS/inputs.md and must not corrupt the panels.)

## SPEC-JT-010 — Quirk exposure of the GUI64 v2.1 runtime — CONFORMS (by design)

The app intentionally contains **no** runtime-pressed controls, so the
press-lifecycle quirks are not applicable:

| Quirk      | Why N/A                                                            |
| ---------- | ------------------------------------------------------------------ |
| Q-EVT-001  | no `BIT_CTRL_ISPRESSED` state to get stuck                         |
| Q-PNT-001  | no button is ever drawn from the shared pressed charset            |
| Q-CTL-001  | only 5 controls, all with index < 16 — all mouse-scannable         |
| Q-CTL-002  | no use of `GUI_SelectControl` with index ≥ 16 (all indices < 5)    |

Should future versions add interactive controls, these quirks and the
Calculator64 workarounds (see quirks.yaml) become applicable and must
be re-evaluated.

## SPEC-JT-011 — Zero page and scratch — CONFORMS — SPEC-ZP-001

The app uses only documented zero page plus its own variables;
$fb/$fc (and $fd/$fe when painting) are treated as volatile across
GUI64 API calls (SPEC-ZP-001 warning). The sei-protected $DC00 read
window (SPEC-JT-101) may not call any GUI64 API.

## SPEC-JT-012 — Designs — NORMATIVE

`GUI_GetDesign` after creation: WIN design keeps the menubar row in
the window height; MAC design decrements `WindowHeight` (menubar lives
in the system bar). Panels and labels must be checked in both designs
(Calculator64 pattern; DOC).