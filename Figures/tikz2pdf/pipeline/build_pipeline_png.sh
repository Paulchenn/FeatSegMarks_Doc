##### filepath: Figures/tikz2pdf/diagram/build_pipeline_png.sh
#!/usr/bin/env bash
set -euo pipefail

# Pfade (relativ zum Skript-Standort)
WORKDIR="$(cd "$(dirname "$0")" && pwd)"
TEXFILE="pipeline_standalone.tex"
PDF="${TEXFILE%.tex}.pdf"
PNG_BASE="pipeline"
OUTDIR="$WORKDIR"

echo "Arbeitsverzeichnis: $WORKDIR"

# 1) Kompilieren (latexmk, fällt zurück auf pdflatex wenn nötig)
if command -v latexmk >/dev/null 2>&1; then
  echo "Kompliziere mit latexmk..."
  (cd "$WORKDIR" && latexmk -pdf -silent -f "$TEXFILE")
else
  echo "latexmk nicht gefunden — verwende pdflatex (2 Läufe)..."
  (cd "$WORKDIR" && pdflatex -interaction=nonstopmode -halt-on-error "$TEXFILE")
  (cd "$WORKDIR" && pdflatex -interaction=nonstopmode -halt-on-error "$TEXFILE")
fi

# 2) PDF -> PNG (pdftocairo aus poppler liefert sauberen Raster-Export)
if command -v pdftocairo >/dev/null 2>&1; then
  echo "Erzeuge PNG mit pdftocairo (300 DPI)..."
  (cd "$WORKDIR" && pdftocairo -singlefile -png -r 300 "$PDF" "$PNG_BASE")
  PNG="$OUTDIR/${PNG_BASE}.png"
elif command -v convert >/dev/null 2>&1; then
  echo "pdftocairo nicht gefunden — benutze ImageMagick convert (300 DPI)..."
  (cd "$WORKDIR" && convert -density 300 "$PDF" -quality 90 "${PNG_BASE}.png")
  PNG="$OUTDIR/${PNG_BASE}.png"
else
  echo "Weder pdftocairo noch convert verfügbar. Bitte installiere poppler oder ImageMagick."
  exit 2
fi

echo "PNG erzeugt: $PNG"

# Optional: aufräumen (auskommentieren, falls du die Hilfsdateien behalten möchtest)
# (cd "$WORKDIR" && latexmk -c)

echo "Fertig."