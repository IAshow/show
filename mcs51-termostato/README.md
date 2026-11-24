# Termóstato Digital com MCS‑51 — Mini Projeto (Assembly + PROTEUS)

Montagem controlada por um AT89C51 (família MCS‑51), programada em **Assembly** e simulada em **PROTEUS**.

O sistema mede a temperatura com um **LM35** através de um conversor **ADC0804**, mostra‑a num **LCD 16x2** e controla uma **ventoinha (motor DC via L293D)** com PWM proporcional ao erro em relação a um **setpoint** ajustável por **botões** ou pela **porta série**. Quando há sobretemperatura, dispara um **alarme** (LED vermelho e buzzer intermitentes).

```
LM35 ──► ADC0804 ──P1──► ┌──────────┐ ──P2──► LCD 16x2
                         │ AT89C51  │ ──P3.7─► L293D ─► Motor DC (ventoinha)
Botões ▲▼ ──P3.3/P3.4──► │ 11,0592  │ ──P0───► LEDs + Buzzer
Virtual Terminal ◄─UART─►└──────────┘
```

## Estrutura

| Ficheiro | Conteúdo |
|---|---|
| `src/termostato.asm` | Programa em Assembly MCS‑51 (sintaxe ASEM‑51 / Keil A51) |
| `src/termostato.hex` | Código já compilado (Intel HEX) para carregar diretamente no AT89C51 |
| `docs/relatorio.md` | Relatório: componente teórica e prática |
| `docs/montagem-proteus.md` | Lista de componentes e ligações, passo a passo, para o PROTEUS |
| `test/simular.sh` | Teste automático do firmware no simulador `ucsim` (sem PROTEUS) |
| `test/to_as31.sh` | Conversão da sintaxe para o assembler `as31` (usado só no teste) |

## Uso rápido no PROTEUS

1. Montar o circuito segundo `docs/montagem-proteus.md`.
2. No AT89C51: **Clock Frequency = 11.0592MHz** e **Program File = `src/termostato.hex`**  
   (ou, em *Source Code*, adicionar `termostato.asm` com o compilador **ASEM‑51** e fazer *Build*).
3. Executar a simulação e alterar a temperatura nas setas do LM35.
4. Botões **SUBIR / DESCER** alteram o setpoint (15–60 °C). No *Virtual Terminal* (9600 8N1), `+` e `-` fazem o mesmo.

## Comportamento

| Condição | Ventoinha | Sinalização |
|---|---|---|
| T < SP | desligada | LED verde |
| T = SP | mantém o estado anterior (histerese) | LED verde |
| T > SP | ligada, PWM = 30 % + 10 % por °C acima do SP (máx. 100 %) | LED verde + LED amarelo |
| T ≥ SP + 10 | 100 % | **ALARME**: LED vermelho e buzzer a 2 Hz |

LCD:
```
T= 33°C SP=28°C
VENT: 80%   OK
```

## Teste sem PROTEUS

```bash
sudo apt-get install as31 sdcc-ucsim
bash test/simular.sh      # termina com "TESTE OK"
```
