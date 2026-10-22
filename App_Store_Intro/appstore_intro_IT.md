# xGRC — Testi App Store in italiano / Italian App Store Copy

Testi pronti da incollare in App Store Connect. Ogni campo riporta il suo limite
di caratteri; tra parentesi quadre c'è il conteggio reale di questo testo,
misurato con `len()` in Python sul blocco esatto.

L'originale inglese è [appstore_intro.md](appstore_intro.md) e questo file gli
corrisponde sezione per sezione. Localizzazione di App Store Connect:
**Italian** — locale dell'app `it`. **Chi cambia un'affermazione la cambia in
tutti i file di lingua** (`appstore_intro_<LANG>.md`): una scheda che in una
lingua promette più che in un'altra è un errore.

**Scritto per la 1.0**, la prima versione, il 2026-10-21 sul
codice 1.0.0, dal testo inglese dello
stesso stato. I punti aperti prima dell'invio (video dimostrativo per App Review,
informativa sulla privacy, riga TESTED ON) sono nell'originale inglese e valgono
anche qui.

**Questo testo è una bozza scritta a macchina.** È stato redatto dall'inglese e
dalle stringhe italiane dell'app (`it.json`), ma **nessun madrelingua l'ha
ancora riletto**. Non incollarlo in App Store Connect prima di quella revisione
(tono, refusi, termini fotografici), e dopo la revisione rimisurare ogni campo.
Vedi «Da confermare» in fondo.

---

## Leggi prima questo — quattro cose che fanno uscire male questo testo

**1. «Scattato» significa solo «scatto confermato».** L'app dice *Scattato*
quando la fotocamera ha confermato lo scatto, e *Inviato* quando il comando è
partito ma la fotocamera non conferma nulla. Il testo dello Store mantiene la
stessa distinzione: «scattato» non indica mai un comando soltanto inviato.

**2. Bulb si dice «posa B».** È il termine dei manuali italiani di Canon e
Nikon; l'app lo usa ovunque («Posa B aperta», «Avvia posa B»). Solo
l'impostazione della ghiera resta `BULB`, come appare sulla fotocamera.

**3. I menu delle fotocamere restano in inglese.** I nomi dei menu dei produttori
(Bluetooth Rmt Ctrl, Location Info. Link, Store Location Info., Self-timer:
10 s/remote…) restano in inglese nell'app, perché le diciture ufficiali italiane
non sono verificate. Il testo dello Store non nomina menu della fotocamera.

**4. Si dà del tu**, come l'app («Tocca», «Imposta», «Abbina») e come
xMosaique.

---

## Tabella terminologica — presa dalla localizzazione dell'app

Fonte: `it.json` (le stringhe italiane di questa traduzione), non la memoria. Se
il testo dello Store usa una parola e l'app un'altra, l'utente cerca qualcosa
che sullo schermo non c'è.

| English | it (app) |
|---|---|
| Shutter (pulsante, sezione) | Scatto |
| shutter (meccanismo) | otturatore |
| Shoot | Scatta |
| Fired, confirmed | Scattato, confermato |
| Sent / Sent, not confirmed | Inviato / Inviato, non confermato |
| confirmed / sent (contatori) | confermati / inviati |
| Focus / Focused | Messa a fuoco / A fuoco |
| AF hold | Mantieni AF |
| half-press | pressione a metà |
| Bulb | Posa B (impostazione della fotocamera: BULB) |
| Release delay | Ritardo di scatto |
| Intervalometer | Intervallometro |
| Timelapse | Timelapse |
| Frames | Fotogrammi |
| Shutter open (intervallometro) | Tempo di esposizione |
| Geotag / Geotagging | Geotag / Geotagging |
| GPS tracks / Track | Tracce GPS / Traccia |
| fix (GPS) | posizione |
| Session / End session | Sessione / Termina sessione |
| Pair / Pair again / Pairing mode | abbinare / Abbina di nuovo / Modalità di abbinamento |
| Forget | Dimentica |
| Connected / Busy | Connessa / Occupata |
| Remote + Geotag / Remote only / Geotag only | Telecomando + Geotag / Solo telecomando / Solo geotag |
| Auto reconnect / Auto disconnect | Riconnessione automatica / Disconnessione automatica |
| Tap to shoot | Tocca per scattare |
| Double Tap (gesto della mano su Apple Watch) | Doppio tocco |
| Settings / About | Impostazioni / Informazioni |
| Live Activity | Attività in tempo reale |
| Lock Screen / Dynamic Island | schermata di blocco / Dynamic Island |
| Control Center | Centro di Controllo |
| Light / Dark / System | Chiaro / Scuro / Sistema |

Cosa ne segue:

- **«Doppio tocco» è solo il gesto della mano** (il nome di Apple). Toccare due
  volte lo schermo è «tocca due volte».
- **La fotocamera è femminile**: «Connessa», «Occupata», «Pronta», «Abbinata».
- **Light è «Chiaro», non «Luce».** Il glossario di xMosaique traduce *Light* con
  «Luce» perché lì è un effetto di luce; qui è l'aspetto (Chiaro/Scuro), come in
  iOS.
- **«Timelapse» resta invariato al plurale**, come i prestiti di xMosaique
  («i timelapse»).

---

## In breve / At a glance

| Campo | it |
|---|---|
| Categoria principale | Photo & Video |
| Categoria secondaria | Utilities |
| Classificazione per età | 4+ |
| Requisiti | iOS 17.0 o successivo (iPhone, iPad); watchOS 10.0 o successivo (Apple Watch) |

**Le categorie si scelgono, non si scrivono**: le stesse due della scheda inglese.

---

## Nome dell'app (30 caratteri)

```
xGRC - Telecomando & Geotag
```
[27]

Il nome sotto l'icona resta `xGRC`; questo è solo il nome della scheda. Apple
indicizza nome e sottotitolo: «telecomando», «geotag», «scatto», «GPS» e
«polso» non vanno ripetuti nelle parole chiave.

Alternativa:

```
xGRC: Telecomando foto e GPS
```
[28]

---

## Sottotitolo (30 caratteri)

```
Scatto e GPS dal tuo polso
```
[26]

Vicino all'inglese *Shutter and GPS on your wrist*. Alternativa:

```
Scatto Bluetooth, Watch e GPS
```
[29]

---

## Testo promozionale (170 caratteri — modificabile senza nuova build)

```
Comanda la fotocamera da iPhone, iPad o Apple Watch: posa B a tempo, ritardo di scatto, timelapse e GPS in ogni foto. Niente dongle. Niente account. Nessun dato raccolto.
```
[170]

Restano tutte le promesse dell'inglese: tre dispositivi, posa B a tempo,
ritardo di scatto, timelapse, GPS, niente dongle, niente account, nessun dato
raccolto.

---

## Parole chiave (100 caratteri, separate da virgole, senza spazi)

```
fotocamera,intervallometro,timelapse,posa,esposizione,mirrorless,exif,geolocalizzazione,reflex,foto
```
[99]

**Controllate contro nome e sottotitolo**: nessuna ripete `xgrc`,
`telecomando`, `geotag`, `scatto`, `gps` o `polso`. **Nessun marchio** (Sony,
Fujifilm, Canon, Nikon, Ricoh): motivo frequente di rifiuto; la descrizione li
nomina solo come compatibilità.

---

## Descrizione (4.000 caratteri)

Incollare l'intero blocco. I paragrafi stanno di proposito su una sola riga: App
Store Connect conserva ogni a capo.

```
xGRC trasforma iPhone, iPad e Apple Watch in un telecomando Bluetooth per la tua fotocamera, e nel suo GPS. Parla direttamente con il Bluetooth integrato nelle fotocamere Sony, Fujifilm, Canon, Nikon e Ricoh: niente dongle, niente Wi-Fi, nessuna app del produttore da aspettare.

UN TOCCO METTE A FUOCO, DUE TOCCHI SCATTANO
Il pulsante di scatto funziona allo stesso modo ovunque. Tocca una volta per mettere a fuoco, due volte per scattare. Con Mantieni AF la messa a fuoco resta bloccata mentre aspetti il momento.

DICE «SCATTATO» SOLO QUANDO HA SCATTATO
Quando la fotocamera conferma uno scatto, xGRC dice «Scattato» e lo conta. Quando il Bluetooth della fotocamera non prevede conferma, dice invece «Inviato». I contatori di confermati e inviati non fingono mai.

POSE LUNGHE SENZA CAVO
• Posa B a tempo: imposta un tempo fino a 99 min 59 s, tocca una volta e l'otturatore si chiude da solo alla fine del conto alla rovescia
• Ritardo di scatto da 1 a 60 secondi, così la tua mano è lontana dalla fotocamera quando scatta
• Intervallometro per i timelapse: intervallo, numero di fotogrammi o fino all'arresto, un ritardo di avvio e un tempo di esposizione opzionale

GPS IN OGNI FOTO
xGRC invia la posizione e l'ora del tuo dispositivo alla fotocamera, che le scrive in ogni foto che scatta. Su iPhone continua con il telefono bloccato e compare nella Dynamic Island e nella schermata di blocco. Su Apple Watch fa il geotagging da solo, con il telefono lasciato a casa. Ogni sessione conserva la sua traccia GPS sul dispositivo, ogni posizione con la sua ora: vedila come punti su una mappa su iPhone e iPad, ed esportala come file CSV da qualsiasi dispositivo.

UNA VERA APP PER APPLE WATCH
Cerca, abbina, scatta e fai geotagging dall'orologio, senza iPhone. Su Apple Watch Series 9, Ultra 2 e successivi, un Doppio tocco di indice e pollice fa scattare l'otturatore, così la mano che regge la fotocamera può restare dov'è. Attiva Tocca per scattare e un tocco sullo schermo mette a fuoco e scatta. Un riquadro nello Smart Stack mostra la sessione a colpo d'occhio.

PENSATA PER IL LAVORO SUL CAMPO
• Scegli Telecomando + Geotag, Solo telecomando o Solo geotag
• La riconnessione automatica riprende la sessione quando la fotocamera si riattiva o torna nel raggio d'azione
• La disconnessione automatica libera la fotocamera dopo un periodo di inattività, 15 minuti se non lo cambi
• Comandi Rapidi e Controlli: Scatta, Messa a fuoco, Avvia e Interrompi geotagging
• Aspetto chiaro, scuro o di sistema su iPhone e iPad
• Comandi grandi, comodi anche con i guanti, e feedback aptico chiaro
• Tredici lingue, da scegliere in Impostazioni

FUNZIONA CON
• Fotocamere Sony Alpha, ZV, RX e FX con telecomando Bluetooth
• Fujifilm X e GFX
• Canon EOS e PowerShot, con abbinamento come telecomando o smartphone
• Nikon, in modalità telecomando (ML-L7)
• Ricoh GR III, GR IIIx e GR IV
Ciò che ogni fotocamera può fare via Bluetooth cambia: messa a fuoco, posa B e geotagging non sono disponibili su ogni marca o modalità. L'elenco completo è sulla pagina GitHub del progetto, collegata da Informazioni.

PRIVATA PER PROGETTO
Nessun account, nessuna analisi, nessuna pubblicità, nessun server. La tua posizione va solo alla tua fotocamera, via Bluetooth, e nelle tracce che restano sul tuo dispositivo finché non le esporti o le elimini. xGRC è open source con licenza GPLv3.

xGRC non è affiliata a Sony, Fujifilm, Canon, Nikon o Ricoh. I nomi dei marchi appartengono ai rispettivi proprietari.
```
[3.496]

**Omesso di proposito**, come nell'inglese: la trascrizione Bluetooth nell'app,
Tieni attiva la fotocamera e la barra laterale su iPad.

**Ogni riga di marca è più stretta di «supporta»**, come nell'inglese. Allargarla
solo in base ai risultati sui dispositivi, non in traduzione.

---

## Novità (4.000 caratteri) — versione 1.0

Le Novità della prima versione non compaiono sullo Store, ma App Store Connect le
chiede comunque.

```
La prima versione di xGRC: telecomando Bluetooth e geotagger GPS per fotocamere, su iPhone, iPad e Apple Watch.
```
[111]

---

## Testi degli screenshot

Sette, al massimo due righe brevi ciascuno; ordine e immagini come
nell'inglese. Le immagini vanno rifatte con il sistema in italiano. Gli
screenshot di Apple Watch non hanno testo.

1 — schermata della sessione, Sony connessa, geotagging attivo

```
Un telecomando per la tua fotocamera.
Niente dongle, niente app del produttore.
```
[79]

2 — «Scattato · confermato», 36 scatti confermati

```
Dice «scattato» solo quando
la fotocamera lo conferma.
```
[54]

3 — una posa B di 2 min 30 s in conto alla rovescia

```
Imposta la posa B.
Un tocco, si chiude da sola.
```
[47]

4 — l'intervallometro in funzione

```
Timelapse
senza cavi da portare.
```
[32]

5 — la schermata Geotagging con la mappa

```
Il GPS del tuo telefono,
in ogni foto.
```
[38]

6 — l'elenco delle fotocamere (non su iPad)

```
Per mirrorless
e compatte.
```
[26]

7 — un ritardo di scatto di 10 s in conto alla rovescia

```
Un ritardo di scatto,
mani lontane dalla fotocamera.
```
[52]

---

## Note per la revisione, risposte sulla privacy, TestFlight

**Restano in inglese** — usare il testo di [appstore_intro.md](appstore_intro.md) senza modifiche.

---

## Da confermare

1. **La revisione di un madrelingua è obbligatoria.** Il testo è scritto a
   macchina; dopo la revisione rimisurare ogni campo.
2. **Se la localizzazione «Italian» esiste in App Store Connect.**
3. **Screenshot in italiano**: non esistono ancora.
4. **Termini fotografici da verificare sui manuali italiani**: «posa B»,
   «ritardo di scatto» (Canon e Nikon parlano anche di «autoscatto» per il
   comando a distanza) e «intervallometro» (Nikon: «ripresa intervallata»). Un
   cambio va fatto insieme in `it.json` e qui.
