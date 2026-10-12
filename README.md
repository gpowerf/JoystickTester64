# Joystick Tester 64

A joystick diagnostic app for [GUI64](https://github.com/WebFritzi/GUI64)
on the Commodore 64 — live display of both controller ports' raw switch
state (four directions + fire, two ports), on emulators and real
hardware.

![Joystick Tester 64 running in GUI64](screenshots/joy2_all_lit.png)

Status: **first working build** — the app runs on the GUI64 v2.1
cart in VICE: window, menus, both live panels, port-2 and port-1
state verified end-to-end (see `screenshots/`). The `test_gui64.py`
acceptance suite and the MAC-design check are next, following the
[Calculator64](https://github.com/gpowerf/Calculator64) pattern.

## Features (spec'd, v1)

- Two square "top view" boxes (Joy 1 / Joy 2), CX-40 arrangement:
  fire button top left, direction discs centred around it. Directions
  are green (dark green idle, light green active), fire is red (brown
  idle, red active)
- Port mapping: **Joy 2 = control port 2** — the port GUI64 itself
  uses for the UI ("Joystick in Port #2"), so moving that stick also
  moves the GUI pointer. Joy 1 = control port 1. (A stick in port 2
  controls the desktop; the tester still shows its lines truthfully.)
- Raw-line semantics: diagonals and stuck lines display truthfully —
  it is a diagnostic, not a game port shim
- 10 Hz polling of both ports via the GUI64 timer, buffered repaints
  only on change; no app code runs in IRQ context
- File → Quit, Help → About; standard GUI64 window behaviour
- Works under the WIN and MAC designs of GUI64 2.1

## Building

Requires [ACME](https://sourceforge.net/projects/acme-crossass/) and
`c1541` (from VICE):

    ./build.sh

This produces `joytest.gui` (the app) and `joytest.d64`
(disk image). Inside GUI64, open the disk and run
`joytest.gui`. (The C64 truncates filenames at 16 characters —
keep the app name short so the `.gui` suffix survives.)

## Requirements

- GUI64 v2.1 (cartridge or disk image)
- A mouse in port 1 (or keyboard-driven desktop navigation)
- For emulation: VICE (`x64sc`) with the GUI64 cartridge attached

## Notes on ports (see SPECS/inputs.md)

- GUI64's runtime monitors the port-2 joystick for the UI (see the
  port-mapping note above): moving that stick moves the GUI pointer
  and fire acts as a click. The tester displays the lines regardless.
- Port 1 lines double as keyboard matrix rows: holding a direction
  produces phantom keypresses (classic C64 behaviour), and held keys
  can flicker a direction briefly. Details and limitations are
  spec'd in `SPECS/inputs.md`.

## GUI64 v2.1 quirks worked around

- An earlier build ran a frame handler (code inside the raster IRQ)
  that wrote $DC00; on a THEC64 this corrupted the charset (crash +
  taskbar garbage) — whether `$dc00` addresses the CIA depends on the
  runtime-owned $01 banking, which differs between cart builds. The
  shipped build runs **no code in IRQ context**: all port access
  happens in the timer handler with a short IRQ-blocked read window
  (see SPEC-JT-006 for the full post-mortem).
- The app contains no self-modifying code and writes no hardcoded
  runtime data addresses.

## Credits

- [GUI64](https://github.com/WebFritzi/GUI64) by WebFritzi — the
  desktop the app runs on.
- Developed with AI assistance (specs, code, tests and documentation).

## License

The app's own code, specs and tests are released under the MIT
License — see [LICENSE](LICENSE).

`gui64.inc.asm` is part of the GUI64 project, (c) WebFritzi, licensed
under [CC BY-NC 4.0](https://creativecommons.org/licenses/by-nc/4.0/);
when it is included here for convenience, the repository as a whole is
intended for non-commercial use.