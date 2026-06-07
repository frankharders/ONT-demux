#!/usr/bin/env bash
# =============================================================================
# 05_methylation_native96.sh
#
# Dorado methylatie-basecalling + demultiplexing via read-ID filtering
# Kit:    Native Barcoding Kit 96 V14 (SQK-NBD114-96)
#
# Workflow:
#   1. Basecalling met mod-modellen (sup + 4mC_5mC + 6mA) → tmp mod-BAM
#   2. Simpele demux → per-barcode BAM (alleen voor read-ID lijsten)
#   3. Per barcode: filter read-IDs uit mod-BAM → barcode-specifieke mod-BAM
#
# Waarom deze aanpak:
#   - Methylatie MM/ML tags zitten alleen in BAM, niet in FASTQ
#   - Je hebt een per-stam referentie nodig voor modkit pileup
#   - Assembleer eerst met 01/03_demux scripts, gebruik die assembly als ref
#   - Dan map je de barcode-mod-BAM tegen de eigen assembly → modkit pileup
#
# Relevante modificaties voor prokaryoten (o.a. Brucella):
#   - 6mA  : N6-methyladenosine, motief GANTC (CcrM methyltransferase)
#             Dominant in Brucella, cel-cyclus gereguleerd
#   - 4mC  : N4-methylcytosine, restrictie-modificatie systemen
#   - 5mC  : C5-methylcytosine, minder frequent in bacteriën
#   Alle drie worden gedetecteerd met: sup,4mC_5mC,6mA
#
# Vereiste tools:
#   - dorado (pad hieronder)
#   - samtools (in PATH)
#
# Input:  ./pod5/            (map met .pod5 bestanden)
#         ./01_demuxed/      (output van demux script, voor read-ID lijsten)
# Output: ./02_methylation/  (per-barcode mod-BAM klaar voor modkit pileup)
# =============================================================================
set -euo pipefail
shopt -s nullglob

# -----------------------------------------------------------------------------
# Configuratie — pas hier aan, niet op de CLI
# -----------------------------------------------------------------------------
DORADO="/data/GIT/dorado-2.0.0-linux-x64/bin/dorado"
NGS_PROJECT="NGS-YY-XX"

POD5_DIR="$(pwd)/pod5"
DEMUX_DIR="$(pwd)/01_demuxed"       # output van een eerder demux script
OUT_DIR="$(pwd)/02_methylation"
TMP_MOD_BAM="$(pwd)/tmp_mod_calls.bam"

KIT="SQK-NBD114-96"

# Modificatie modellen — all-context voor prokaryoten
# 4mC_5mC detecteert beide cytosine modificaties in alle sequentie-contexten
# 6mA detecteert N6-methyladenosine in alle contexten
# Niet gebruiken: 5mCG_5hmCG → dat is een eukaryoot/CpG-context model
MOD_MODEL="sup,4mC_5mC,6mA"

MIN_QSCORE=10

# -----------------------------------------------------------------------------
# Validatie
# -----------------------------------------------------------------------------
[[ -x "$DORADO" ]]   || { echo "ERROR: dorado niet gevonden: $DORADO"; exit 1; }
[[ -d "$POD5_DIR" ]]  || { echo "ERROR: pod5 map niet gevonden: $POD5_DIR"; exit 1; }
[[ -d "$DEMUX_DIR" ]] || { echo "ERROR: demux output niet gevonden: $DEMUX_DIR"; exit 1; }

command -v samtools &>/dev/null || { echo "ERROR: samtools niet in PATH"; exit 1; }

pod5_files=("${POD5_DIR}"/*.pod5)
(( ${#pod5_files[@]} > 0 )) || { echo "ERROR: geen .pod5 bestanden in $POD5_DIR"; exit 1; }

demux_bams=("${DEMUX_DIR}"/*.bam)
(( ${#demux_bams[@]} > 0 )) || { echo "ERROR: geen BAM bestanden in $DEMUX_DIR"; exit 1; }

mkdir -p "$OUT_DIR"

echo "========================================"
echo "Project  : $NGS_PROJECT"
echo "Script   : $(basename "$0")"
echo "Kit      : $KIT"
echo "Modellen : $MOD_MODEL"
echo "Barcodes : ${#demux_bams[@]} BAM bestanden gevonden in $DEMUX_DIR"
echo "Pod5     : ${#pod5_files[@]} bestanden"
echo "Output   : $OUT_DIR"
echo "Gestart  : $(date)"
echo "========================================"

# -----------------------------------------------------------------------------
# Stap 1: Basecalling met modificatie modellen → tijdelijk mod-BAM
# -----------------------------------------------------------------------------
# Noot: GEEN --emit-fastq hier — MM/ML methylatie-tags werken alleen in BAM.
# Noot: GEEN --barcode-both-ends hier — we doen geen demux in deze stap,
#       we gebruiken read-IDs van de al uitgevoerde demux.
echo "[1/3] Basecalling + methylatie calling..."

"$DORADO" basecaller \
    --device cuda:all \
    --min-qscore "$MIN_QSCORE" \
    --emit-summary \
    "$MOD_MODEL" \
    "$POD5_DIR" \
    > "$TMP_MOD_BAM"

echo "  Klaar: $(date)"

# -----------------------------------------------------------------------------
# Stap 2 + 3: Per barcode — read-IDs extracten en mod-BAM filteren
# -----------------------------------------------------------------------------
# samtools view -N: filtert op een lijst van read-IDs (één per regel)
# unclassified.bam overslaan — geen bruikbare barcode-toewijzing
echo "[2/3] Read-IDs extracten en mod-BAM filteren per barcode..."

for barcode_bam in "${DEMUX_DIR}"/*.bam; do
    barcode_name=$(basename "$barcode_bam" .bam)

    # unclassified overslaan
    if [[ "$barcode_name" == *"unclassified"* ]]; then
        echo "  Overgeslagen: $barcode_name"
        continue
    fi

    readid_file="${OUT_DIR}/${barcode_name}_readids.txt"
    out_bam="${OUT_DIR}/${barcode_name}_mod.bam"

    echo "  Verwerken: $barcode_name"

    # Read-IDs uit de demux BAM halen (kolom 1 van SAM)
    samtools view "$barcode_bam" \
        | cut -f1 \
        | sort -u \
        > "$readid_file"

    n_reads=$(wc -l < "$readid_file")
    echo "    Read-IDs: $n_reads"

    if (( n_reads == 0 )); then
        echo "    Waarschuwing: geen reads voor $barcode_name, overgeslagen"
        rm -f "$readid_file"
        continue
    fi

    # Mod-BAM filteren op deze read-IDs → barcode-specifieke mod-BAM
    # -N: read-ID bestand
    # -b: BAM output
    samtools view -b -N "$readid_file" "$TMP_MOD_BAM" \
        > "$out_bam"

    echo "    Mod-BAM: $out_bam"
done

echo "  Klaar: $(date)"

# -----------------------------------------------------------------------------
# Opruimen tijdelijk BAM
# -----------------------------------------------------------------------------
echo "[3/3] Opruimen..."
rm -f "$TMP_MOD_BAM"

# -----------------------------------------------------------------------------
# Samenvatting + volgende stap
# -----------------------------------------------------------------------------
echo "========================================"
echo "Resultaat in $OUT_DIR:"
ls -lh "${OUT_DIR}"/*_mod.bam 2>/dev/null || echo "  (geen mod-BAM bestanden)"
echo ""
echo "Volgende stap per barcode:"
echo "  1. samtools fastq <barcode>_mod.bam | flye/autocycler → assembly"
echo "  2. minimap2 -ax map-ont assembly.fa <barcode>_mod.bam | samtools sort > mapped.bam"
echo "  3. modkit pileup mapped.bam methylation.bed --ref assembly.fa"
echo "Klaar: $(date)"
echo "========================================"
