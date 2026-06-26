# Schwärzen

Kleines natives macOS-Menüleisten-Tool (Apple Silicon), um sensible Stellen in einem Foto/Bild
dauerhaft mit einem **grau-melierten Rechteck** unkenntlich zu machen.

## Bauen

```bash
bash build.sh
```

Erzeugt `build/Schwaerzen.app`. Starten:

```bash
open build/Schwaerzen.app
```

In der Menüleiste erscheint ein 👁️-Symbol (durchgestrichenes Auge).

## Benutzen

1. **Bild laden** – auf eine dieser drei Arten:
   - Bild aus dem Finder **auf das Menüleisten-Symbol ziehen** (Drag & Drop)
   - Menü → **Bild öffnen …**
   - Menü → **Bild aus der Vorschau laden** (übernimmt das gerade in Apples Vorschau geöffnete Bild;
     beim ersten Mal fragt macOS nach der Erlaubnis, die Vorschau zu steuern)
2. Im Fenster mit der Maus **Rechtecke über die sensiblen Stellen ziehen** – jede Stelle wird
   sofort mit grauem Rauschen abgedeckt. Mehrere Rechtecke sind möglich.
   - **Letzten entfernen** (⌘Z) / **Alle entfernen** / **Esc** bricht das aktuelle Aufziehen ab
3. **Speichern** (⌘S) – legt eine Kopie `<Name>_geschwaerzt.<Endung>` **neben dem Original** an.
   Das Original bleibt unverändert.

## Wichtig

- Die Schwärzung wird **fest in die Bildpixel eingebrannt** (nicht rückgängig machbar, nicht rekonstruierbar).
- Beim Speichern werden **EXIF-Metadaten entfernt** (z. B. GPS-Ort) – gut für sensible Inhalte.
- Format: JPEG bleibt JPEG, alles andere wird als PNG gespeichert. Volle Originalauflösung bleibt erhalten.
- In Apples Vorschau selbst lässt sich technisch nicht hineinzeichnen – deshalb das eigene kleine Fenster.

## Autostart (optional)

Systemeinstellungen → Allgemein → Anmeldeobjekte → `Schwaerzen.app` hinzufügen.
Oder die App nach `/Programme` verschieben.
