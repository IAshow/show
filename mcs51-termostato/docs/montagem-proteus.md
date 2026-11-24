# Montagem no PROTEUS (ISIS) — passo a passo

## 1. Componentes (Pick Devices)

| Ref. | Nome no PROTEUS | Qtd. | Valor / Notas |
|---|---|---|---|
| U1 | `AT89C51` | 1 | Clock 11.0592MHz, Program File `termostato.hex` |
| U2 | `LM35` | 1 | Sensor de temperatura (10 mV/°C) |
| U3 | `ADC0804` | 1 | ADC de 8 bits |
| LCD1 | `LM016L` | 1 | LCD 16x2 (HD44780) |
| U4 | `L293D` | 1 | Driver do motor |
| M1 | `MOTOR` (ou `MOTOR-DC`) | 1 | Ventoinha |
| RP1 | `RESPACK-8` | 1 | 10k — pull‑ups do porto P0 |
| D1 | `LED-GREEN` | 1 | Sistema OK |
| D2 | `LED-RED` | 1 | Alarme |
| D3 | `LED-YELLOW` | 1 | Ventoinha ligada |
| BZ1 | `BUZZER` | 1 | Alarme sonoro |
| R1–R3 | `RES` | 3 | 330 Ω (LEDs) |
| R4 | `RES` | 1 | 10k (relógio do ADC) |
| C1 | `CAP` | 1 | 150 pF (relógio do ADC) |
| VR1 | `POT-HG` | 1 | 10k — ajustar VREF/2 = 1,28 V (ou gerador `DC` de 1.28 V) |
| BTN1, BTN2 | `BUTTON` | 2 | SUBIR / DESCER |
| — | `VIRTUAL TERMINAL` | 1 | 9600 baud, 8N1 (instrumento) |
| — | `DC VOLTMETER` | 1 | Opcional, para verificar VREF/2 |

> Circuito de reset (10 µF + 10k) e cristal (11,0592 MHz + 2×33 pF) são necessários numa placa real; no PROTEUS o AT89C51 funciona só com a propriedade *Clock Frequency*. Pinos de alimentação do microcontrolador estão ligados implicitamente. Ligar **/EA (pino 31) a VCC**.

## 2. Ligações

### AT89C51 ↔ ADC0804
| ADC0804 | Liga a |
|---|---|
| DB0…DB7 (pinos 18…11) | P1.0…P1.7 |
| /CS (1) | GND |
| /RD (2) | P0.4 |
| /WR (3) | P0.5 |
| CLK IN (4) | C1 (150 pF) a GND, e R4 (10k) a CLK R |
| CLK R (19) | R4 (10k) a CLK IN |
| /INTR (5) | P3.2 |
| VIN+ (6) | LM35 VOUT |
| VIN− (7), A GND (8), D GND (10) | GND |
| VREF/2 (9) | cursor de VR1 (1,28 V) |
| VCC (20) | +5 V |

Frequência do relógio do ADC: f ≈ 1 / (1,1·R·C) = 1 / (1,1 × 10 kΩ × 150 pF) ≈ 606 kHz.

### LM35
VS → +5 V, GND → GND, VOUT → VIN+ do ADC0804.

### LCD LM016L
| LCD | Liga a |
|---|---|
| D0…D7 | P2.0…P2.7 |
| RS | P3.5 |
| RW | GND |
| E | P3.6 |
| VSS | GND, VDD → +5 V, VEE → GND (contraste) |

### Ventoinha (L293D)
| L293D | Liga a |
|---|---|
| EN1 (1) | +5 V |
| IN1 (2) | P3.7 |
| IN2 (7) | GND |
| OUT1 (3) | Motor + |
| OUT2 (6) | Motor − |
| VSS (16) | +5 V, VS (8) → +12 V (ou +5 V em simulação) |
| GND (4, 5, 12, 13) | GND |

### Botões
BTN1 (SUBIR): P3.3 ↔ GND. BTN2 (DESCER): P3.4 ↔ GND. (Pull‑ups internas do porto 3.)

### Porto P0 — LEDs, buzzer (ativos a 0)
RP1 (RESPACK‑8): pino comum a +5 V e os 8 pinos a P0.0…P0.7 (P0 é de dreno aberto).

| Pino | Ligação |
|---|---|
| P0.0 | cátodo D1 (verde); ânodo → R1 330 Ω → +5 V |
| P0.1 | cátodo D2 (vermelho); ânodo → R2 330 Ω → +5 V |
| P0.2 | terminal − do BUZZER; terminal + → +5 V |
| P0.3 | cátodo D3 (amarelo); ânodo → R3 330 Ω → +5 V |
| P0.4 | /RD do ADC0804 |
| P0.5 | /WR do ADC0804 |

> Numa placa real o buzzer deve ser comandado por um transístor; em simulação a ligação direta é suficiente.

### Virtual Terminal
RXD do terminal ← P3.1 (TXD); TXD do terminal → P3.0 (RXD). Propriedades: 9600 baud, 8 bits, sem paridade, 1 stop bit.

## 3. Programa

- **Opção A (mais simples):** duplo clique no AT89C51 → *Program File* → `src/termostato.hex`.
- **Opção B (compilar no PROTEUS):** *Source Code* → *Add Source File* → `termostato.asm`, *Code Generation Tool* = **ASEM51** → *Build Project*. Depois, em *Program File*, escolher o `.hex` gerado.

## 4. Verificação

1. Iniciar: o LCD mostra `TERMOSTATO  8051` durante ~1 s e o terminal recebe a mensagem de boas‑vindas.
2. Com o LM35 a 25 °C e SP = 28 °C: `VENT:  0%   OK`, LED verde aceso.
3. Subir o LM35 até 33 °C: motor roda, `VENT: 80%`, LED amarelo aceso.
4. Subir até 38 °C ou mais: `ALARME`, LED vermelho e buzzer a piscar.
5. Premir SUBIR/DESCER, ou enviar `+`/`-` no terminal: o SP muda de imediato.
