# postmarketOS auf SM-T510 (gta3xlwifi) – Analyse aller Fix-Versuche

Stand: 2026-11-22, 21:30 Uhr. Fehler besteht weiterhin nach 4 Versuchen.

## Fehlerbild (konstant über alle Versuche)

```
Kernel panic - not syncing: Unable to mount root fs on unkown-block(0,0)
CPU: 7 UID: 0 PID: 1 Comm: swapper/0 Not tainted 6.15.0-rc1-exynos7904-wifi-dev1 #86-postmarketOS PREEMPT
```
Davor (bestätigt per Foto): `VFS: Cannot open root device "" or unknown-block(0,0): error -6` +
`/dev/root: Can't open blockdev`. Kernel bootet weit (viele Treiber, mmc, Partitionstabelle), bricht erst
beim Root-Mount ab. **In keinem Foto war je eine Zeile mit "RAMDISK", "initramfs" oder "unpack" sichtbar**
— aber die obersten Boot-Zeilen (vor den 8 Tux-Pinguinen) wurden nie vollständig fotografiert, das ist eine
Lücke in der Beweislage, keine bestätigte Abwesenheit.

## Architektur-Verständnis (durch Quellcode bestätigt, nicht geraten)

- Bootkette: Samsung-Bootloader → lädt `boot.img` "kernel"-Sektion = **uniLoader** (Custom-Loader von
  Mollomm1) → uniLoader kopiert eingebetteten Linux-Kernel nach `CONFIG_PAYLOAD_ENTRY` (physisch
  `0x90000000`) und eingebettete Ramdisk nach `CONFIG_RAMDISK_ENTRY` → springt in den echten Kernel.
- **Bestätigt per `start.S`-Quellcode**: uniLoader liest `kernel`/`ramdisk`/`dt`-Pointer **ausschließlich
  aus eigenen, einkompilierten Blobs** (`adrp`/`add` auf Linker-Symbole) — NICHT aus Registern, die der
  Bootloader beim Sprung in uniLoader übergibt. D.h. die "ramdisk"-Sektion der Android-boot.img wird von
  uniLoader komplett ignoriert, unabhängig davon, wohin der Bootloader sie lädt.
- Das Kernel-Paket (`linux-samsung-gta3xlwifi` APKBUILD) baute uniLoader ursprünglich mit **leerer**
  eingebetteter Ramdisk (`touch blob/ramdisk`) — das ist mit Sicherheit falsch/unvollständig für einen
  lauffähigen Boot, da dadurch NIE ein echtes Initramfs im RAM landet.

## Versuch 1 (gescheitert)
`deviceinfo_flash_offset_ramdisk` von `0x01000000` auf `0x79000000` geändert (Annahme: Bootloader lädt
Ramdisk-Sektion direkt an Header-Adresse `base+offset`).
**Fehler in der Annahme**: Durch obigen Quellcode-Fund (`start.S`) war diese Änderung von Anfang an
wirkungslos, weil uniLoader diese externe Sektion nie anschaut. Hätte ich zuerst den uniLoader-Quellcode
gelesen, wäre dieser Versuch übersprungen worden.

## Versuch 2 (gescheitert)
Offset auf `0x09000000` korrigiert (Theorie: Bootloader addiert versteckt `+0x70000000`, hergeleitet aus
`tags_addr`-Konvention). Gleicher Grundfehler wie Versuch 1 — die Adresse der externen Sektion ist für
uniLoader irrelevant, daher logischerweise kein Effekt. **Diese Erkenntnis (Quellcode lesen vor Adressen
raten) kam erst danach.**

## Versuch 3 (gescheitert)
uniLoader aus `github.com/Mollomm1/uniLoader` (generischer Branch) selbst neu gebaut, diesmal mit echtem
Kernel-Image + echtem Initramfs eingebettet (`blob/ramdisk` nicht mehr leer). Theoretisch korrekt nach
Quellcode-Analyse. Trotzdem derselbe Fehler.

**Mögliche Fehlerquellen, die hier NICHT geprüft wurden:**
- Ob der Samsung-Bootloader die "kernel"-Sektion der boot.img über eine bestimmte Größe hinaus
  überhaupt vollständig lädt/kopiert (keine Begrenzung bekannt, aber auch nie verifiziert). Die alte,
  erfolgreich bis zum Root-Mount bootende Version war **~21,7 MB** groß (nur Kernel, keine Ramdisk). Die
  neue, eingebettete Version ist **~28,3–28,4 MB** groß. Es ist ungeprüft, ob der Bootloader ab einer
  bestimmten Größe (zwischen 21,7 MB und 28,4 MB) abschneidet.
- Ob `__optimized_memcpy` (die Kopierroutine für die Ramdisk) bei ~6,6 MB korrekt funktioniert (Quellcode
  wurde gelesen, sieht nach Standard-Glibc-Stil-Implementierung aus, aber nicht am Gerät verifiziert).
- Es wurde **kein neues Foto** nach diesem Versuch gemacht/ausgewertet — könnte neue Information enthalten
  (z.B. jetzt ein "Initramfs unpacking failed"-Fehler statt gar keiner Erwähnung), wurde aber übersprungen.

## Versuch 4 (gescheitert, aktuellster Stand)
Festgestellt: `Mollomm1/uniLoader` (generischer Branch) ist **veraltet** gegenüber einem dedizierten Fork
`Mollomm1/uniLoader-t510`, der:
- die Ramdisk-Zieladresse per **libfdt direkt in den Device-Tree patcht** (`linux,initrd-start/end` werden
  zur Laufzeit gesetzt, nicht statisch im DTS verlassen),
- eine andere `CONFIG_RAMDISK_ENTRY` nutzt (`0x84000000` statt `0x89000000`),
- sich selbst relozieren kann (`CONFIG_POSITION_INDEPENDENT=y`).

uniLoader mit `gta3xl_defconfig` aus diesem Fork neu gebaut, geflasht. **Gleicher Fehler.**

**Offene Fragen / nicht verifiziert:**
- Ob der Bootloader-Lade-Größenlimit-Verdacht (siehe Versuch 3) auch hier zuschlägt (Image ist ähnlich groß,
  ~28,4 MB).
- Ob `gta3xl_defconfig` wirklich vollständig zu unserem Gerät passt (z.B. `CONFIG_TEXT_BASE=0x87000000` —
  woher stammt dieser Wert, ist er für *unser* Exynos7904-Board verifiziert oder nur für eine angenommene
  Kompatibilität mit Exynos7885 übernommen?).
- Kein frisches Foto/Log nach diesem Versuch ausgewertet.

## Nicht in Frage gestellte Grundannahmen (Risiko für systematischen Fehler)

1. **Ist `uniLoader` überhaupt der richtige Mechanismus für dieses Gerät/diesen Build?** Nie durch eine
   funktionierende Referenz (fremdes, nachweislich bootendes Image für exakt dieses Board) bestätigt.
2. **Woher stammt der Kernel/DTB, den wir einbetten, wirklich?** Aus einem bereits einmal gebauten
   „Baseline“-Archiv (`gta3xl-wifi-baseline-...tar.gz`) — nie erneut gegen den *aktuellen* Stand von
   `/home/harry/pmaports` geprüft, ob zwischenzeitlich etwas geändert wurde, das einen Mismatch erzeugt.
3. **DTS-Datei** (`exynos7904-t510.dts`) stammt unverändert aus Mollomm1s ursprünglichem Commit — das wurde
   verifiziert (`git diff` gegen Ursprungscommit = leer). Vertrauenswürdig.
4. Es wurde nie geprüft, ob das Gerät (SM-T510, `gta3xlwifi`) even am Ende exakt das ist, wofür der ganze
   pmaports-Fork gedacht ist, oder ob es Hardware-Revisionsunterschiede gibt.

## Nächster sinnvoller Schritt (noch nicht ausgeführt)

Statt weiter Code zu ändern: **ein neues, vollständiges Foto vom aktuellen Panic-Bildschirm auswerten**
(inkl. der Zeilen VOR den Tux-Pinguinen) um zu sehen, ob sich am Log überhaupt etwas verändert hat
zwischen Versuch 2 (kein eingebettetes Initramfs wirksam) und Versuch 3/4 (eingebettetes Initramfs). Wenn
sich NICHTS am Log ändert (identisch bis auf Timestamps), ist das ein starkes Indiz für das
Größenlimit-Problem beim Laden der Kernel-Sektion durch den Bootloader.

## Update (21:50 Uhr) – eigenständige Weiterarbeit ohne Foto

**Wichtigster Fund**: Mollomm1s pmaports-Fork (`github.com/Mollomm1/pmaports`, Branch `main`, live abgerufen) ist
**byte-identisch** mit dem, was wir lokal importiert haben. Es gibt dort **keine neuere/korrigierte Version**
unseres Kernel-APKBUILDs. Das bedeutet: Das APKBUILD zeigt nach wie vor auf den alten, generischen
`Mollomm1/uniLoader`-Branch mit leerer eingebetteter Ramdisk (`touch blob/ramdisk`) — **so wie Mollomm1 es
selbst aktuell veröffentlicht hat.**

Gleichzeitig existiert sein **separates, klar aktiveres Repo `Mollomm1/uniLoader-t510`** (mit `ramdisk-handler.c`,
DTB-Patching per libfdt, Board-Name `gta3xl` statt `t510`) — das ist offensichtlich **work-in-progress**, um
genau unser Problem zu lösen, aber **noch nicht ins Kernel-APKBUILD zurückintegriert**.

**Fazit**: Das ist kein einfacher Konfigurationsfehler unsererseits, sondern eine **noch nicht fertiggestellte
Stelle in Mollomm1s eigenem, work-in-progress Gerätesupport**. Mein Versuch 4 (uniLoader-t510 + gta3xl_defconfig,
mit DTB-Patching) ist die aktuell bestmögliche, vorwärtsgerichtete Umsetzung dessen, was er selbst gerade baut —
aber auch das hat (noch) nicht gebootet.

**Geprüft und verworfen**:
- `heimdall-isorec` Flash-Methode (separate Partition fürs Initramfs) — wird von KEINEM aktuell lokal
  vorhandenen Gerät genutzt (0 von ~270 deviceinfo-Dateien), kein Referenzbeispiel verfügbar, daher hohes
  Risiko für einen Blindversuch ohne Erfolgsgarantie.
- `pmOS_boot`/`pmOS_root`-Subpartitionen — das ist pmbootstraps generisches Partitionsschema für Geräte mit
  offenem Bootloader, hat nichts mit unserem Samsung/uniLoader-Fall zu tun (falsche Spur aus einer Websuche).

**Ehrlicher Stand**: Ohne frisches Foto vom aktuellen Bildschirm (Versuch 4) kann ich nicht unterscheiden
zwischen: (a) Versuch 4 hat tatsächlich keinen Effekt gehabt (gleicher Fehler wie immer), oder (b) Versuch 4
hat etwas verändert, das im sichtbaren Bildschirmausschnitt nicht zu sehen war. Rein durch Code-Lesen und
Online-Recherche ist an diesem Punkt kein weiterer Fortschritt ohne neue Information vom Gerät möglich.

## Update (22:35 Uhr) – wichtiger Fund: bewiesener Alternativ-Ansatz existiert

Samsung Galaxy S9 (`samsung-starlte`) ist **offiziell in postmarketOS gemerged** (MR !4123, Mai 2023) und
bootet nachweislich (Display, Touch, WLAN funktionieren laut Commit-Historie). Der entscheidende Unterschied:
**Dieses Gerät nutzt KEIN uniLoader!** Es nutzt stattdessen einen **Downstream-Kernel** (alter,
Android-eigener Kernel-Fork, Version 4.9, Quelle: `Exynos9810-LTS/android_kernel_samsung_universal9810`)
mit `downstreamkernel_prepare`/`downstreamkernel_package` (Standard-postmarketOS-Hilfsfunktionen für
Vendor-Kernel) + klassischem `heimdall-bootimg` mit QCDT (`dtbTool-exynos`, dt.img). Genau dieselben
Flash-Offsets wie unser ALTES (vor jeder Änderung) deviceinfo: `base=0x10000000, kernel=0x00008000,
ramdisk=0x01000000, second=0xf0000000, tags=0x00000100`.

**Grund, warum das funktioniert, unseres aber nicht**: Ein alter Downstream-Kernel (4.9/4.4) versteht noch
das klassische Samsung-Bootprotokoll (ATAGS-artige Ramdisk-Übergabe) direkt, ohne Zwischenbootloader. Unser
Projekt (Mollomm1s Fork) versucht dagegen einen **modernen, nah-mainline 6.15-Kernel** zu booten, der NUR
noch Device-Tree-basierte Initrd-Übergabe kennt – deshalb braucht es den fragilen `uniLoader`-Umweg, der
(Stand jetzt) nirgendwo öffentlich nachweislich bis zum Rootfs funktioniert.

**Konsequenz**: Es gibt einen bewiesenen, alternativen, deutlich einfacheren Weg (Downstream-Kernel +
Standard-boot.img, kein uniLoader) für Exynos-Samsung-Geräte generell. Für unser Gerät (gta3xlwifi) würde
das aber einen kompletten Strategiewechsel bedeuten: statt Mollomm1s nah-mainline-Kernel einen alten
Downstream-Kernel (z.B. `Temporalwar/android_kernel_gta3xlwifi`, Android 4.4.302 für SM-T510, bereits
gefunden) zu verwenden und das gesamte Kernel-Paket neu nach diesem Muster zu bauen. Deutlich mehr Aufwand
als der aktuelle PSTORE_BLK-Diagnoseweg, aber nachweislich funktionierender Pfad für diese Geräteklasse.
