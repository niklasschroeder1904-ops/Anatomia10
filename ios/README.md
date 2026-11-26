# Anatomia als iPhone-App (Xcode)

Das Xcode-Projekt verpackt die Web-App in eine echte iPhone/iPad-App. Beim Bauen werden
`index.html`, die Übersetzungen, alle Bilder und 3D-Modelle aus dem Hauptordner des Repos
in die App kopiert – die App läuft danach komplett offline.

Was die App kann, was Safari nicht kann:

- **Eigene Vibrationsmuster** für jede Funktion (Tabelle unten). Safari erlaubt Webseiten auf
  dem iPhone keine Vibration, nur einen einzelnen Tick.
- Sonst ist alles gleich wie im Browser (gleiche Lektionen, gleiches Aussehen).

## Vorbereitung (vor dem Termin am Mac)

- **Xcode** aus dem Mac App Store laden (kostenlos). Der Download ist groß (mehrere GB),
  also früh starten. Der Mac braucht ein aktuelles macOS, damit das neueste Xcode läuft –
  Xcode muss zur iOS-Version des iPhones passen.
- Eine **Apple-ID** reicht (kostenlos). Ein bezahlter Entwickler-Account (99 €/Jahr) ist nur
  für den App Store nötig.
- iPhone und Kabel mitnehmen.
- **Fortschritt sichern** (siehe unten), damit er in die App kommt.

## Schritt für Schritt am Mac

1. Xcode einmal öffnen, Lizenz bestätigen; wenn Xcode fragt, die **iOS**-Komponenten laden.
2. Repo holen (Terminal):
   ```
   git clone https://github.com/niklasschroeder1904-ops/Anatomia10.git
   ```
   oder auf GitHub „Code → Download ZIP“ und entpacken. Wichtig: das **ganze** Repo,
   nicht nur den Ordner `ios`.
3. `ios/Anatomia.xcodeproj` doppelklicken (öffnet Xcode).
4. Xcode → Settings → **Accounts** → „+“ → Apple-ID anmelden.
5. Links auf „Anatomia“ (blaues Projekt) → Target „Anatomia“ → **Signing & Capabilities** →
   bei **Team** die eigene Apple-ID wählen („Personal Team“).
   Meldet Xcode, dass die Bundle ID vergeben ist: `de.anatomia.app` in etwas Eigenes ändern,
   z. B. `de.niklas.anatomia`.
6. iPhone per Kabel anschließen, am iPhone „Diesem Computer vertrauen“.
   Dann am iPhone den **Entwicklermodus** einschalten: Einstellungen → Datenschutz & Sicherheit →
   Entwicklermodus (der Punkt erscheint erst, nachdem das iPhone einmal mit Xcode verbunden war),
   iPhone startet neu.
7. In Xcode oben das eigene iPhone als Ziel wählen und ▶︎ drücken (⌘R). Das erste Bauen
   dauert ein paar Minuten.
8. Beim ersten Mal am iPhone: Einstellungen → Allgemein → **VPN & Geräteverwaltung** →
   den Entwickler (eigene Apple-ID) → „Vertrauen“. Danach startet die App.

Nur ausprobieren ohne iPhone: oben einen Simulator wählen (z. B. „iPhone 16“) und ▶︎ drücken.
Im Simulator vibriert nichts.

Mit kostenloser Apple-ID läuft die App **7 Tage**. Danach iPhone anschließen und in Xcode
wieder ▶︎ drücken – der Fortschritt bleibt erhalten (solange die App nicht gelöscht wird).

**Neue Version der Web-App in die App holen:** im Repo-Ordner `git pull` (oder neues ZIP)
und in Xcode wieder ▶︎ drücken.

## Fortschritt aus Safari in die App holen

Die App speichert getrennt von Safari. So kommt der Fortschritt hinüber:

1. In Safari (Web-App): **Einstellungen → Fortschritt sichern** → „In Dateien sichern“ →
   z. B. „Auf meinem iPhone“ → Sichern.
2. In der App: **Einstellungen → Fortschritt laden** → die Datei
   `anatomia-fortschritt-….json` wählen → bestätigen. Die App startet neu, mit allem:
   XP, Taler, Serie, Sterne, Wiederholungen, Einstellungen.

Das geht genauso in die andere Richtung und zwischen zwei Geräten (z. B. iPhone → iPad).
Achtung: Laden **ersetzt** den Fortschritt auf dem Gerät.

## Die Vibrationen

| Moment | So fühlt es sich an |
| --- | --- |
| Richtige Antwort | kurzes „Erfolg“-Doppeltippen |
| Falsche Antwort | „Fehler“-Rattern (drei schnelle Stöße) |
| 5, 10, 15 richtig hintereinander | vier Tipper, immer stärker, dann „Erfolg“ |
| Runde geschafft | zwei mittlere Tipper, ein starker, dann „Erfolg“ |
| Erste Runde des Tages (Serie +1) | sanft → mittel → zweimal stark |
| Neue Stufe erreicht | drei starke Schläge, dann ein langes Brummen |
| Taler abgeholt | drei harte Münz-Klicks, immer stärker, dann „Erfolg“ |
| Herzen aufgebraucht | Warnung, dann ein dumpfes Brummen |
| Karteikarte „Gewusst“ | ein leichter Tipper |
| Karteikarte „Nochmal“ | zwei weiche Tipper |
| Im Shop gekauft / Lektion freigeschaltet | ein mittlerer Tipper, dann „Erfolg“ |
| Joker benutzt (50:50 oder Buchstabe) | ein harter und ein leichter Klick |

Ausschalten: in der App **Einstellungen → Vibration**. Vibriert gar nichts: am iPhone
Einstellungen → Töne & Haptik → **Systemhaptik** einschalten.

Die Muster stehen in `index.html` (`HAP_SETS`): jeder Schritt ist
`[Art, Verzögerung in ms, Stärke 0–1, Länge in s]`. Arten: `light`, `medium`, `heavy`,
`soft`, `rigid` (Tipper), `success`, `warning`, `error` (Muster von iOS), `select`
(feinster Tick), `buzz` (Brummen). Android-Handys bekommen dieselben Momente als
An/Aus-Zeiten (`ms`).

## Prüfung bei GitHub

Bei jeder Änderung im Ordner `ios/` baut GitHub die App auf einem Mac und startet sie
fünfmal im iPhone-Simulator (Englisch, Deutsch, Schwedisch, Spanisch, Norwegisch): GitHub → **Actions** →
„iPhone-App prüfen“. Die Bildschirmfotos liegen dort unter „Artifacts“. Ein grüner Haken
heißt: Der Swift-Code lässt sich bauen, und die App zeigt die Web-App.

## Technik

- `Anatomia/WebAppView.swift`: das Fenster mit der Web-App (WKWebView). Die Dateien kommen
  aus dem Ordner „Web“ in der App (Adresse `anatomia://app/`). Dazu:
  - `HapticBridge` („haptic“): spielt die Vibrationsmuster der Seite.
  - `ShareBridge` („share“): gibt die Sicherungsdatei an das Teilen-Menü.
  - `SplashBridge` („splash“): die App ist auf dem Bildschirm, die Ladeanimation geht.
  - `Coordinator`: zeigt `alert()`/`confirm()` der Seite als iOS-Dialoge (sonst würde z. B.
    „Prüfung abbrechen?“ nie gefragt).
- Start: Der Startbildschirm von iOS ist das Blau der Ladeanimation (Farbe `LaunchBackground`
  in `Assets.xcassets`, eingetragen in `Info.plist`). Danach zeigt `Anatomia/SplashView.swift` die
  Ladeanimation (Knochen, schlagendes Herz mit EKG, Stern – wie in der Web-App), von der App selbst
  gezeichnet: Die Web-Ansicht könnte sie nur zwischen den großen Skripten der Seite zeichnen, sie
  würde beim Laden stehen bleiben. Sobald die App auf dem Bildschirm ist, meldet die Seite das
  („splash“, `SplashBridge`) und die Animation blendet aus. iOS merkt sich den Startbildschirm: Zeigt
  die App nach dem Update noch den alten, hilft einmal das iPhone neu zu starten (nicht die App
  löschen – das löscht den Fortschritt).
- Build-Phase „Copy web app“: kopiert `*.html`, `*.js`, Bilder und `*.glb` aus dem Hauptordner.
- `Anatomia/Info.plist`: nennt die Sprachen der Web-App (Deutsch, Englisch, Spanisch,
  Schwedisch, Norwegisch). Nur dann meldet die Web-Ansicht der App die Sprache des iPhones, und die App
  startet von selbst in dieser Sprache. Den Rest der Info.plist erzeugt Xcode.
