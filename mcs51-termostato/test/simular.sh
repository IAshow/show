#!/bin/bash
# Teste automatico do firmware no simulador ucsim (s51), sem PROTEUS.
# Requisitos (Debian/Ubuntu): apt-get install as31 sdcc-ucsim
# O ADC0804 e simulado colocando o valor em P1 e /INTR (P3.2) a 0;
# os botoes sao simulados forcando P3.3 / P3.4 a 0.
set -e
AQUI=$(cd "$(dirname "$0")" && pwd)
TMP=$(mktemp -d)
bash "$AQUI/to_as31.sh" "$AQUI/../src/termostato.asm" > "$TMP/t.asm"
( cd "$TMP" && as31 -l t.asm >/dev/null )
: > "$TMP/in.txt"
cat > "$TMP/cmd.txt" <<'CMD'
pin1=25
pin3=0xfb
step 1300000
pin1=33
step 600000
pin1=40
step 600000
pin3=0xf3
step 60000
pin3=0xfb
step 600000
pin1=29
step 600000
pin1=28
step 600000
pin3=0xeb
step 60000
pin3=0xfb
step 600000
pin1=26
step 600000
quit
CMD
( cd "$TMP" && s51 -t 8051 -X 11.0592M -S in=in.txt,out=out.txt t.hex < cmd.txt > log.txt 2>&1 )
tr -d '\r' < "$TMP/out.txt" > "$TMP/obtido.txt"
cat > "$TMP/esperado.txt" <<'ESP'
Termostato MCS-51 - comandos: + sobe SP, - desce SP
T= 25C SP=28C VENT:  0%   OK  
T= 25C SP=28C VENT:  0%   OK  
T= 33C SP=28C VENT: 80%   OK  
T= 40C SP=28C VENT:100% ALARME
T= 40C SP=29C VENT:100% ALARME
T= 29C SP=29C VENT: 30%   OK  
T= 28C SP=29C VENT:  0%   OK  
T= 28C SP=28C VENT:  0%   OK  
T= 26C SP=28C VENT:  0%   OK  
ESP
echo "--- saida serie obtida ---"
cat "$TMP/obtido.txt"
# compara so as linhas distintas (o numero de repeticoes depende do tempo)
if [ "$(uniq "$TMP/obtido.txt")" = "$(uniq "$TMP/esperado.txt")" ]; then
  echo "TESTE OK"; cp "$TMP/t.hex" "$AQUI/../src/termostato.hex"; rm -rf "$TMP"
else
  echo "TESTE FALHOU"; diff <(uniq "$TMP/esperado.txt") <(uniq "$TMP/obtido.txt") || true; exit 1
fi
