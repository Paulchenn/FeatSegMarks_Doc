# Berechnung von Merkmalspunkten aus Segmentierungsmasken für Visual Servoing

[![LaTeX](https://img.shields.io/badge/LaTeX-biber%20%7C%20pdflatex-informational.svg?logo=latex&logoColor=white)](https://www.latex-project.org/)
[![Hochschule Karlsruhe](https://img.shields.io/badge/HKA-Fakultät%20MMT-red.svg)](https://www.h-ka.de/)
[![Abschluss](https://img.shields.io/badge/Master-RKIM-blue.svg)](https://www.h-ka.de/)
[![Status](https://img.shields.io/badge/Status-Abgeschlossen-brightgreen.svg)]()

> **Forschungs- und Entwicklungsprojekt (F&E)**  
> Masterstudiengang *Robotik und Künstliche Intelligenz in der Produktion* (RKIM)  
> Fakultät für Maschinenbau und Mechatronik | Hochschule Karlsruhe (HKA)  
> **Projektkürzel:** `25ss_CF_FeaturesSegMasks`  
> **Abgabedatum:** 25. Februar 2025

---

## Inhaltsverzeichnis

- [Überblick](#überblick)
- [Motivation & Problemstellung](#motivation--problemstellung)
- [Forschungsfragen](#forschungsfragen)
- [Methodik & Architekturkonzepte](#methodik--architekturkonzepte)
  - [1. Differentiable Sobel-based Shape Encoding (DS-EMSE)](#1-differentiable-sobel-based-shape-encoding-ds-emse)
  - [2. Online-Augmentierung & Shape Deformation (TSD/TSG)](#2-online-augmentierung--shape-deformation-tsdtsg)
  - [3. Generatorarchitektur & Latenter Raum](#3-generatorarchitektur--latenter-raum)
  - [4. Diagnosetool zur Informationsattribution](#4-diagnosetool-zur-informationsattribution)
  - [5. Nachgelagertes Matching mit xFeat](#5-nachgelagertes-matching-mit-xfeat)
- [Zentrale Ergebnisse & Erkenntnisse](#zentrale-ergebnisse--erkenntnisse)
- [Repository-Struktur](#repository-struktur)
- [Kompilierung & Bauanleitung](#kompilierung--bauanleitung)
  - [Voraussetzungen](#voraussetzungen)
  - [Kompilierung via CLI](#kompilierung-via-cli)
  - [Konfiguration für VS Code (LaTeX Workshop)](#konfiguration-für-vs-code-latex-workshop)
- [Projektbeteiligte & Betreuung](#projektbeteiligte--betreuung)
- [Literatur & Referenzen](#literatur--referenzen)

---

## Überblick

Bildbasierte Regelungsprozesse (**Visual Servoing**) in der Robotik hängen elementar von der Wiederholbarkeit, Stabilität und Lokalisierungsgenauigkeit visueller Merkmale (Keypoints und Deskriptoren) ab. Klassische Merkmalsdetektoren (wie SIFT oder ORB) scheitern in anspruchsvollen industriellen Umgebungen häufig an drastischen Beleuchtungs-, Textur- und Blickwinkelwechseln. Moderne, lernbasierte Feature-Extraktoren wie **xFeat** bieten zwar eine exzellente Inferenzgeschwindigkeit, weisen jedoch häufig einen ausgeprägten **Texture Bias** auf: Sie stützen sich primär auf hochfrequente Oberflächenmuster anstelle robuster geometrischer Konturen und Formen (**Shape Bias**).

Dieses Projekt untersucht und implementiert eine **generative Vorverarbeitungspipeline**, die Bilder online so transformiert, dass formtragende Kanteninformationen betont und irrelevante Texturen gezielt abgeschwächt werden. Untersucht wird die Kopplung zwischen Kanten- und Texturpfaden, einer differenzierbaren Kantenextraktion (**DS-EMSE**), einer Thin-Plate-Spline-basierten Formdeformation (**TSD**) und dem modernen Feature-Matching-Framework **xFeat** auf den Datensätzen **ImageNet256** und **MegaDepth**.

---

## Motivation & Problemstellung

1. **Gestalt statt Textur als Invariante:** Für regelungstechnische Aufgaben (z. B. robotergeführtes Greifen oder Feinpositionieren) sind physische Objektkanten und Silhouetten signifikant stabilere Bezugsgrößen als wechselnde Oberflächenmuster.
2. **End-to-End-Differenzierbarkeit:** Konventionelle Kantenoperatoren stellen oft nicht-differenzierbare Barrieren im Trainingsgraph dar. Eine gradientenbasierte Optimierung erfordert differenzierbare Kantenrepräsentationen direkt im Loss-Signal.
3. **Verifizierbare Informationsnutzung:** Vor dem nachgelagerten Matching muss quantitativ nachgewiesen werden, ob der Bildgenerator tatsächlich Forminformationen gegenüber Texturinformationen priorisiert.

---

## Forschungsfragen

Die wissenschaftliche Untersuchung orientiert sich an drei Kernfragen:

- **F1 (Generatorinterne Informationsnutzung):**  
  Lässt sich durch Architektur- und Pipeline-Modifikationen nachweisen, dass das Gradientenverhältnis  
  $$\frac{\big\lVert \frac{\partial L_{\text{edge}}}{\partial E}\big\rVert}{\big\lVert \frac{\partial L_{\text{edge}}}{\partial I_{\text{txt}}}\big\rVert}$$  
  steigt und der Generator somit nachweisbar sensitiver auf Kanten ($E$) als auf Texturen ($I_{\text{txt}}$) reagiert?
- **F2 (Systemischer Einfluss auf Feature Matching):**  
  Führt eine generative, formorientierte Bildvorverarbeitung zu einer messbaren Steigerung der Matching-Güte ($\text{mAcc}$, $\text{AUC}$) von nachgelagerten Detektoren wie xFeat, oder entstehen Zielkonflikte zwischen generativer Rekonstruktion und deskriptorbasiertem Matching?
- **F3 (Auflösungs- und Domänenübertragbarkeit):**  
  Welche Auswirkungen haben Domänensprünge und Auflösungsdiskrepanzen (z. B. klassenbasiertes $256 \times 256$ ImageNet vs. hochauflösende szenische MegaDepth-Daten) auf die Wirksamkeit der Pipeline?

---

## Methodik & Architekturkonzepte

```
                        +---------------------------------------+
                        |        Eingabebild / Maske            |
                        +---------------------------------------+
                                     |             |
                     (Kantenpfad)    |             | (Texturpfad)
                                     v             v
                           +---------------+  +----------------+
                           |    DS-EMSE    |  | Thin-Plate     |
                           | (Diff. Sobel) |  | Spline (TSD)   |
                           +---------------+  +----------------+
                                     \             /
                                      \           /
                                       v         v
                         +-----------------------------------+
                         |      Generator (VGG16-Encoder     |
                         |      + Decoder m. Skip/Pooling)   |
                         +-----------------------------------+
                                           |
                                           v
                         +-----------------------------------+
                         |      Generiertes Bild (Form+)     |
                         +-----------------------------------+
                                           |
                                           v
                         +-----------------------------------+
                         |       xFeat Feature Matching      |
                         |      & Visual Servoing Metriken   |
                         +-----------------------------------+
```

### 1. Differentiable Sobel-based Shape Encoding (DS-EMSE)
Als Weiterentwicklung bestehender Ansätze (z. B. EMSE nach He et al., ICCV 2023) wurde ein differenzierbarer Sobel-basierter Kantenextraktionsoperator implementiert. Dieser erlaubt die gradientengestützte End-to-End-Rückführung des Kantenverlusts $L_{\text{edge}}$ direkt in das generative Netzwerk.

### 2. Online-Augmentierung & Shape Deformation (TSD/TSG)
Durch **Thin-Plate Spline (TPS)**-Deformationen (**TSD**) und kontrollierte Textur-Shape-Generierung (**TSG**) werden Form- und Texturkomponenten entkoppelt. Dies zwingt das Modell, robuste Invarianten zu erlernen, anstatt sich auf statische Korrelationen im Trainingsdatensatz zu verlassen.

### 3. Generatorarchitektur & Latenter Raum
- **Encoder:** VGG16-basierter Feature-Extractor zur hierarchischen Merkmalsgewinnung.
- **Decoder:** Rekonstruktionspfad mit Skip-Connections und gespeicherten Pooling-Indizes (angelehnt an SegNet/U-Net-Konzepte) zur Erhaltung scharfer Kantenübergänge.
- **Stochastik:** Gezielte Rauschinjektion im latenten Raum zur Förderung von Diversität und Robustheit im GAN-Setup.

### 4. Diagnosetool zur Informationsattribution
Um den tatsächlichen Lernerfolg label-frei und quantitativ zu überprüfen, wurde eine Gradienten-Diagnosemetrik eingeführt:
$$\mathcal{R}_{E/I} = \frac{\left\lVert \frac{\partial L_{\text{edge}}}{\partial E} \right\rVert}{\left\lVert \frac{\partial L_{\text{edge}}}{\partial I_{\text{txt}}} \right\rVert}$$
Ein Anstieg von $\mathcal{R}_{E/I}$ signalisiert die erfolgreiche Fokussierung des Netzwerks auf geometrische Formkanten gegenüber volatilen Texturdetails.

### 5. Nachgelagertes Matching mit xFeat
Die generierten Repräsentationen werden dem schnellen Feature-Extraktor **xFeat** (*Potje et al., CVPR 2024*) zugeführt. Evaluiert werden u. a. Homographie-Schätzungen, relative Posen, **Mean Accuracy ($\text{mAcc}$)** bei verschiedenen Fehlerschwellen ($1\text{px}, 3\text{px}, 5\text{px}, 10\text{px}$) sowie **Area Under Curve ($\text{AUC}$)**.

---

## Zentrale Ergebnisse & Erkenntnisse

1. **Bestätigung des internen Shape-Shifts:**
   - Die Attributionsanalyse belegt einen signifikanten Anstieg des Gradientenverhältnisses $\mathcal{R}_{E/I}$ von $0{,}40$ auf bis zu $0{,}50$ in optimierten Konfigurationen (im Vergleich zu $0{,}14$ in der Baseline). Die Architektur- und Loss-Modifikationen sensibilisieren den Generator erfolgreich für strukturelle Kanten.
2. **Die Zielkonflikt-Diskrepanz (Objective Incongruity):**
   - Trotz intern nachgewiesener Formfokussierung führt das Vorschalten des Generators in der reinen Null-Schritt-Inferenz zu einem Leistungsabfall beim deskriptorgetriebenen Feature-Matching (z. B. $\text{mAcc}@10$ von $74{,}7\,\%$ auf $38{,}2\,\%$).
   - *Ursachenanalyse:* 
     - **Auflösungs-Mismatch:** Der Generator trainiert auf $256 \times 256$, während xFeat feine Subpixel-Details in hochauflösenden Szenen benötigt.
     - **Domänen-Gap:** Der Transfer von klassenbasierten Objektdatensätzen (ImageNet) zu szenenbasierten Geometriedatensätzen (MegaDepth) erzeugt strukturelle Informationsverluste.
     - **Verlustfunktions-Divergenz:** Ein rein kanten- und pixelbasierter generativer Rekonstruktionsverlust optimiert nicht inhärent die Gradientenstrukturen, die für deskriptive Keypoint-Wiederholbarkeit entscheidend sind.
3. **Ausblick & vorgeschlagene Folgekonzepte:**
   - Direkte Kopplung des Feature-Matching-Loss in das Generator-Training (End-to-End Keypoint-Aware Loss).
   - Multi-Scale-Architekturen zur Vermeidung des 256px-Auflösungsflaschenhalses.
   - Explizite Keypoint-Positionssteuerung (Konzept 3).

---

## Repository-Struktur

```text
FeatSegMarks_Doc/
├── thesis.tex                    # Haupt-LaTeX-Dokument (Kompilierungs-Einstiegspunkt)
├── bibliography.bib              # Literaturdatenbank (BibLaTeX/Biber)
├── Glossar.bib                   # Glossar-Einträge
├── copyAndRename_thesis.bat      # Windows-Automatisierungsskript für PDF-Export
├── TeXFiles/                     # Strukturierte Kapitel und Teildokumente
│   ├── 000_Settings.tex          # Globale Variablen, Farben, Metadaten & TikZ-Stile
│   ├── 001_Titlepage.tex         # Deckblatt (HKA-Layout)
│   ├── 002_NDNotice.tex          # Sperrvermerk / Vertraulichkeitshinweis
│   ├── 004_Acronyms.tex          # Abkürzungsverzeichnis (\acro)
│   ├── 005_Glossar.tex           # Glossar-Konfiguration
│   ├── 010_Kurzfassung.tex       # Abstract & Kurzfassung
│   ├── 020_Einfuehrung.tex       # Problemstellung, Forschungsfragen & Aufbau
│   ├── 030_StandDerTechnik.tex   # CNNs, GANs, TPS, xFeat, Visual Servoing
│   ├── 040_EntwicklungDerMethode.tex # Analyse He-Paper, DS-EMSE, Problemlösungen
│   ├── 041_Kopplung_SDbOA_xFeat.tex  # Kopplungskonzept zwischen Generator & xFeat
│   ├── 050_KonzeptArchitektur.tex    # Generator, Diagnosetool, ImageNet & MegaDepth
│   ├── 060_ErgebnisseEvaluation.tex  # Quantitative Evaluation (mAcc, AUC, R_E/I)
│   ├── 070_DiskussionAusblick.tex    # Kritische Würdigung, Limitationen & 3 Konzepte
│   ├── 100_Zusammenfassung.tex       # Zusammenfassung der Resultate
│   ├── 110_Anhang.tex                # Zusätzliche Tabellen, Messreihen & Code
│   └── 120_Declaration.tex           # Eidesstattliche Erklärung
├── Figures/                      # Abbildungen und Vektorgrafiken
│   ├── jpg/                      # Bildmaterial
│   ├── pdf/                      # Vektordiagramme im PDF-Format
│   ├── png/                      # Ergebnisplots und Trainingsverläufe
│   ├── svg/                      # SVG-Quellen
│   ├── tikz/                     # TikZ-Quellcodes für Flussdiagramme
│   └── tikz2pdf/                 # Kompilierte TikZ-Einzelseiten
├── Praesentation/                # Begleitende Grafiken & Folienmaterial
└── README.md                     # Projektdokumentation
```

---

## Kompilierung & Bauanleitung

Das Dokument basiert auf KOMA-Script (`scrreprt`), nutzt `biblatex` mit dem Backend **biber** und bindet Vektorgrafiken sowie TikZ-Diagramme ein.

### Voraussetzungen

Eine vollständige TeX-Distribution:
- **TeX Live** (Linux / Windows) oder **MacTeX** (macOS)
- **MikTeX** (Alternative für Windows)
- Enthaltene Werkzeuge: `pdflatex`, `biber`, `makeglossaries`

### Kompilierung via CLI

Am zuverlässigsten erfolgt der Build mit `latexmk`, welches Abhängigkeiten und Referenzen automatisch auflöst:

```bash
# Automatischer Build mit latexmk
latexmk -pdf -synctex=1 -interaction=nonstopmode thesis.tex

# Aufräumen von Hilfsdateien
latexmk -c
```

Alternativ der manuelle Standard-Kompilierungszyklus:

```bash
# 1. Erster Durchlauf: Erzeugung der Hilfsdateien
pdflatex -interaction=nonstopmode thesis.tex

# 2. Bibliographie erstellen
biber thesis

# 3. Zweiter & dritter Durchlauf für Querverweise, Abkürzungen & Seitenzahlen
pdflatex -interaction=nonstopmode thesis.tex
pdflatex -interaction=nonstopmode thesis.tex
```

### Konfiguration für VS Code (LaTeX Workshop)

In `.vscode/settings.json` kann folgende Recipe-Definition hinterlegt werden:

```json
{
  "latex-workshop.latex.recipes": [
    {
      "name": "latexmk",
      "tools": ["latexmk"]
    }
  ],
  "latex-workshop.latex.tools": [
    {
      "name": "latexmk",
      "command": "latexmk",
      "args": [
        "-pdf",
        "-synctex=1",
        "-interaction=nonstopmode",
        "-file-line-error",
        "%DOC%"
      ]
    }
  ]
}
```

---

## Projektbeteiligte & Betreuung

### Autoren (Projektgruppe)
- **Analena Krieger, B. Eng.** (Matrikelnr. 100551)
- **Julia Kramme, B. Eng.** (Matrikelnr. 100381)
- **Paul Glaser, B. Eng.** (Matrikelnr. 100215)
- **Tim Schäfer, B. Eng.** (Matrikelnr. 71606)

### Akademische Betreuung
- **Erstprüfer / Projektleiter:** Prof. Dr.-Ing. Christian Friedrich
- **Wissenschaftlicher Mitarbeiter / Betreuer:** Dominik Werman, M. Sc.
- **Zweitprüfer:** Prof. Dr.-Ing. Robert Weiß

**Institution:**  
Hochschule Karlsruhe – University of Applied Sciences  
Fakultät für Maschinenbau und Mechatronik  
Masterstudiengang Robotik und Künstliche Intelligenz in der Produktion (RKIM)

---

## Literatur & Referenzen

- **He et al. (2023):** *Shift from Texture-bias to Shape-bias: Edge Deformation-based Augmentation for Robust Object Recognition.* Proceedings of the IEEE/CVF International Conference on Computer Vision (ICCV), S. 1526–1535. [DOI: 10.1109/ICCV51070.2023.00147](https://doi.org/10.1109/ICCV51070.2023.00147)
- **Potje et al. (2024):** *Accelerated Features for Lightweight and Real-Time Visual SLAM and Visual Servoing (xFeat).* Proceedings of the IEEE/CVF Conference on Computer Vision and Pattern Recognition (CVPR). [arXiv:2404.19174](https://arxiv.org/abs/2404.19174)
- **Chaumette & Hutchinson (2006):** *Visual servo control. I. Basic approaches.* IEEE Robotics & Automation Magazine.
