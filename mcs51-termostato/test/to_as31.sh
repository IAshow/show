#!/bin/sh
# Converte a fonte (sintaxe Intel/ASEM-51) para a sintaxe do as31 (apenas para testes)
sed -E \
 -e 's/^([A-Z_0-9]+)[[:space:]]+(BIT|EQU)[[:space:]]+([^;]*[^;[:space:]])/\t.equ \1, \3/' \
 -e 's/\bP0\.([0-7])/080h+\1/; s/\bP1\.([0-7])/090h+\1/; s/\bP2\.([0-7])/0A0h+\1/; s/\bP3\.([0-7])/0B0h+\1/' \
 -e 's/^[[:space:]]+ORG[[:space:]]+/\t.org /' \
 -e "s/^([A-Z_0-9]+:)[[:space:]]+DB[[:space:]]+'([^']*)'/\1\t.db \"\2\"/" \
 -e 's/^[[:space:]]+END[[:space:]]*$/\t.end/' \
 "$1"
