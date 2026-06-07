#!/usr/bin/env bash
# =============================================================================
# 03_demux_native96_strict.sh
#
# Dorado basecalling + stricte demultiplexing
# Kit:    Native Barcoding Kit 96 V14 (SQK-NBD114-96)
# Mode:   Strikt — barcode moet aan BEIDE uiteinden gedetecteerd worden
#
# Wanneer gebruiken:
#   - Nauw verwante samples waarbij barcode-contaminatie kritisch is
#     (bijv. Brucella stammen die nauwelijks van elkaar verschillen)
#   - Downstream methylatie-analyse per stam
#   - Wanneer zuiverheid van de barcode-toewijzing zwaarder weegt dan yield
#
# Trade-off:
#   - Minder reads geclassificeerd (tot 50% meer unclassified t.o.v. simpel)
#   - Maar vrijwel geen cross-barcode contaminatie
#
# Input:  ./pod5/       (map met .pod5 bestanden)
# Output: ./01_demuxed/ (één BAM per barcode)
# =============================================================================
set -euo pipefail
shopt -s nullglob

# -----------------------------------------------------------------------------
# Configuratie — pas hier aan, niet op de CLI
# -----------------------------------------------------------------------------
DORADO="/data/GIT/dorado-2.0.0-linux-x64/bin/dorado"
NGS_PROJECT="NGS-YY-XX"

POD5_DIR="$(pwd)/pod5"
OUT_DIR="$(pwd)/01_demuxed"
TMP_BAM="$(pwd)/tmp_calls.bam"

KIT="SQK-NBD114-96"
MODEL="sup"
MIN_QSCORE=10

# -----------------------------------------------------------------------------
# Validatie
# -----------------------------------------------------------------------------
[[ -x "$DORADO" ]]  || { echo "ERROR: dorado niet gevonden: $DORADO"; exit 1; }
[[ -d "$POD5_DIR" ]] || { echo "ERROR: pod5 map niet gevonden: $POD5_DIR"; exit 1; }

pod5_files=("${POD5_DIR}"/*.pod5)
(( ${#pod5_files[@]} > 0 )) || { echo "ERROR: geen .pod5 bestanden in $POD5_DIR"; exit 1; }

mkdir -p "$OUT_DIR"

echo "========================================"
echo "Project : $NGS_PROJECT"
echo "Script  : $(basename "$0")"
echo "Kit     : $KIT"
echo "Mode    : strikt (barcode beide uiteinden vereist)"
echo "Pod5    : ${#pod5_files[@]} bestanden"
echo "Output  : $OUT_DIR"
echo "Gestart : $(date)"
echo "========================================"

# -----------------------------------------------------------------------------
# Stap 1: Basecalling → tijdelijk BAM
# -----------------------------------------------------------------------------
# --barcode-both-ends al hier: classificatie-tags in BAM zijn dan al strikt.
echo "[1/2] Basecalling..."

"$DORADO" basecaller \
    --device cuda:all \
    --kit-name "$KIT" \
    --barcode-both-ends \
    --min-qscore "$MIN_QSCORE" \
    --emit-summary \
    "$MODEL" \
    "$POD5_DIR" \
    > "$TMP_BAM"

echo "  Klaar: $(date)"

# -----------------------------------------------------------------------------
# Stap 2: Demultiplexen
# -----------------------------------------------------------------------------
# --barcode-both-ends ook hier herhalen: demux herbeoordeelt classificatie
# onafhankelijk van de basecaller tags.
echo "[2/2] Demultiplexen..."

"$DORADO" demux \
    --kit-name "$KIT" \
    --barcode-both-ends \
    --output-dir "$OUT_DIR" \
    --emit-summary \
    "$TMP_BAM"

echo "  Klaar: $(date)"

# -----------------------------------------------------------------------------
# Opruimen
# -----------------------------------------------------------------------------
rm -f "$TMP_BAM"

# -----------------------------------------------------------------------------
# Samenvatting
# -----------------------------------------------------------------------------
echo "========================================"
echo "Resultaat in $OUT_DIR:"
ls -lh "${OUT_DIR}"/*.bam 2>/dev/null || echo "  (geen BAM bestanden)"
echo "Klaar: $(date)"
echo "========================================"
