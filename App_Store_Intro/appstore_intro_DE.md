# xGRC — App-Store-Texte auf Deutsch / German App Store Copy

Texte zum direkten Einfügen in App Store Connect. Jedes Feld nennt sein
Zeichenlimit; die Zahl in eckigen Klammern ist die tatsächliche Länge des Texts,
gemessen mit `len()` in Python auf dem genauen Block.

Das englische Original ist [appstore_intro.md](appstore_intro.md); diese Datei
entspricht ihm Abschnitt für Abschnitt. **Wer eine Aussage ändert, ändert sie in
allen Sprachdateien** (`appstore_intro_<LANG>.md`) — ein Eintrag, der in einer
Sprache mehr verspricht als in einer anderen, ist ein Fehler.

**App-Store-Connect-Lokalisierung: „German“ (Locale `de`).** App Store Connect
kennt nur eine deutsche Lokalisierung; Deutschland, Österreich und die Schweiz
sehen denselben Text. Er schreibt „ß“ wie die App selbst.

**Geschrieben für 1.0**, die erste Veröffentlichung, am 2026-10-21 auf
dem Stand 1.0.0, aus dem englischen Text
desselben Stands. Die offenen Punkte vor der Einreichung (Demo-Video für App
Review, Datenschutzerklärung, TESTED-ON-Zeile) stehen im englischen Original und
gelten hier genauso.

**Dieser Text ist maschinell entworfen.** Er stammt aus dem Englischen und aus den
deutschen Strings der App (`de.json`), aber **noch keine deutsche
Muttersprachlerin und kein Muttersprachler hat ihn gelesen**. Vor der
Einreichung gegenlesen lassen — Ton, Tippfehler, Fotografie-Begriffe — und danach
jedes Feld neu messen. Siehe „Noch zu klären“.

---

## Zuerst lesen — vier Dinge, an denen dieser Text scheitern kann

**1. „Ausgelöst“ heißt nur „bestätigt ausgelöst“.** Die App sagt *Ausgelöst*,
wenn die Kamera die Aufnahme bestätigt hat, und *Gesendet*, wenn der Befehl
hinausging, die Kamera aber nichts bestätigt. Der Store-Text hält diese Trennung
genauso scharf: Nirgends steht „ausgelöst“ für einen bloß gesendeten Befehl.

**2. Die 30-Zeichen-Felder sind die eigentliche Grenze.** „Kamera-Fernauslöser“
hat allein 19 Zeichen; mit „xGRC - “ und „& Geotag“ wären es 35. Der Name sagt
deshalb „Fernauslöser“, und „Kamera“ wandert in die Keywords.

**3. Kameramenüs bleiben englisch.** Die Menünamen der Hersteller (Bluetooth Rmt
Ctrl, Location Info. Link, Store Location Info., Self-timer: 10 s/remote …)
stehen in der App auf Englisch, weil ihre offiziellen deutschen Bezeichnungen
nicht sicher belegt sind. Der Store-Text nennt keine Kameramenüs.

**4. Die App duzt, also duzt der Store-Text.** „Tippe“, „Stelle … ein“,
„Kopple“ — wie bei xMosaique.

---

## Terminologie — aus der Lokalisierung der App

Quelle: `de.json` (die deutschen Strings dieser Übersetzung), nicht aus dem
Gedächtnis. Nennt der Store-Text ein Wort und die App ein anderes, sucht der
Nutzer etwas, das es auf dem Bildschirm nicht gibt.

| English | de (App) |
|---|---|
| Shutter (Auslösetaste, Abschnitt) | Auslöser |
| Shoot | Auslösen |
| Fired, confirmed | Ausgelöst, bestätigt |
| Sent / Sent, not confirmed | Gesendet / Gesendet, nicht bestätigt |
| confirmed / sent (Zähler) | bestätigt / gesendet |
| Focus / Focused | Fokus / Fokussiert |
| AF hold | AF halten |
| half-press | halbes Drücken (des Auslösers) |
| Bulb | Bulb (Kamera-Einstellung: BULB) |
| Release delay | Auslöseverzögerung |
| Intervalometer | Intervallometer |
| Timelapse | Zeitraffer |
| Frames | Aufnahmen |
| Shutter open (Intervallometer) | Belichtungszeit |
| Geotag / Geotagging | Geotag / Geotagging |
| GPS tracks / Track | GPS-Tracks / Track |
| fix (GPS) | Position |
| Session / End session | Sitzung / Sitzung beenden |
| Pair / Pair again / Pairing mode | koppeln / Erneut koppeln / Kopplungsmodus |
| Forget | Vergessen |
| Connected / Busy | Verbunden / Belegt |
| Remote + Geotag / Remote only / Geotag only | Fernauslöser + Geotag / Nur Fernauslöser / Nur Geotag |
| Auto reconnect / Auto disconnect | Auto-Verbinden / Auto-Trennen |
| Tap to shoot | Tippen zum Auslösen |
| Double Tap (Handgeste der Apple Watch) | Doppeltippen |
| Settings / About | Einstellungen / Info |
| Live Activity | Live-Aktivität |
| Lock Screen / Dynamic Island | Sperrbildschirm / Dynamic Island |
| Control Center | Kontrollzentrum |
| Light / Dark / System | Hell / Dunkel / System |

Was aus der Tabelle folgt:

- **„Doppeltippen“ ist nur die Handgeste** (Apples Name). Zweimal auf den
  Bildschirm tippen heißt „zweimal tippen“.
- **„Fernauslöser“ ist der Modus, nicht das Gerät.** Die Modi heißen in der App
  „Fernauslöser + Geotag“, „Nur Fernauslöser“, „Nur Geotag“; der Text nennt sie
  genau so.
- **Light heißt „Hell“, nicht „Licht“.** Das xMosaique-Glossar übersetzt *Light*
  als „Licht“ — dort ist es ein Lichteffekt. Hier ist es die Darstellung
  (Hell/Dunkel), wie in iOS.
- **Saved heißt „Gespeichert“**, nicht xMosaiques „Gesichert“: In xGRC ist es der
  Zustand einer gespeicherten, nicht verbundenen Kamera.

---

## Überblick / At a glance

| Feld | de |
|---|---|
| Primäre Kategorie | Photo & Video |
| Sekundäre Kategorie | Utilities |
| Altersfreigabe | 4+ |
| Voraussetzung | iOS 17.0 oder neuer (iPhone, iPad); watchOS 10.0 oder neuer (Apple Watch) |

**Kategorien werden ausgewählt, nicht geschrieben**: dieselben zwei wie im
englischen Eintrag.

---

## App-Name (30 Zeichen)

```
xGRC - Fernauslöser & Geotag
```
[28]

Der Name unter dem Icon bleibt `xGRC`; das ist nur der Name des Eintrags. Apple
indexiert Name und Untertitel: „Fernauslöser“, „Geotag“, „Auslöser“, „GPS“ und
„Handgelenk“ müssen in den Keywords nicht noch einmal stehen.

Alternative, mit „Kamera“ im Namen:

```
xGRC: Kamera-Fernauslöser+GPS
```
[29]

---

## Untertitel (30 Zeichen)

```
Auslöser und GPS am Handgelenk
```
[30]

Nah am englischen *Shutter and GPS on your wrist*. Alternative:

```
Bluetooth-Auslöser, Watch, GPS
```
[30]

---

## Werbetext (170 Zeichen — ohne neuen Build änderbar)

```
Löse deine Kamera per iPhone, iPad oder Apple Watch aus: Bulb mit Timer, Auslöseverzögerung, Zeitraffer, GPS in jedem Foto. Kein Dongle. Kein Konto. Nichts wird erfasst.
```
[169]

Alle Zusagen des Englischen bleiben: drei Geräte, Bulb mit Timer,
Auslöseverzögerung, Zeitraffer, GPS, kein Dongle, kein Konto, keine
Datenerfassung.

---

## Keywords (100 Zeichen, kommagetrennt, ohne Leerzeichen)

```
kamera,intervallometer,zeitraffer,bulb,langzeitbelichtung,spiegellos,exif,standort,fotografie,dslr
```
[98]

**Gegen Name und Untertitel geprüft**: keines wiederholt `xgrc`,
`fernauslöser`, `geotag`, `auslöser`, `gps` oder `handgelenk`. `kamera` steht
hier, weil der Name es nicht enthält. **Keine Markennamen** (Sony, Fujifilm,
Canon, Nikon, Ricoh): häufiger Ablehnungsgrund; die Beschreibung nennt sie nur
als Kompatibilität.

---

## Beschreibung (4.000 Zeichen)

Den ganzen Block einfügen. Die Absätze stehen absichtlich jeweils auf einer
Zeile: App Store Connect übernimmt jeden Zeilenumbruch.

```
xGRC macht dein iPhone, iPad und deine Apple Watch zur Bluetooth-Fernbedienung deiner Kamera – und zu ihrem GPS. Die App spricht direkt mit dem eingebauten Bluetooth von Sony-, Fujifilm-, Canon-, Nikon- und Ricoh-Kameras: kein Dongle, kein WLAN, kein Warten auf die App des Herstellers.

EINMAL TIPPEN FOKUSSIERT, ZWEIMAL LÖST AUS
Der Auslöser funktioniert überall gleich. Tippe einmal zum Fokussieren, zweimal zum Auslösen. Mit „AF halten“ bleibt der Fokus gespeichert, während du auf den Moment wartest.

„AUSGELÖST“ NUR, WENN WIRKLICH AUSGELÖST
Wo die Kamera eine Aufnahme bestätigt, zeigt xGRC „Ausgelöst“ und zählt sie. Wo das Bluetooth der Kamera keine Bestätigung kennt, steht stattdessen „Gesendet“. Die Zähler für bestätigt und gesendet tun nie nur so.

LANGZEITBELICHTUNG OHNE KABEL
• Bulb mit Timer: Zeit bis 99 min 59 s einstellen, einmal tippen, und der Verschluss schließt von selbst, wenn der Countdown endet
• Auslöseverzögerung von 1 bis 60 Sekunden, damit deine Hand beim Auslösen nicht an der Kamera ist
• Intervallometer für Zeitraffer: Intervall, Zahl der Aufnahmen oder bis zum Stopp, eine Startverzögerung und eine optionale Belichtungszeit

GPS IN JEDEM FOTO
xGRC sendet Standort und Uhrzeit deines Geräts an die Kamera, die sie in jedes Foto schreibt, das sie aufnimmt. Auf dem iPhone läuft das bei gesperrtem Gerät weiter und erscheint in der Dynamic Island und auf dem Sperrbildschirm. Die Apple Watch geotaggt selbstständig, das iPhone kann zu Hause bleiben. Jede Sitzung speichert ihren GPS-Track auf deinem Gerät, jede Position mit ihrer Uhrzeit: auf iPhone und iPad als Punkte auf einer Karte, und von jedem Gerät als CSV-Datei exportierbar.

EINE ECHTE APP FÜR DIE APPLE WATCH
Suchen, koppeln, auslösen und geotaggen direkt an der Uhr, ohne iPhone. Auf Apple Watch Series 9, Ultra 2 und neuer löst ein Doppeltippen mit Zeigefinger und Daumen aus, sodass die Hand an der Kamera bleiben kann, wo sie ist. Schalte „Tippen zum Auslösen“ ein, und ein Tippen auf den Bildschirm fokussiert und löst aus. Eine Kachel im Smart Stack zeigt die Sitzung auf einen Blick.

GEBAUT FÜR UNTERWEGS
• Wähle „Fernauslöser + Geotag“, „Nur Fernauslöser“ oder „Nur Geotag“
• Auto-Verbinden nimmt die Sitzung wieder auf, wenn die Kamera aufwacht oder wieder in Reichweite ist
• Auto-Trennen gibt die Kamera nach einer ruhigen Phase frei, nach 15 Minuten, wenn du es nicht änderst
• Kurzbefehle und Steuerelemente: Auslösen, Fokus, Geotagging starten und stoppen
• Helle, dunkle oder System-Darstellung auf iPhone und iPad
• Große, handschuhtaugliche Bedienelemente und deutliche Haptik
• Dreizehn Sprachen, in den Einstellungen wählbar

FUNKTIONIERT MIT
• Sony Alpha, ZV, RX und FX mit Bluetooth-Fernbedienung
• Fujifilm X und GFX
• Canon EOS und PowerShot, mit Kopplung als Fernbedienung oder Smartphone
• Nikon, im Fernbedienungsmodus (ML-L7)
• Ricoh GR III, GR IIIx und GR IV
Was eine Kamera über Bluetooth kann, ist unterschiedlich: Fokus, Bulb und Geotagging gibt es nicht bei jeder Marke und in jedem Modus. Die vollständige Liste steht auf der GitHub-Seite des Projekts, verlinkt unter Info.

PRIVAT VON GRUND AUF
Kein Konto, keine Analyse, keine Werbung, keine Server. Dein Standort geht nur an deine Kamera, per Bluetooth, und in Tracks, die auf deinem Gerät bleiben, bis du sie exportierst oder löschst. xGRC ist Open Source unter der Lizenz GPLv3.

xGRC steht in keiner Verbindung zu Sony, Fujifilm, Canon, Nikon oder Ricoh. Markennamen sind Marken ihrer jeweiligen Inhaber.
```
[3.499]

**Absichtlich weggelassen**, wie im Englischen: das Bluetooth-Protokoll in der
App, „Kamera wach halten“ und die Seitenleiste auf dem iPad.

**Jede Markenzeile ist enger als „unterstützt“**, wie im Englischen. Nur aus
Geräteergebnissen erweitern, nicht beim Übersetzen.

---

## Neuerungen (4.000 Zeichen) — Version 1.0

Bei der ersten Version zeigt der Store die Neuerungen nicht an, App Store Connect
verlangt sie trotzdem.

```
Die erste Version von xGRC: ein Bluetooth-Fernauslöser und GPS-Geotagger für Kameras, auf iPhone, iPad und Apple Watch.
```
[119]

---

## Screenshot-Texte

Sieben, je höchstens zwei kurze Zeilen; Reihenfolge und Bild wie im Englischen.
Die Bilder müssen mit deutschem System neu aufgenommen werden. Die
Apple-Watch-Screenshots haben keinen Text.

1 — Sitzungsbildschirm, Sony verbunden, Geotagging läuft

```
Eine Fernbedienung für deine Kamera.
Kein Dongle, keine Hersteller-App.
```
[71]

2 — „Ausgelöst · bestätigt“, 36 bestätigte Aufnahmen

```
„Ausgelöst“ nur, wenn
die Kamera es bestätigt.
```
[46]

3 — eine Bulb-Belichtung von 2 min 30 s im Countdown

```
Bulb-Zeit einstellen. Einmal
tippen, sie schließt von selbst.
```
[61]

4 — das Intervallometer läuft

```
Zeitraffer
ohne Kabel im Gepäck.
```
[32]

5 — der Geotagging-Bildschirm mit Karte

```
Das GPS deines iPhone,
in jedem Foto.
```
[37]

6 — die Kameraliste (nicht auf dem iPad)

```
Für spiegellose
und Kompaktkameras.
```
[35]

7 — eine Auslöseverzögerung von 10 s im Countdown

```
Auslöseverzögerung –
Hände weg von der Kamera.
```
[46]

---

## Notizen für App Review, Datenschutzangaben, TestFlight

**Bleiben auf Englisch** — den Text aus [appstore_intro.md](appstore_intro.md) unverändert verwenden.

---

## Noch zu klären

1. **Muttersprachliche Prüfung ist Pflicht.** Der Text ist maschinell entworfen;
   danach jedes Feld neu messen (der Untertitel hat 0 Zeichen Luft, der
   Werbetext 1).
2. **Ob die Lokalisierung „German“ in App Store Connect angelegt ist.**
3. **Deutsche Screenshots** gibt es noch nicht.
4. **Fotografie-Begriffe gegen die deutschen Handbücher prüfen**: „Bulb“
   (Canon/Nikon sagen auch „Langzeitbelichtung (B)“), „Auslöseverzögerung“ und
   „Intervallometer“ (Canon: „Intervall-Timer“, Nikon: „Intervallaufnahme“).
   Ein Wechsel muss in `de.json` und hier gleichzeitig geschehen.
