# Slash

File manager nativo per macOS (SwiftUI), ispirato a Tilde: split view con tab, Spaces, cartelle fissate,
command palette (⌘K), proprietà personalizzate, viste per cartella, nickname, Live Groups, operazioni immagini.

## Installare
1. Vai su **Releases** del repo e scarica `Slash.zip`.
2. Decomprimi e trascina `Slash.app` in Applicazioni.
3. Primo avvio: tasto destro → **Apri** (l'app non è notarizzata da Apple). Se macOS la blocca:
   Impostazioni di Sistema → Privacy e sicurezza → "Apri comunque".
4. Da lì in poi si aggiorna da sola (o menu Slash → *Check for Updates…*).

## Scorciatoie
⌘K palette · ⌘T nuovo tab · ⌘W chiudi tab · ⌘D dividi · ⌘[ / ⌘] indietro/avanti · ⌘↑ cartella superiore · Spazio Quick Look

## Sviluppo
`swift run` (macOS 14+, Xcode 15+) oppure `scripts/build-app.sh 1.0.0`. Ogni push su `main` pubblica una release.
Analisi di Tilde: `docs/REVERSE_ENGINEERING.md`.
