# Tacho 🏎️

Geschwindigkeitsmesser für iOS 26 im Liquid-Glass-Design.

## Funktionen
- **Analoges Tacho**, **Digitalanzeige** mit Segmentbalken und **HUD-Modus** (gespiegelt für die Windschutzscheibe)
- **Automatische Erkennung**: Stillstand, Gehen, Rennen, Fahrrad, E-Scooter, Auto, Zug, Flugzeug
  (iOS-Bewegungsdaten + GPS-Geschwindigkeitsprofil + Vibrations-/Rhythmusanalyse), manuell überschreibbar
- **Routen aufzeichnen** inkl. Hintergrundbetrieb, Auto-Pause, Höhenmeter
- **Verlauf** mit Suche, Filter, nach Geschwindigkeit eingefärbter Karte, Geschwindigkeits- & Höhendiagramm
  (Diagramm-Scrubbing zeigt die Stelle auf der Karte), GPX-Export
- **Orte & Räume**: Straße/Stadt/POI (z. B. Bahnhof), Umgebung (freier Himmel / Stadt / Innenraum-Tunnel),
  **Etagenerkennung** per Barometer, Luftdruck
- **Sprint-Messung** 0–20 … 0–200 km/h mit Bestenliste
- **Rekorde**: Höchstwerte je Fortbewegungsart, Wochenstatistik
- Live-Karte, Geschwindigkeitswarnung mit Haptik, G-Kraft, Kompass, 5 Farbschemata, km/h · mph · m/s · kn

## Build
GitHub Actions (`.github/workflows/build-ipa.yml`) generiert das Projekt mit XcodeGen, baut unsigniert
und veröffentlicht `Tacho.ipa` als Release. Installation per AltStore / Sideloadly / TrollStore.
