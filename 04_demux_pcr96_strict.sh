#!/usr/bin/env bash
# =============================================================================
# 04_demux_pcr96_strict.sh
#
# Dorado basecalling + stricte demultiplexing
# Kit:    PCR Barcoding Kit 96 V14 (SQK-PBK114-96 / SQK-PCB114-24)
# Mode:   Strikt — barcode moet aan BEIDE uiteinden gedetecteerd worden
#
# Verschil PCR vs Native barcoding:
#   - Native barcoding: barcode geligeerd aan native DNA-uiteinden
#                       → barcode aan beide uiteinden van hetzelfde fragment
#   - PCR barcoding:    barcode in de PCR-primer ingebouwd
#                       → barcode aan beide uiteinden via amplificatie
#                       → kortere inserts, hogere barcode-signaalsterkte
#                       → dorado gebruikt andere flanking-sequenties voor scoring
#
# Wanneer gebruiken:
#   - Geamplificeerd materiaal (PCR-product, amplicon sequencing)
#   - Lage input DNA hoeveelheden waarbij native ligation niet werkt
#   - Metagenomics na SISPA-amplificatie met PCR barcodes
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

# Controleer welke kit je hebt:
#   SQK-PCB114-24  → 24 barcodes, PCR V14
#   SQK-RBK114-96  → 96 barcodes, Rapid Barcoding V14 (ook PCR-gebaseerd)
# Pas aan op jouw situatie:
KIT="SQK-RBK114-96"
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
echo "Mode    : strikt PCR (barcode beide uiteinden vereist)"
echo "Pod5    : ${#pod5_files[@]} bestanden"
echo "Output  : $OUT_DIR"
echo "Gestart : $(date)"
echo "========================================"

# -----------------------------------------------------------------------------
# Stap 1: Basecalling → tijdelijk BAM
# -----------------------------------------------------------------------------
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
