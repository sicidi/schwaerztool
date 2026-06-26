# Gandalf, der Graubalken

Kleines natives macOS-Menüleisten-Tool (Apple Silicon) zum dauerhaften Unkenntlichmachen
sensibler Stellen in einem Foto/Bild – mit einem **grau-melierten Balken**, der sich tonal
an die Umgebung anpasst.

## Bauen

```bash
bash build.sh
```

Erzeugt `build/Gandalf, der Graubalken.app` (interner Binary-Name: `Schwaerzen`). Starten:

```bash
open "build/Gandalf, der Graubalken.app"
```

In der Menüleiste erscheint ein 👁️-Symbol (durchgestrichenes Auge). Die App hat kein Dock-Symbol.

## Benutzen

1. **Bild laden** – auf eine dieser drei Arten:
   - Bild aus dem Finder **auf das Menüleisten-Symbol ziehen** (Drag & Drop)
   - Menü → **Bild öffnen …**
   - Menü → **Bild aus der Vorschau laden** (übernimmt das gerade in Apples Vorschau geöffnete Bild;
     beim ersten Mal fragt macOS nach der Erlaubnis, die Vorschau zu steuern)
2. Im Fenster mit der Maus **Rechtecke über die sensiblen Stellen ziehen** – jede Stelle wird
   sofort mit grauem, an die Umgebung angepasstem Rauschen abgedeckt. Mehrere Rechtecke sind möglich.
   - **Letzten entfernen** (⌘Z) / **Alle entfernen** / **Esc** bricht das aktuelle Aufziehen ab
3. **Speichern** (⌘S) – legt eine Kopie `<Name>_geschwaerzt.<Endung>` **neben dem Original** an.
   Das Original bleibt unverändert.

## Wichtig

- Die Schwärzung wird **fest in die Bildpixel eingebrannt** (nicht rückgängig machbar, nicht rekonstruierbar).
- Beim Speichern werden **EXIF-Metadaten entfernt** (z. B. GPS-Ort) – gut für sensible Inhalte.
- Format: JPEG bleibt JPEG, alles andere wird als PNG gespeichert. Volle Originalauflösung bleibt erhalten.
- In Apples Vorschau selbst lässt sich technisch nicht hineinzeichnen – deshalb das eigene kleine Fenster.

## Weitergabe an Kollegen (DMG)

```bash
bash build-dmg.sh
```

Erzeugt `dist/Gandalf-der-Graubalken-1.0.dmg` (App + „Programme"-Verknüpfung + „Erste Schritte.txt").
Apple Silicon only. Da die App ad-hoc signiert (nicht notarisiert) ist, müssen Kollegen sie beim
ersten Start einmal über **Systemeinstellungen → Datenschutz & Sicherheit → „Dennoch öffnen"** freigeben.

## App-Icon neu erzeugen (optional)

```bash
bash tools/make-icon.sh
```

Rendert das Icon und baut `Resources/AppIcon.icns`.

## Autostart (optional)

Systemeinstellungen → Allgemein → Anmeldeobjekte → die App hinzufügen.
Oder die App nach `/Programme` verschieben.
