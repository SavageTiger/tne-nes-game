.segment "HEADER"
.byte "NES"
.byte $1a
.byte $02 ; 2 * 16KB PRG ROM
.byte $01 ; 1 * 8KB CHR ROM
.byte %00000001 ; mapper and mirroring
.byte $00
.byte $00
.byte $00
.byte $00
.byte $00, $00, $00, $00, $00 ; filler bytes

.segment "ZEROPAGE" ; LSB 0 - FF

.segment "STARTUP"
Reset:
    SEI ; Disables all interrupts
    CLD ; disable decimal mode

    ; Reset the stack register
    LDX #$FF
    TXS ; Transfer X (255) to Stack Register
    INX ; Reset to 0

    ; Disable draw calls (disable PPU)
    LDX #$00
    STX $2000
    STX $2001

    ; Disable sound IRQ (prevent sound from placing)
    LDX #$40
    STX $4017

    ; Disable PCM channel (prevent sound from playing)
    LDX #$00
    STX $4010

    ; Wait for the first VBlank (PPU is currently not drawning)
: ; Anonymous label
    BIT $2002
    BPL :- ; Branch if positive back to anonymous label

    ; Clear all 2KB of memory mem
    LDX #$00
    TXA ; X -> A register
CLEARMEM:
    STA $0000, X
    STA $0100, X
    STA $0200, X
    STA $0300, X
    STA $0400, X
    STA $0500, X
    STA $0600, X
    STA $0700, X
    INX
    BNE CLEARMEM ; When X is 00 BNE = true due to the Zero flag being 0

    ; Create Memory for the PPU
    LDY #$FF
    TYA ; Y -> A register
PPUMEM:
    STA $0200, X
    INX
    BNE PPUMEM ; When X is 00 BNE = true due to the Zero flag being 0

    ; Wait for the second VBlank (PPU is still not drawning)
: ; Anonymous label
    BIT $2002
    BPL :- ; Branch if positive back to anonymous label

    ; Tell the PPU where its memory is
    LDA #$02
    STA $4014
    NOP
    NOP

    ; Give the beginning location of where to write PPU data
    LDA #$3F
    STA $2006
    LDA #$00
    STA $2006

    LDA #$80 ; Set the initial tree counter (for left 2)
    STA $a8
    LDA #$C0 ; Set the initial tree counter (for right 1)
    STA $a7
    LDA #$30 ; Set the initial tree counter (for right 2)
    STA $a6

LoadPalettes:
    LDA PaletteData, X
    STA $2007 ; $3F00, $3F01, $3F02 => $3F1F
    INX
    CPX #$20
    BNE LoadPalettes    

LoadBackground:
	LDA $2002
	LDA #$20
	STA $2006
	LDA #$00
	STA $2006
	LDA #<Background
	STA $10
	LDA #>Background
	STA $11
	LDY #$00
	LDX #$04
LoadBackgroundInner:
	LDA ($10), Y
	STA $2007
	INY
	BNE LoadBackgroundInner
	INC $11
	DEX
	BNE LoadBackgroundInner

    ; Enable interrupts
    CLI

    LDA #%10010000   ; enable NMI, sprites from Pattern Table 0, background from Pattern Table 1
    STA $2000

    LDA #%00011110   ; enable sprites, enable background, no clipping on left side
    STA $2001

Init:
    JSR movePickup
    JSR hidePickup
    JSR resetDrawRoadLine1
    JSR resetDrawRoadLine2
    JSR resetDrawRoadLine3
    JSR resetDrawRoadLine4
    JSR resetCarPosition
    
Loop:
    JMP Loop

PaletteData:
  .byte $0a,$2d,$20,$10,$0f,$0f,$0f,$0f,$0f,$0f,$0f,$0f,$0f,$0f,$0f,$0f ; Background palette
  .byte $0a,$08,$28,$38,$0f,$30,$30,$08,$0f,$1c,$1a,$2a,$0f,$1c,$09,$1b ; Sprite palette


NMI:    
    LDA #$02 ; copy sprite data from $0200 => PPU memory for display
    STA $4014

    ; Skip rendinging gameplay items when secret screen is visible
    LDA $25
    CMP #$01
    BEQ :+

    JSR readController
    JSR renderCar    

    JSR drawRoadLine1
    JSR drawRoadLine2
    JSR drawRoadLine3
    JSR drawRoadLine4

    JSR renderTreeLeft1
    JSR renderTreeLeft2
    JSR renderTreeRight1
    JSR renderTreeRight2

    JSR renderPickup
    JSR detectCollision
:

    ;;This is the PPU clean up section, so rendering the next frame starts properly.
    LDA #%10010000   ; enable NMI, sprites from Pattern Table 0, background from Pattern Table 1
    STA $2000
    LDA #%00011110   ; enable sprites, enable background, no clipping on left side
    STA $2001

    JSR roadScroll

    RTI

removeAllChars:
    LDX #$00
    LDY #$00
:    
    LDA #$00
    STA $0230, X
    STA $0231, X
    STA $0232, X
    STA $0233, X
    INX
    INX
    INX
    INX
    INY
    CPY #$80
    BMI :-
    RTS

secretScreen:
    ; Clear the road if we are on the secret screen
    LDA $25
    CMP #$00
    BEQ :+
    JSR removeAllChars
    JSR renderSecret
    LDA #$FF
    STA $2005
    LDA #$50
    STA $2005
:
    RTS

renderSecret:
    LDY $38
    INY
    STY $38

    LDY #$00
    STY $39
    LDY $38
    STY $30
    LDY #$90
    STY $29
    LDY #$40
    STY $31
:
    LDA $31
    STA $0230, X
    LDA $29
    STA $0231, X
    LDA #$01
    STA $0232, X
    LDA $30
    STA $0233, X
    LDY $29

    LDY $29
    INY
    STY $29

    LDY $39
    INY
    STY $39

    LDY $30
    INY
    INY
    INY
    INY
    INY
    INY
    INY
    INY
    STY $30

    LDY $31
    INY
    INY
    INY
    INY
    INY
    INY
    INY
    INY
    STY $31

    INX
    INX
    INX
    INX

    LDA $39
    CMP #$10
    BNE:-

    RTS

roadScroll:
    JSR secretScreen
    LDA $25
    CMP #$01
    BEQ skipScroll

    LDY $01
    CPY #$B0
    BCS :+
    LDA #$d7
    STA $01
:
    LDA #$00
    STA $2005
    LDX $01
    DEX
    TXA
    STA $01
    STA $2005
skipScroll:
    RTS

resetCarPosition:
    LDA #$D0
    STA $0270
    LDA #$D8
    STA $0274

    LDA #$70
    STA $0273
    LDA #$70
    STA $0277
    RTS

decreaseFrameTimer:
    LDA $08
    CMP #$00
    BEQ :+
    LDX $08
    DEX
    STX $08
:
    RTS

renderPickup:
    JSR decreaseFrameTimer

    ; Skip if frame timer had not expired yet
    LDA $08
    CMP #$00
    BNE :+

    LDX $0b
    INX
    INX
    TXA
    STA $0b
    STA $0278

    LDA #$35
    STA $0279
    LDA #$00
    STA $027a

    JSR hideOnMiss

:
    RTS

hideOnMiss:
    LDA $0b
    CMP #$FE
    BNE :+
    LDA #$00
    STA $0b
    JSR resetScore
    JSR hidePickup
:
    RTS

movePickup:
    ; Must be more then 60 and less then A0
    JSR updateRandom

    LDA $a0

    CMP #$60
    BPL :+
    JSR movePickup
    RTS
:
    CMP #$A0
    BMI :+
    JSR movePickup
    RTS
:

    STA $03
    STA $027b    

    RTS

incrScoreCount:
    ; Skip if frame timer for the pickup has not expired yet
    LDA $08
    CMP #$00
    BNE :+

    ; Incr score
    LDX $20
    INX
    STX $20

    CPX #$0A
    BCC :+
    LDX #$00
    STX $20
    LDX $21
    INX
    STX $21

:
    JSR renderScore
    JSR checkSecret
    RTS

resetScore:
    LDA #$00
    STA $20
    STA $21
    JSR renderScore
    RTS

checkSecret:
    LDA $21
    CMP #$02
    BMI :+
    LDX #$01
    STX $25
:
    RTS

renderScore:
    LDA #$25
    STA $027c
    LDA $21
    STA $027d
    LDA #$01
    STA $027e
    LDA #$20
    STA $027f

    LDA #$25
    STA $0280
    LDA $20
    STA $0281
    LDA #$01
    STA $0282
    LDA #$28
    STA $0283

    RTS

hidePickup:
    LDA #$00
    STA $0278

    LDA #$00
    STA $0b

    LDA #$90
    STA $027b

    LDA #$30
    STA $027a

    JSR updateRandom
    LDA $a0
    STA $08

    JSR movePickup
:
    RTS

detectCollision:
    ; 0270 = Car Y
    ; 0273 = Car X
    ; 0278 = Pickup Y
    ; 027b = Pickup x  
    LDX $0270
    CPX $0278
    BPL :+

    LDX $0270
    INX
    INX
    INX
    INX
    CPX $0278
    BCC :+

    LDX $0273
    DEX
    DEX
    DEX
    DEX
    DEX
    DEX
    CPX $027b
    BPL :+

    LDX $0273
    INX
    INX
    INX
    INX
    INX
    CPX $027b
    BCC :+

    JSR incrScoreCount
    JSR hidePickup

:
    RTS


renderCar:
    LDA $0270
    STA $0270
    LDA #$33
    STA $0271
    LDA #$03
    STA $0272
    LDA $0273
    STA $0273

    LDA #$43
    STA $0275
    LDA #$03
    STA $0276
    LDA $0277
    STA $0277

    RTS

readController:
    ; Latch the controller
    LDA #$01
    STA $4016
    LDA #$00
    STA $4016       ; tell both the controllers to latch buttons

    ; Read buttons on controller A $4016
    LDA $4016       ; READ A (ignore)
    LDA $4016       ; READ B (ignore)
    LDA $4016       ; READ Select (ignore)
    LDA $4016       ; READ Start (ignore)

    LDA $4016       ; READ Up
    AND #%0000001
    BEQ :+
    JSR moveCarUp
    :

    LDA $4016       ; READ Down
    AND #%0000001
    BEQ :+
    JSR moveCarDown
    :

    LDA $4016       ; READ Left
    AND #%0000001
    BEQ :+
    JSR moveCarLeft
    :
    
    LDA $4016       ; READ Right
    AND #%0000001
    BEQ :+
    JSR moveCarRight
    :

    RTS

moveCarUp:
    LDX $0270
    CPX #$09
    BEQ :+
    DEX
    TXA
    STA $0270

    LDX $0274
    DEX
    TXA
    STA $0274
:
    RTS

moveCarDown:
    LDX $0270
    CPX #$D1
    BEQ :+
    INX
    TXA
    STA $0270

    LDX $0274
    INX
    TXA
    STA $0274
:
    RTS


moveCarRight:
    LDX $0273
    CPX #$A8
    BEQ :+

    INX
    TXA
    STA $0273

    LDX $0277
    INX
    TXA
    STA $0277
:
    RTS

moveCarLeft:
    LDX $0273
    CPX #$52
    BMI :+

    DEX
    TXA
    STA $0273

    LDX $0277
    DEX
    TXA
    STA $0277
:
    RTS

moveTreeLeft1:
    JSR updateRandom
    JSR updateRandom
    
    LDA $a0
    STA $65

    LDA $a0
    CMP #$39
    BCS endTreeLeft1

    LDA #$00
    STA $0230
    LDA #$51
    STA $0231
    LDA #$00
    STA $0232
    LDA $a0
    STA $0233

    LDA #$00
    STA $0234
    LDA #$52
    STA $0235
    LDA #$00
    STA $0236
    LDA $a0
    ADC #$08
    STA $0237

    LDA #$08
    STA $0238
    LDA #$61
    STA $0239
    LDA #$00
    STA $023A
    LDA $a0
    STA $023B

    LDA #$08
    STA $023C
    LDA #$62
    STA $023D
    LDA #$00
    STA $023E
    LDA $a0
    ADC #$08
    STA $023F

    LDA #$00
    STA $a9
    
    JMP endTreeLeft1
renderTreeLeft1:
    LDX $a9
    CPX #$F0
    BEQ moveTreeLeft1

    INC $0230
    INC $0234
    INC $0238
    INC $023C
    INC $a9

endTreeLeft1:
    RTS

moveTreeLeft2:
    JSR updateRandom
    JSR updateRandom

    LDA $a0
    STA $44
    CMP #$39
    BCS endTreeLeft2

    LDA #$00
    STA $0240
    LDA #$51
    STA $0241
    LDA #$00
    STA $0242
    LDA $a0
    STA $0243

    LDA #$00
    STA $0244
    LDA #$52
    STA $0245
    LDA #$00
    STA $0246
    LDA $a0
    ADC #$08
    STA $0247

    LDA #$08
    STA $0248
    LDA #$61
    STA $0249
    LDA #$00
    STA $024A
    LDA $a0
    STA $024B

    LDA #$08
    STA $024C
    LDA #$62
    STA $024D
    LDA #$00
    STA $024E
    LDA $a0
    ADC #$08
    STA $024F

    LDA #$00
    STA $a8
    
    JMP endTreeLeft2
renderTreeLeft2:
    LDX $a8
    CPX #$F0
    BEQ moveTreeLeft2
    
    INC $0240
    INC $0244
    INC $0248
    INC $024C
    INC $a8

endTreeLeft2:
    RTS

moveTreeRight1:
    JSR updateRandom
    JSR updateRandom
    
    LDA $a0
    CMP #$B1
    BCC endTreeRight1
    CMP #$F0
    BCS endTreeRight1

    LDA #$00
    STA $0250
    LDA #$51
    STA $0251
    LDA #$00
    STA $0252
    LDA $a0
    STA $0253

    LDA #$00
    STA $0254
    LDA #$52
    STA $0255
    LDA #$00
    STA $0256
    LDA $a0
    ADC #$08
    STA $0257

    LDA #$08
    STA $0258
    LDA #$61
    STA $0259
    LDA #$00
    STA $025A
    LDA $a0
    STA $025B

    LDA #$08
    STA $025C
    LDA #$62
    STA $025D
    LDA #$00
    STA $025E
    LDA $a0
    ADC #$08
    STA $025F

    LDA #$00
    STA $a7
    
    JMP endTreeRight1
renderTreeRight1:
    LDX $a7
    CPX #$F0
    BEQ moveTreeRight1
    
    INC $0250
    INC $0254
    INC $0258
    INC $025C
    INC $a7

endTreeRight1:
    RTS

moveTreeRight2:
    JSR updateRandom
    JSR updateRandom
    
    LDA $a0
    CMP #$B1
    BCC endTreeRight2
    CMP #$F0
    BCS endTreeRight2

    LDA #$00
    STA $0260
    LDA #$51 ; CHAR
    STA $0261
    LDA #$00
    STA $0262
    LDA $a0  ; Y
    STA $0263

    LDA #$00
    STA $0264
    LDA #$52
    STA $0265
    LDA #$00
    STA $0266
    LDA $a0
    ADC #$08
    STA $0267

    LDA #$08
    STA $0268
    LDA #$61
    STA $0269
    LDA #$00
    STA $026A
    LDA $a0
    STA $026B

    LDA #$08
    STA $026C
    LDA #$62
    STA $026D
    LDA #$00
    STA $026E
    LDA $a0
    ADC #$08
    STA $026F

    LDA #$00
    STA $a6
    
    JMP endTreeRight2
renderTreeRight2:
    LDX $a6
    CPX #$F0
    BEQ moveTreeRight2
    
    INC $0260
    INC $0264
    INC $0268
    INC $026C
    INC $a6

endTreeRight2:
    RTS

resetRandom:
    LDA $0270
    STA $a0

    LDA $0273
    STA $a1

    LDA #$90
    STA $a3
updateRandom:
    LDA #$00
    CMP $a0
    BEQ resetRandom

    INC $a2
    DEC $a3
    DEC $a3
    DEC $a3
    INC $a1
    INC $a1
    INC $a1
    INC $a1
    INC $a1

    LDA $a2
    EOR $a3
    STA $a3

    LDA $a0
    EOR $a1
    EOR $a2
    EOR $a3
    STA $a0

    RTS

resetDrawRoadLine1:
    LDA #$00
    STA $d0
    LDA #$08
    STA $d4
    LDA #$10
    STA $d8
drawRoadLine1:
    LDY #$00
    
    LDX $d0
    INX
    STX $d0

    LDX $d4
    INX
    STX $d4

    LDX $d8
    INX
    STX $d8
drawRoadLineBlocks1:
    LDX $d0, Y
    TXA
    STA $02dc, Y

    LDA #$32
    STA $02dd, Y
    LDA #$01
    STA $02de, Y
    LDA #$7d
    STA $02df, Y

    INY
    INY
    INY
    INY

    CPY #$0c
    BNE drawRoadLineBlocks1

    RTS

resetDrawRoadLine2:
    LDA #$40
    STA $e0
    LDA #$48
    STA $e4
    LDA #$50
    STA $e8
drawRoadLine2:
    LDY #$00
    
    LDX $e0
    INX
    STX $e0

    LDX $e4
    INX
    STX $e4

    LDX $e8
    INX
    STX $e8
drawRoadLineBlocks2:
    LDX $e0, Y
    TXA
    STA $02e8, Y

    LDA #$32
    STA $02e9, Y
    LDA #$01
    STA $02ea, Y
    LDA #$7d
    STA $02eb, Y

    INY
    INY
    INY
    INY

    CPY #$0c
    BNE drawRoadLineBlocks2

    RTS

resetDrawRoadLine3:
    LDA #$80
    STA $f0
    LDA #$88
    STA $f4
    LDA #$90
    STA $f8
drawRoadLine3:
    LDY #$00
    
    LDX $f0
    INX
    STX $f0

    LDX $f4
    INX
    STX $f4

    LDX $f8
    INX
    STX $f8
drawRoadLineBlocks3:
    LDX $f0, Y
    TXA
    STA $02f4, Y

    LDA #$32
    STA $02f5, Y
    LDA #$01
    STA $02f6, Y
    LDA #$7d
    STA $02f7, Y

    INY
    INY
    INY
    INY

    CPY #$0c
    BNE drawRoadLineBlocks3

    RTS

resetDrawRoadLine4:
    LDA #$c0
    STA $0100
    LDA #$c8
    STA $0104
    LDA #$d0
    STA $0108
drawRoadLine4:
    LDY #$00
    
    LDX $0100
    INX
    STX $0100

    LDX $0104
    INX
    STX $0104

    LDX $0108
    INX
    STX $0108
drawRoadLineBlocks4:
    LDX $0100, Y
    TXA
    STA $02d0, Y

    LDA #$32
    STA $02d1, Y
    LDA #$01
    STA $02d2, Y
    LDA #$7d
    STA $02d3, Y

    INY
    INY
    INY
    INY

    CPY #$0c
    BNE drawRoadLineBlocks4

    RTS

Background:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$02,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$02,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$02,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$02,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$02,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$02,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$02,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$02,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$02,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$02,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$02,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$02,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$02,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$02,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$02,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$02,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$02,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$02,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$02,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$02,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$02,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$02,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$02,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$02,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$02,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$02,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$02,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$02,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$02,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$02,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00



.segment "VECTORS"
    .word NMI
    .word Reset

.segment "CHARS"
    .incbin "gfx.chr"
