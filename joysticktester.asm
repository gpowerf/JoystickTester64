;---------------------------------------------------------------
; Joystick Tester 64 - a GUI64 app
;
; Live display of both C64 controller ports' raw switch state:
; four direction arrows plus fire per port, lit while the line
; is active. Display-only; polls via the GUI64 timer.
;
; See SPECS/ (app.md, inputs.md) for the behaviour contract.
;
; Build: acme -f cbm -o joysticktester.gui joysticktester.asm
;---------------------------------------------------------------

!source "gui64.inc.asm"

!zone Constants
WT_JOYTEST      = 50            ; app window types start at 50
ID_MENU_FILE    = 10            ; menu IDs start at 10
ID_MENU_HELP    = 11
CT_JOYPANEL     = 50            ; custom control type

; Joystick state bits (active high; CIA lines are active low,
; see SPECS/inputs.md SPEC-JT-101/102)
; PORT MAPPING (verified, was transposed in rev 1-4 builds):
;   $DC00 (CIA1 PRA) = control PORT 2 - the GUI64 UI joystick
;                      (doc: "Joystick in Port #2", right click
;                      with Commodore key + fire)
;   $DC01 (CIA1 PRB) = control PORT 1
; Cross-checks: PEEK(56320)=$DC00 reads port 2; c64-wiki: port 1
; left is hardwired to the CTRL key (CTRL sits on a PRB/row line);
; GUI64's JoyDecoder reads $DC00 for the UI stick.
JST_UP          = 1
JST_DOWN        = 2
JST_LEFT        = 4
JST_RIGHT       = 8
JST_FIRE        = 16

; Registered APP chars (SPECS/app.md SPEC-JT-003)
GL_DIR          = 224           ; direction disc (one glyph for all
GL_FIRE         = 225           ; four directions - position conveys
                                ; the direction, colour the state;
                                ; also the About-box icon dots)

; Control indices (Wnd_JT order; referenced by paint + tests)
IDX_MENUBAR     = 0
IDX_LABEL1      = 1
IDX_PANEL1      = 2
IDX_LABEL2      = 3
IDX_PANEL2      = 4

; GUI64 runtime internals (SPECS/zeropage cross-refs)
CIA1_PRA        = $dc00         ; port 1 lines / key columns
CIA1_DDRB       = $dc03         ; must stay 0 (never written)
; NOTE: this app runs NO code of its own in IRQ context. An earlier
; build used a frame handler that wrote $dc00 from inside the raster
; IRQ; on a cart build whose frame-handler call site sits where $01
; has CHAREN clear (charset mapped, IO out) those writes hit charset
; RAM at $dc00 instead of the CIA - observed as a THEC64 crash with
; taskbar glyphs corrupted to flat $ff/$7f patterns (HW report). All
; port access now happens in the timer handler (GUI64 main loop
; context, IRQ-blocked window) - see SPECS/inputs.md SPEC-JT-101.

*=$b000
AppStart
!zone Start
                cld
                lda #WT_JOYTEST
                sta Param0
                jsr GUI_FindWndByType   ; app already running?
                bcs +                   ; yes: bring window to front
                ldx #<CharList          ; register indicator glyphs
                ldy #>CharList
                lda #2
                jsr GUI_RegisterChars
                ldx #<PaintCtrls        ; custom control routines,
                ldy #>PaintCtrls        ; both BEFORE the window is
                jsr GUI_SetPaintCtrlsRoutine ; created (SPEC-JT-003)
                ldx #<VoidAction
                ldy #>VoidAction
                jsr GUI_SetCtrlActionsRoutine
                ldx #<TimerHandler      ; poll both ports + repaint at
                ldy #>TimerHandler      ; the runtime's 10 Hz timer
                jsr GUI_InitTimer
                jsr GUI_StartTimer
                ldx #<Wnd_JT
                ldy #>Wnd_JT
                jsr GUI_CreateWindowEx
                jsr GUI_GetDesign
                beq ++                  ; WIN design
                dec WindowHeight        ; MAC: menubar not in window
                jsr GUI_UpdateWindow
++              jsr GUI_GetCSTMWindowColor ; tile colour for panel blanks
                sta WndColour
                lda CurrentWindow
                sta WndHandle           ; repaint focus guard
                jsr GUI_SelectControl0  ; menubar: set menu titles
                ldx #<Str_Menubar
                ldy #>Str_Menubar
                lda #2
                jsr GUI_SetCtrlStringList
                lda #IDX_LABEL1         ; frames carry the labels
                jsr GUI_SelectControl
                ldx #<Str_Joy1
                ldy #>Str_Joy1
                jsr GUI_SetCtrlString
                lda #IDX_LABEL2
                jsr GUI_SelectControl
                ldx #<Str_Joy2
                ldy #>Str_Joy2
                jsr GUI_SetCtrlString
                jsr TimerHandler        ; initial poll (sets mirrors)
                jsr GUI_RepaintCurWindow ; GUI_CreateWindowEx does not
                rts                     ; paint (SPECS/app.md SPEC-JT-008)
+               stx Param0              ; window handle from FindWndByType
                jmp GUI_SelectTopWindow

!zone WndProc
JTWndProc       lda wndParam0
                cmp #EC_SHUTDOWN        ; stop the timer before the
                bne +                   ; window dies (Sweepy pattern)
                jmp GUI_StopTimer
+               jsr GUI_StdWndProc      ; must always be called
                lda wndParam1
                bpl +                   ; dialog mode ($ff): ignore
                rts
+
                beq jw_rts              ; normal mode: nothing to do
                jmp jw_menu             ; menu mode
jw_menu         lda wndParam0
                cmp #EC_LBTNPRESS
                bne jw_rts
                jsr GUI_IsInCurMenu
                bcc jw_rts
                jsr GUI_GetCurMenuID
                cmp #ID_MENU_FILE
                beq jw_filemenu
                lda CurMenuItem         ; Help menu
                bne jw_rts
                ldx #<Str_About
                ldy #>Str_About
                jsr GUI_ShowMessage
                rts
jw_filemenu     lda CurMenuItem
                bne jw_rts
                jsr GUI_KillCurWindow   ; File -> Quit
                jmp GUI_Repaint
jw_rts          rts

!zone Timer
;---------------------------------------------------------------
; TimerHandler: runs from the GUI64 main loop at 10 Hz (the
; runtime's TOD-based timer - works in VICE and on real HW; the
; frame-handler heartbeat idea was removed after it crashed a
; THEC64, see the NOTE above and SPECS/app.md SPEC-JT-006).
;
; Polls both ports, then applies the repaint policy per
; SPECS/app.md SPEC-JT-008: only when dirty, only in normal mode,
; only while our own window is current.
;
; Port 2 read (SPEC-JT-101): short IRQ-blocked window - release
; the keyboard columns, read, restore the driver's steady-state
; latch $7f (NOT the read value: pressed bits are 0 and would
; drive columns low). No API calls inside the window.
;---------------------------------------------------------------
TimerHandler
                sei
                lda #$ff
                sta CIA1_PRA            ; release all key columns
                lda CIA1_PRA            ; bits 0-4 = PORT 2 (low=on)
                tax                     ; ($DC00 = PRA = port 2; the
                lda #$7f                ; GUI64 UI joystick lives here)
                sta CIA1_PRA
                cli
                txa
                eor #$ff
                and #%00011111
                cmp Joy2State
                beq +
                sta Joy2State
                lda #1
                sta Dirty
+               lda CIA1_PRA+1          ; PORT 1: direct read, no writes
                eor #$ff                ; ($DC01 = PRB = port 1)
                and #%00011111
                cmp Joy1State
                beq +
                sta Joy1State
                lda #1
                sta Dirty
+               lda Dirty
                beq th_done
                lda ProgramMode
                bne th_done             ; menu/dialog open: defer
                lda CurrentWindow
                cmp WndHandle
                bne th_done             ; not focused: stay dirty
                lda #0
                sta Dirty
                jsr GUI_RepaintCurWindow
th_done         rts

!zone Paint
;---------------------------------------------------------------
; PaintCtrls: paints one CT_JOYPANEL instance into the window
; buffer. X = control type. $fd/$fe points at the control's top
; left char in the paint buffer, $02/$03 in the colour buffer.
; The instance is told apart via ControlIndex (SPEC-JT-003).
; Layout (5x5 chars, CX-40 arrangement - fire top left, cross
; centred on the middle column/row):
;     F . U . .
;     . . . . .
;     L . . . R
;     . . . . .
;     . . D . .
; Indicators are simple discs (CharList): dark green dim /
; light green lit for directions, brown dim / red lit for fire.
; Every cell is painted; the rest are solid window-colour tiles
; (runtime char 4; a space char would show the global black
; background inside the panel).
;---------------------------------------------------------------
PaintCtrls
                lda ControlIndex
                cmp #IDX_PANEL2
                beq pc_p2
                lda Joy1State
                jmp pc_go
pc_p2           lda Joy2State
pc_go           sta pc_state
                ldy #0
                ; ---- row 0: F . U . .
                lda #GL_FIRE
                sta pc_gbase
                lda #CL_RED
                sta pc_gcl
                lda #JST_FIRE
                jsr PPGlyph
                jsr PPBlank
                lda #GL_DIR
                sta pc_gbase
                lda #CL_LIGHTGREEN
                sta pc_gcl
                lda #JST_UP
                jsr PPGlyph
                jsr PPBlank
                jsr PPBlank
                jsr PCRow
                ; ---- row 1: . . . . .
                jsr PPBlank
                jsr PPBlank
                jsr PPBlank
                jsr PPBlank
                jsr PPBlank
                jsr PCRow
                ; ---- row 2: L . . . R
                lda #GL_DIR
                sta pc_gbase
                lda #CL_LIGHTGREEN
                sta pc_gcl
                lda #JST_LEFT
                jsr PPGlyph
                jsr PPBlank
                jsr PPBlank
                jsr PPBlank
                lda #JST_RIGHT
                jsr PPGlyph
                jsr PCRow
                ; ---- row 3: . . . . .
                jsr PPBlank
                jsr PPBlank
                jsr PPBlank
                jsr PPBlank
                jsr PPBlank
                jsr PCRow
                ; ---- row 4: . . D . .
                jsr PPBlank
                jsr PPBlank
                lda #JST_DOWN
                jsr PPGlyph
                jsr PPBlank
                jsr PPBlank

; advance to the next buffer row, reset column offset
PCRow           jsr GUI_AddBufWidthToFD
                jsr GUI_AddBufWidthTo02
                ldy #0
                rts

; write one cell: A = char, X = colour
PPCell          sta ($fd),y
                txa
                sta ($02),y
                iny
                rts

; select one indicator cell: A = state bit mask,
; pc_gbase = glyph char. Colour: pc_gcl = lit colour, dim colour
; in pg_dimcl. Lit char = dim char (same disc), only the colour
; changes.
PPGlyph         sta pc_gmask
                lda pc_gcl
                sta pg_litcl
                lda pc_gmask
                and pc_state
                bne +
                lda pc_gbase        ; dim: disc in dim colour
                ldx #CL_DARKGREEN   ; (dirs); fire overrides below
                cmp #GL_FIRE
                bne pg_out
                ldx #CL_BROWN
pg_out          jmp PPCell
+               lda pc_gbase        ; lit: disc in lit colour
                ldx pg_litcl
                jmp PPCell

; write a solid tile cell (runtime char 4) in the window colour
PPBlank         lda #4
                sta ($fd),y
                lda WndColour
                sta ($02),y
                iny
                rts

VoidAction      rts

!zone Data
pc_state        !byte 0
pc_gbase        !byte 0
pc_gcl          !byte 0
pc_gmask        !byte 0
pg_litcl        !byte 0
Joy1State       !byte 0
Joy2State       !byte 0
Dirty           !byte 0
WndHandle       !byte $ff       ; invalid until window exists
WndColour       !byte 0         ; window colour (GUI_GetCSTMWindowColor)

; Glyphs for APP chars 224-225 (SPECS/app.md SPEC-JT-003).
; Panel indicators: solid discs (user brief: "simple circles that
; light up") - no OFF bits inside the shape, so no black holes.
;   224 direction disc - dark green dim, light green lit
;   225 fire disc      - brown dim, red lit
CharList
                ; 224 direction disc
                !byte $3c,$7e,$ff,$ff,$ff,$ff,$7e,$3c
                ; 225 fire disc
                !byte $3c,$7e,$ff,$ff,$ff,$ff,$7e,$3c

Str_Title       !pet "Joystick Tester",0
Str_Joy1        !pet "Joy 1",0
Str_Joy2        !pet "Joy 2",0

; Window: type, bits, x, y, width, height, title, wndproc
; Frames are square top views of a CX-40 stick (7x7 outer); the
; 5x5 indicator panel fills the interior exactly. CT_FRAME prints
; its string from border x+1, so "Joy 1" (5 chars) fits in w=7.
; h=11: two content rows below the frame boxes (WIN), one after the
; MAC height decrement - the frame must not touch the window edge.
Wnd_JT          !byte WT_JOYTEST, %00100001, 7, 2, 20, 11
                !word Str_Title, JTWndProc
; Controls (terminated by zero byte):
                ;0: menubar (x/y = pointer to menu list)
                !byte CT_MENUBAR, <MenuList, >MenuList, 0, 0
                !pet 0
                ;1: frame + label Joy 1 (CT_FRAME paints its string
                ;   into the top border line, char 38 notch)
                !byte CT_FRAME, 1, 1, 7, 7
                !pet "Joy 1",0
                ;2: panel port 1 (fills frame 1's interior exactly)
                !byte CT_JOYPANEL, 2, 2, 5, 5
                !pet 0
                ;3: frame + label Joy 2
                !byte CT_FRAME, 12, 1, 7, 7
                !pet "Joy 2",0
                ;4: panel port 2
                !byte CT_JOYPANEL, 13, 2, 5, 5
                !pet 0
                ; terminating zero byte
                !byte 0

; Menus
MenuList        !word Menu_File, Menu_Help
Str_Menubar     !pet "File",0,"Help",0
; Format: ID, max string len, item count, string list
Menu_File       !pet ID_MENU_FILE,4,1,"Quit",0
Menu_Help       !pet ID_MENU_HELP,5,1,"About",0

Str_About       !pet "Joystick Tester 64 v0.1"
                !byte 28                ; PETSCII line separator
                !pet " by Guillermo Power",0