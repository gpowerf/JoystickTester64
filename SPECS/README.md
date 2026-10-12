# Joystick Tester 64 — specs

Behaviour specs for the Joystick Tester 64 app, written in the style
of [GUI64dev](https://github.com/gpowerf/GUI64dev)'s runtime SPECS.
Every statement carries an ID (SPEC-JT-nnn) and an **evidence level**:

| Level | Meaning                                              |
| ----- | ---------------------------------------------------- |
| DOC   | stated in the GUI64 API reference (Apps folder)      |
| SRC   | read in the runtime source (Code/v2.1 on GitHub)     |
| EMU   | verified in VICE against the shipped cart            |
| HW    | observed on real hardware / THEC64 (pending session) |

NORMATIVE statements define the app's required behaviour; CONFORMS
statements record how the app sits on documented/observed runtime
behaviour; TEST INFRA statements pin the emulator-only test
machinery.

| File         | Contents                                              |
| ------------ | ----------------------------------------------------- |
| app.md       | window, panels, menus, timer, repaint, quirk exposure |
| inputs.md    | CIA reading, runtime co-opting of the ports, injection |
| testplan.md  | T-* acceptance tests (test_gui64.py) + HW session plan |

Cross-references: runtime behaviour statements SPEC-EVT-*/SPEC-CTL-*/
SPEC-PNT-*/SPEC-ZP-* and quirk IDs Q-* live in GUI64dev
(`SPECS/`, `quirks.yaml`). Runtime findings made while writing these
specs (timer dispatch unconditional; JoyDecoder reads $DC00; CIA
injection semantics) are recorded here with SRC/EMU evidence and can
be upstreamed into GUI64dev's SPECS once confirmed in the app's test
suite.