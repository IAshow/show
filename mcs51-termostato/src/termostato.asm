;=============================================================================
; TERMOSTATO DIGITAL COM MICROCONTROLADOR MCS-51 (AT89C51 / 8051)
;-----------------------------------------------------------------------------
; Mini Projeto - Programacao Assembly MCS'51 com simulacao em PROTEUS
;
; Funcionalidades:
;   - Leitura da temperatura com sensor LM35 + conversor ADC0804 (8 bits)
;     (VREF/2 = 1,28 V  ->  10 mV por LSB  ->  1 LSB = 1 grau C)
;   - Visualizacao num LCD 16x2 (HD44780 / LM016L) em modo de 8 bits
;   - Setpoint ajustavel com dois botoes (SUBIR / DESCER) entre 15 e 60 C
;   - Ventoinha (motor DC via L293D) com controlo ON/OFF com histerese e
;     velocidade proporcional ao erro (PWM por software, 100 Hz, 10 niveis)
;   - Alarme de sobretemperatura (T >= SP + 10 C): LED vermelho e buzzer
;     intermitentes (2 Hz)
;   - Registo de dados pela porta serie (9600 bps, 8N1) a cada segundo e
;     comandos remotos: '+' sobe o setpoint, '-' desce o setpoint
;
; Cristal: 11,0592 MHz  (1 ciclo maquina = 1,085 us)
; Assembler: ASEM-51 (integrado no PROTEUS 8) / Keil A51 (sintaxe Intel)
;=============================================================================

;-----------------------------------------------------------------------------
; Mapa de pinos
;-----------------------------------------------------------------------------
; P1.0..P1.7  <- ADC0804 DB0..DB7 (dados da conversao)
; P2.0..P2.7  -> LCD D0..D7
; P3.0 (RXD)  <- Porta serie (Virtual Terminal TXD)
; P3.1 (TXD)  -> Porta serie (Virtual Terminal RXD)
; P3.2        <- ADC0804 /INTR (fim de conversao, ativo a 0)
; P3.3        <- Botao SUBIR  (ativo a 0)
; P3.4        <- Botao DESCER (ativo a 0)
; P3.5        -> LCD RS
; P3.6        -> LCD E
; P3.7        -> L293D IN1 (ventoinha, PWM)
; P0.0        -> LED verde  "sistema OK"      (ativo a 0)
; P0.1        -> LED vermelho "alarme"        (ativo a 0)
; P0.2        -> Buzzer                       (ativo a 0)
; P0.3        -> LED amarelo "ventoinha ON"   (ativo a 0)
; P0.4        -> ADC0804 /RD
; P0.5        -> ADC0804 /WR
; (P0 e de dreno aberto: usar RESPACK-8 de 10k como pull-up)
;-----------------------------------------------------------------------------

ADC_INTR    BIT     P3.2
BTN_UP      BIT     P3.3
BTN_DN      BIT     P3.4
LCD_RS      BIT     P3.5
LCD_EN      BIT     P3.6
FAN         BIT     P3.7

LED_OK      BIT     P0.0
LED_ALM     BIT     P0.1
BUZZER      BIT     P0.2
LED_FAN     BIT     P0.3
ADC_RD      BIT     P0.4
ADC_WR      BIT     P0.5

ADC_DADOS   EQU     P1
LCD_DADOS   EQU     P2

;-----------------------------------------------------------------------------
; Constantes
;-----------------------------------------------------------------------------
SP_INICIAL  EQU     28          ; setpoint inicial (graus C)
SP_MIN      EQU     15
SP_MAX      EQU     60
DUTY_MIN    EQU     3           ; duty minimo com ventoinha ligada (30 %)
DUTY_MAX    EQU     10          ; 10 niveis de PWM = 100 %
ALARME_DT   EQU     10          ; alarme quando T >= SP + 10
MASC_BTN    EQU     18h         ; mascara de P3.3 e P3.4

T0_H        EQU     0FCh        ; 65536 - 922 = 0FC66h -> 1 ms @ 11,0592 MHz
T0_L        EQU     66h
BAUD_9600   EQU     0FDh        ; TH1 para 9600 bps (SMOD = 0)

;-----------------------------------------------------------------------------
; Variaveis em RAM interna
;-----------------------------------------------------------------------------
; Flags (area enderecavel ao bit, byte 20h)
F_AMOSTRA   BIT     00h         ; 20h.0 - passaram 250 ms -> nova leitura
F_BOTOES    BIT     01h         ; 20h.1 - passaram 20 ms  -> ler botoes
F_VENT      BIT     02h         ; 20h.2 - ventoinha ligada
F_ALARME    BIT     03h         ; 20h.3 - alarme ativo
F_PISCA     BIT     04h         ; 20h.4 - onda de 2 Hz para intermitencia
F_SERIE     BIT     05h         ; 20h.5 - PUTC envia para a serie (1) / LCD (0)

SETPT       EQU     30h         ; setpoint (graus C)
TEMP        EQU     31h         ; ultima temperatura lida (graus C)
DUTY        EQU     32h         ; nivel de PWM (0..10)
CNT_PWM     EQU     33h         ; contador de PWM (0..9)
CNT_20MS    EQU     34h         ; divisor 1 ms -> 20 ms
CNT_250MS   EQU     35h         ; divisor 1 ms -> 250 ms
BTN_ANT     EQU     36h         ; estado anterior dos botoes
CNT_LOG     EQU     37h         ; divisor 250 ms -> 1 s (registo serie)

PILHA       EQU     5Fh         ; pilha comeca em 60h

;=============================================================================
; Vetores
;=============================================================================
            ORG     0000h
            LJMP    INICIO

            ORG     000Bh               ; interrupcao do Timer 0
            LJMP    ISR_T0

;=============================================================================
; Programa principal
;=============================================================================
            ORG     0030h
INICIO:
            MOV     SP,#PILHA
            ; --- Portos ------------------------------------------------------
            MOV     P0,#0FFh            ; LEDs/buzzer desligados, /RD=/WR=1
            MOV     P1,#0FFh            ; P1 como entrada (ADC)
            MOV     P3,#0FFh            ; entradas de P3 a 1
            CLR     FAN                 ; ventoinha parada
            CLR     LCD_EN
            ; --- Variaveis ---------------------------------------------------
            MOV     20h,#00h            ; limpa todas as flags
            MOV     SETPT,#SP_INICIAL
            MOV     TEMP,#0
            MOV     DUTY,#0
            MOV     CNT_PWM,#0
            MOV     CNT_20MS,#20
            MOV     CNT_250MS,#250
            MOV     BTN_ANT,#0
            MOV     CNT_LOG,#4
            ; --- Perifericos -------------------------------------------------
            LCALL   LCD_INIT
            LCALL   SERIE_INIT
            ; --- Mensagem inicial --------------------------------------------
            CLR     F_SERIE
            MOV     DPTR,#TXT_TITULO1
            LCALL   PUT_STR
            MOV     A,#0C0h             ; linha 2
            LCALL   LCD_CMD
            MOV     DPTR,#TXT_TITULO2
            LCALL   PUT_STR
            SETB    F_SERIE
            MOV     DPTR,#TXT_BANNER
            LCALL   PUT_STR
            MOV     R6,#250             ; ~1 s de apresentacao
            LCALL   ATRASO_MS
            MOV     R6,#250
            LCALL   ATRASO_MS
            MOV     R6,#250
            LCALL   ATRASO_MS
            MOV     R6,#250
            LCALL   ATRASO_MS
            MOV     A,#01h              ; limpa o LCD
            LCALL   LCD_CMD
            ; --- Timer 0 (base de tempo 1 ms) --------------------------------
            MOV     TMOD,#21h           ; T1 modo 2 (baud), T0 modo 1 (16 bits)
            MOV     TH0,#T0_H
            MOV     TL0,#T0_L
            SETB    ET0
            SETB    EA
            SETB    TR0
            SETB    F_AMOSTRA           ; primeira leitura imediata

CICLO:
            ; --- Botoes (cada 20 ms -> antirressalto natural) ----------------
            JNB     F_BOTOES,CIC_SERIE
            CLR     F_BOTOES
            LCALL   LER_BOTOES
CIC_SERIE:
            ; --- Comandos pela porta serie -----------------------------------
            JNB     RI,CIC_AMOSTRA
            LCALL   LER_COMANDO
CIC_AMOSTRA:
            ; --- Aquisicao, controlo e visualizacao (cada 250 ms) ------------
            JNB     F_AMOSTRA,CICLO
            CLR     F_AMOSTRA
            LCALL   LER_ADC
            MOV     TEMP,A
            LCALL   CONTROLO
            LCALL   MOSTRAR_LCD
            DJNZ    CNT_LOG,CICLO       ; registo serie a cada 4 x 250 ms
            MOV     CNT_LOG,#4
            LCALL   REGISTO_SERIE
            SJMP    CICLO

;=============================================================================
; ISR do Timer 0 - executada a cada 1 ms
;   - gera o PWM da ventoinha (periodo 10 ms -> 100 Hz)
;   - gera as bases de tempo de 20 ms e 250 ms
;   - faz piscar o LED de alarme e o buzzer
;=============================================================================
ISR_T0:
            PUSH    PSW
            PUSH    ACC
            CLR     TR0
            MOV     TH0,#T0_H           ; recarga para o proximo 1 ms
            MOV     TL0,#T0_L
            SETB    TR0
            ; --- PWM por software --------------------------------------------
            INC     CNT_PWM
            MOV     A,CNT_PWM
            CJNE    A,#DUTY_MAX,ISR_PWM
            MOV     CNT_PWM,#0
            CLR     A
ISR_PWM:
            CLR     C
            SUBB    A,DUTY              ; C = 1 se CNT_PWM < DUTY
            MOV     FAN,C               ; motor ligado durante DUTY ms em 10
            ; --- Base de tempo de 20 ms --------------------------------------
            DJNZ    CNT_20MS,ISR_250
            MOV     CNT_20MS,#20
            SETB    F_BOTOES
ISR_250:
            ; --- Base de tempo de 250 ms -------------------------------------
            DJNZ    CNT_250MS,ISR_FIM
            MOV     CNT_250MS,#250
            SETB    F_AMOSTRA
            CPL     F_PISCA
            ; --- Sinalizacao (LEDs ativos a 0) -------------------------------
            JNB     F_ALARME,ISR_SEM_ALM
            SETB    LED_OK              ; apaga LED verde
            MOV     C,F_PISCA
            MOV     LED_ALM,C           ; LED vermelho intermitente
            MOV     BUZZER,C            ; buzzer intermitente
            SJMP    ISR_LEDVENT
ISR_SEM_ALM:
            CLR     LED_OK              ; LED verde aceso
            SETB    LED_ALM
            SETB    BUZZER
ISR_LEDVENT:
            MOV     C,F_VENT
            CPL     C
            MOV     LED_FAN,C           ; LED amarelo = ventoinha ligada
ISR_FIM:
            POP     ACC
            POP     PSW
            RETI

;=============================================================================
; LER_ADC - efetua uma conversao no ADC0804 (/CS ligado a GND)
;   Saida: A = valor convertido (graus C). Em caso de timeout devolve TEMP.
;   Usa: R7
;=============================================================================
LER_ADC:
            MOV     ADC_DADOS,#0FFh     ; P1 como entrada
            CLR     ADC_WR              ; impulso em /WR inicia a conversao
            NOP
            NOP
            SETB    ADC_WR
            MOV     R7,#0               ; timeout ~ 256 x 4 ciclos (~1,1 ms)
LADC_ESP:
            JNB     ADC_INTR,LADC_PRONTO
            DJNZ    R7,LADC_ESP
            MOV     A,TEMP              ; ADC nao respondeu: mantem valor
            RET
LADC_PRONTO:
            CLR     ADC_RD              ; ativa as saidas do ADC
            NOP
            NOP
            MOV     A,ADC_DADOS
            SETB    ADC_RD
            RET

;=============================================================================
; CONTROLO - decide o estado da ventoinha e do alarme
;   T <  SP        -> ventoinha desligada
;   T == SP        -> mantem estado (histerese de 1 grau)
;   T >  SP        -> ventoinha ligada, DUTY = 3 + (T - SP), max. 10
;   T >= SP + 10   -> alarme
;   Usa: A, R5
;=============================================================================
CONTROLO:
            MOV     A,TEMP
            CLR     C
            SUBB    A,SETPT             ; A = T - SP
            JC      CTL_DESLIGA         ; T < SP
            MOV     R5,A                ; R5 = diferenca (>= 0)
            JNZ     CTL_LIGA            ; T > SP
            JNB     F_VENT,CTL_DESLIGA  ; T == SP e estava desligada
CTL_LIGA:
            SETB    F_VENT
            MOV     A,R5
            CLR     C
            SUBB    A,#(DUTY_MAX-DUTY_MIN)
            JNC     CTL_SATURA          ; diferenca >= 7 -> 100 %
            MOV     A,R5
            ADD     A,#DUTY_MIN
            SJMP    CTL_DUTY
CTL_SATURA:
            MOV     A,#DUTY_MAX
CTL_DUTY:
            MOV     DUTY,A
            ; --- Alarme ------------------------------------------------------
            MOV     A,R5
            CLR     C
            SUBB    A,#ALARME_DT
            JC      CTL_SEM_ALM         ; diferenca < 10
            SETB    F_ALARME
            RET
CTL_DESLIGA:
            CLR     F_VENT
            MOV     DUTY,#0
CTL_SEM_ALM:
            CLR     F_ALARME
            RET

;=============================================================================
; LER_BOTOES - detecao de flanco (premir) nos botoes SUBIR/DESCER
;   Chamada a cada 20 ms (antirressalto). Usa: A, R6, R7
;=============================================================================
LER_BOTOES:
            MOV     A,P3
            CPL     A                   ; botoes ativos a 0 -> premido = 1
            ANL     A,#MASC_BTN
            MOV     R7,A                ; estado atual
            XRL     A,BTN_ANT           ; bits que mudaram
            ANL     A,R7                ; ... e que estao premidos agora
            MOV     R6,A                ; R6 = botoes acabados de premir
            MOV     BTN_ANT,R7
            MOV     A,R6
            JNB     ACC.3,LB_DESCER
            LCALL   SP_SOBE
LB_DESCER:
            MOV     A,R6
            JNB     ACC.4,LB_FIM
            LCALL   SP_DESCE
LB_FIM:
            RET

;=============================================================================
; SP_SOBE / SP_DESCE - altera o setpoint dentro dos limites e pede
; atualizacao imediata (nova amostra -> controlo -> LCD)
;=============================================================================
SP_SOBE:
            MOV     A,SETPT
            CJNE    A,#SP_MAX,SPS_OK
            RET
SPS_OK:
            INC     SETPT
            SETB    F_AMOSTRA
            RET

SP_DESCE:
            MOV     A,SETPT
            CJNE    A,#SP_MIN,SPD_OK
            RET
SPD_OK:
            DEC     SETPT
            SETB    F_AMOSTRA
            RET

;=============================================================================
; LER_COMANDO - le um caracter recebido pela serie
;   '+' sobe o setpoint, '-' desce o setpoint; restantes sao ignorados
;=============================================================================
LER_COMANDO:
            MOV     A,SBUF
            CLR     RI
            CJNE    A,#'+',LC_MENOS
            LJMP    SP_SOBE
LC_MENOS:
            CJNE    A,#'-',LC_FIM
            LJMP    SP_DESCE
LC_FIM:
            RET

;=============================================================================
; MOSTRAR_LCD - escreve o estado no LCD
;   Linha 1: "T= 25oC SP=28oC "
;   Linha 2: "VENT: 70%   OK  "  ou  "VENT:100% ALARME"
;=============================================================================
MOSTRAR_LCD:
            CLR     F_SERIE
            MOV     A,#80h              ; cursor no inicio da linha 1
            LCALL   LCD_CMD
            MOV     A,#'T'
            LCALL   PUTC
            MOV     A,#'='
            LCALL   PUTC
            MOV     A,TEMP
            LCALL   PUT_DEC3
            MOV     A,#0DFh             ; simbolo de grau no HD44780
            LCALL   PUTC
            MOV     DPTR,#TXT_C_SP      ; "C SP="
            LCALL   PUT_STR
            MOV     A,SETPT
            LCALL   PUT_DEC2
            MOV     A,#0DFh
            LCALL   PUTC
            MOV     A,#'C'
            LCALL   PUTC
            MOV     A,#' '
            LCALL   PUTC
            MOV     A,#0C0h             ; cursor no inicio da linha 2
            LCALL   LCD_CMD
            MOV     DPTR,#TXT_VENT      ; "VENT:"
            LCALL   PUT_STR
            LCALL   PUT_DUTY            ; "  0%" .. "100%"
            MOV     A,#' '
            LCALL   PUTC
            LCALL   PUT_ESTADO          ; "  OK  " / "ALARME"
            RET

;=============================================================================
; REGISTO_SERIE - envia uma linha de estado pela porta serie
;   Exemplo: "T= 25C SP=28C VENT: 30%   OK  <CR><LF>"
;=============================================================================
REGISTO_SERIE:
            SETB    F_SERIE
            MOV     A,#'T'
            LCALL   PUTC
            MOV     A,#'='
            LCALL   PUTC
            MOV     A,TEMP
            LCALL   PUT_DEC3
            MOV     DPTR,#TXT_C_SP
            LCALL   PUT_STR
            MOV     A,SETPT
            LCALL   PUT_DEC2
            MOV     DPTR,#TXT_C_VENT    ; "C VENT:"
            LCALL   PUT_STR
            LCALL   PUT_DUTY
            MOV     A,#' '
            LCALL   PUTC
            LCALL   PUT_ESTADO
            MOV     A,#0Dh
            LCALL   PUTC
            MOV     A,#0Ah
            LCALL   PUTC
            CLR     F_SERIE
            RET

;-----------------------------------------------------------------------------
; PUT_DUTY  - escreve DUTY x 10 em percentagem ("  0%".."100%")
; PUT_ESTADO - escreve "  OK  " ou "ALARME"
;-----------------------------------------------------------------------------
PUT_DUTY:
            MOV     A,DUTY
            MOV     B,#10
            MUL     AB
            LCALL   PUT_DEC3
            MOV     A,#'%'
            LJMP    PUTC

PUT_ESTADO:
            MOV     DPTR,#TXT_OK
            JNB     F_ALARME,PE_ESCR
            MOV     DPTR,#TXT_ALARME
PE_ESCR:
            LJMP    PUT_STR

;=============================================================================
; Rotinas de saida de texto (destino escolhido por F_SERIE)
;=============================================================================
; PUTC - envia o caracter em A para o LCD ou para a porta serie
PUTC:
            JB      F_SERIE,SERIE_TX
            LJMP    LCD_DADO

; PUT_STR - envia a string terminada em 0 apontada por DPTR
PUT_STR:
            CLR     A
            MOVC    A,@A+DPTR
            JZ      PS_FIM
            LCALL   PUTC
            INC     DPTR
            SJMP    PUT_STR
PS_FIM:
            RET

; PUT_DEC3 - escreve A (0..255) em 3 digitos, zeros a esquerda como espacos
;   Usa: A, B, R2, R3, R4
PUT_DEC3:
            MOV     B,#100
            DIV     AB
            MOV     R2,A                ; centenas
            MOV     A,B
            MOV     B,#10
            DIV     AB
            MOV     R3,A                ; dezenas
            MOV     R4,B                ; unidades
            MOV     A,R2
            JZ      PD3_SEM_C
            ADD     A,#'0'
            LCALL   PUTC
            MOV     A,R3                ; com centenas, dezenas sempre visiveis
            SJMP    PD3_DIG
PD3_SEM_C:
            MOV     A,#' '
            LCALL   PUTC
            MOV     A,R3
            JNZ     PD3_DIG
            MOV     A,#' '
            LCALL   PUTC
            SJMP    PD3_UNI
PD3_DIG:
            ADD     A,#'0'
            LCALL   PUTC
PD3_UNI:
            MOV     A,R4
            ADD     A,#'0'
            LJMP    PUTC

; PUT_DEC2 - escreve A (0..99) em 2 digitos. Usa: A, B, R4
PUT_DEC2:
            MOV     B,#10
            DIV     AB
            MOV     R4,B
            ADD     A,#'0'
            LCALL   PUTC
            MOV     A,R4
            ADD     A,#'0'
            LJMP    PUTC

;=============================================================================
; Porta serie - 9600 bps, 8N1, Timer 1 em modo 2
;=============================================================================
SERIE_INIT:
            MOV     TMOD,#21h
            MOV     TH1,#BAUD_9600
            MOV     TL1,#BAUD_9600
            MOV     SCON,#50h           ; modo 1, rececao ativa
            CLR     TI
            CLR     RI
            SETB    TR1
            RET

; SERIE_TX - envia o caracter em A (espera pelo fim da transmissao)
SERIE_TX:
            MOV     SBUF,A
STX_ESP:
            JNB     TI,STX_ESP
            CLR     TI
            RET

;=============================================================================
; LCD HD44780 - interface de 8 bits, R/W ligado a GND (escrita com atrasos)
;=============================================================================
LCD_INIT:
            CLR     LCD_EN
            MOV     R6,#20              ; > 15 ms apos alimentacao
            LCALL   ATRASO_MS
            MOV     A,#38h              ; sequencia de inicializacao
            LCALL   LCD_CMD
            MOV     R6,#5
            LCALL   ATRASO_MS
            MOV     A,#38h
            LCALL   LCD_CMD
            MOV     A,#38h              ; 8 bits, 2 linhas, 5x7
            LCALL   LCD_CMD
            MOV     A,#0Ch              ; display ON, cursor OFF
            LCALL   LCD_CMD
            MOV     A,#06h              ; incremento automatico, sem shift
            LCALL   LCD_CMD
            MOV     A,#01h              ; limpar
            LCALL   LCD_CMD
            RET

; LCD_CMD - envia o comando em A (RS = 0). Usa: A, R5, R6, R7
LCD_CMD:
            CLR     LCD_RS
            LCALL   LCD_ESCREVE
            CJNE    A,#03h,LCMD_C       ; comandos 01h/02h demoram ~1,6 ms
LCMD_C:
            JNC     LCMD_FIM
            MOV     R6,#2
            LCALL   ATRASO_MS
LCMD_FIM:
            RET

; LCD_DADO - escreve o caracter em A (RS = 1). Usa: R7
LCD_DADO:
            SETB    LCD_RS
; LCD_ESCREVE - coloca A no barramento e gera o impulso em E
LCD_ESCREVE:
            MOV     LCD_DADOS,A
            SETB    LCD_EN
            NOP
            NOP
            CLR     LCD_EN
            LJMP    ATRASO_50US

;=============================================================================
; Atrasos por software (cristal de 11,0592 MHz)
;=============================================================================
; ATRASO_50US - ~50 us. Usa: R7
ATRASO_50US:
            MOV     R7,#21
A50_L:
            DJNZ    R7,A50_L
            RET

; ATRASO_MS - ~R6 milissegundos. Usa: R5, R6, R7
ATRASO_MS:
            MOV     R5,#2
AMS_L1:
            MOV     R7,#229
AMS_L2:
            DJNZ    R7,AMS_L2
            DJNZ    R5,AMS_L1
            DJNZ    R6,ATRASO_MS
            RET

;=============================================================================
; Textos (memoria de programa)
;=============================================================================
TXT_TITULO1:    DB      'TERMOSTATO  8051',0
TXT_TITULO2:    DB      ' MCS-51 + LM35  ',0
TXT_BANNER:     DB      'Termostato MCS-51 - comandos: + sobe SP, - desce SP',0Dh,0Ah,0
TXT_C_SP:       DB      'C SP=',0
TXT_C_VENT:     DB      'C VENT:',0
TXT_VENT:       DB      'VENT:',0
TXT_OK:         DB      '  OK  ',0
TXT_ALARME:     DB      'ALARME',0

            END
