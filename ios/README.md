# Anatomia als iOS-App (Xcode)

Das Xcode-Projekt verpackt die Web-App in eine native iPhone/iPad-App (WKWebView).
Beim Bauen werden `index.html`, alle Bilder und 3D-Modelle aus dem Hauptordner des
Repos in die App kopiert – die App läuft danach komplett offline.

## Starten auf dem Mac

1. Repo holen (Terminal):
   ```
   git clone https://github.com/niklasschroeder1904-ops/Anatomia10.git
   ```
   oder auf GitHub „Code → Download ZIP“ und entpacken. Wichtig: das **ganze** Repo,
   nicht nur den Ordner `ios`.
2. `ios/Anatomia.xcodeproj` doppelklicken (öffnet Xcode).
3. Oben in der Leiste ein Gerät wählen, z. B. „iPhone 16“-Simulator.
4. ▶︎ (Run) drücken bzw. ⌘R.

## Auf dem eigenen iPhone

1. iPhone per Kabel anschließen, am iPhone „Entwicklermodus“ aktivieren
   (Einstellungen → Datenschutz & Sicherheit → Entwicklermodus).
2. In Xcode links auf „Anatomia“ (blaues Projekt) → Target „Anatomia“ →
   „Signing & Capabilities“ → bei **Team** die eigene Apple-ID wählen
   (Xcode → Settings → Accounts → „+“ falls noch keine da ist).
3. Falls Xcode meldet, dass die Bundle ID vergeben ist: `de.anatomia.app` in
   etwas Eigenes ändern, z. B. `de.niklas.anatomia`.
4. iPhone oben als Ziel wählen und ▶︎ drücken. Beim ersten Mal am iPhone unter
   Einstellungen → Allgemein → VPN & Geräteverwaltung dem Entwickler vertrauen.

Mit kostenloser Apple-ID läuft die App 7 Tage, danach einfach erneut ▶︎ drücken.
