# xGRC — Texto de App Store en español / Spanish App Store Copy

Texto listo para pegar en App Store Connect. Cada campo lleva su límite de
caracteres; entre corchetes va el recuento real de este texto, medido con
`len()` de Python (App Store Connect cuenta caracteres, no bytes).

**Este archivo rellena dos localizaciones de App Store Connect: Español
(España) y Español (México)**, que corresponden a las localizaciones `es` y
`es-419` de la app. Son dos fichas independientes: cada una necesita su propio
nombre, subtítulo, palabras clave, descripción, texto promocional, novedades y
capturas. Donde las dos variantes coinciden, el bloque va una sola vez y lo
dice; donde no, van las dos.

**Es un borrador hecho a máquina**, igual que las traducciones de la propia
app: **un hablante nativo de España y otro de Latinoamérica tienen que leerlo
antes de enviarlo.** El original en inglés está en
[appstore_intro.md](appstore_intro.md) y este archivo se corresponde con él
sección por sección. **Una afirmación que cambia aquí (funciones, límites,
cámaras compatibles y sus salvedades, privacidad) tiene que cambiar en todos
los archivos de idioma**, el inglés incluido; la lista de archivos está al
principio del inglés.

**Redactado para 1.0**, la primera versión, el 2026-10-21, contra
el código 1.0.0. Antes de enviar hay
que releer cada afirmación contra el commit archivado, como dice el inglés.

**Las notas para la revisión, las respuestas de privacidad y el texto de
TestFlight se quedan en inglés**: están en
[appstore_intro.md](appstore_intro.md) y se pegan tal cual.

---

## Tabla de terminología — tomada de `es.json` y `es-419.json`

El texto de la tienda usa las mismas palabras que la interfaz. Si aquí se dice
una cosa y la app otra, el usuario busca en pantalla algo que no está.

| English | es (España) | es-419 (Latinoamérica) |
|---|---|---|
| Shutter | Obturador | Obturador |
| Shoot | Disparar | Disparar |
| Fired · confirmed | Disparado · confirmado | Disparado · confirmado |
| Sent | Enviado | Enviado |
| Bulb | Bulb | Bulb |
| Release delay | Retardo de disparo | Retardo de disparo |
| Intervalometer | Intervalómetro | Intervalómetro |
| Timelapse | Timelapse | Timelapse |
| **Frames** | **Fotogramas** | **Cuadros** |
| Geotag | Geoetiqueta | Geoetiqueta |
| Geotagging | Geoetiquetado | Geoetiquetado |
| GPS tracks / Track | Rutas GPS / Ruta | Rutas GPS / Ruta |
| Session / End session | Sesión / Finalizar sesión | Sesión / Finalizar sesión |
| Pair / Pairing mode | Emparejar / Modo de emparejamiento | Emparejar / Modo de emparejamiento |
| Focus / AF hold | Enfoque / Mantener AF | Enfoque / Mantener AF |
| **Half-press** | **pulsar hasta la mitad** | **presionar hasta la mitad** |
| Remote + Geotag / Remote only / Geotag only | Remoto + Geoetiqueta / Solo remoto / Solo geoetiqueta | Remoto + Geoetiqueta / Solo remoto / Solo geoetiqueta |
| Auto reconnect / Auto disconnect | Reconexión automática / Desconexión automática | Reconexión automática / Desconexión automática |
| Tap to shoot | Tocar para disparar | Tocar para disparar |
| Double Tap (Apple Watch) | Doble toque | Doble toque |
| **Live Activity** | **Actividad en directo** | **Actividad en vivo** |
| Dynamic Island / Lock Screen | Dynamic Island / pantalla bloqueada | Dynamic Island / pantalla bloqueada |
| **Settings** | **Ajustes** | **Configuración** |
| **Add camera** | **Añadir cámara** | **Agregar cámara** |
| **phone** | **móvil** | **celular** |
| **wireless remote** | **mando inalámbrico** | **control remoto inalámbrico** |
| **countdown** | **cuenta atrás** | **cuenta regresiva** |
| **take a photo** | **hacer una foto** | **tomar una foto** |
| **Done** | **Hecho** | **Listo** |

Las filas en negrita son las que cambian entre las dos fichas. Además, España
usa el pretérito perfecto («se ha desconectado») y Latinoamérica el indefinido
(«se desconectó»), como en las cadenas de la app.

Los nombres de menú de las cámaras (Bluetooth Rmt Ctrl, Location Info. Link,
Pairing Registration, Store Location Info., Self-timer: 10 s/remote…) se dejan
en inglés en la app, porque no hay certeza de la etiqueta oficial de cada
fabricante en español. La ficha no los nombra.

---

## Nombre de la app (30 caracteres)

**Las dos fichas usan el mismo nombre.**

```
xGRC - Disparador remoto y GPS
```
[30]

«Disparador remoto» es como se llama este accesorio en las dos variantes, así
que no hace falta partir el nombre. Al límite: si cambia una palabra, hay que
volver a contar. El prefijo `xGRC` se mantiene; el nombre bajo el icono sigue
siendo `xGRC`.

---

## Subtítulo (30 caracteres)

**Las dos fichas, igual:**

```
Obturador y GPS en tu muñeca
```
[28]

---

## Texto promocional (170 caracteres — se puede cambiar sin compilar)

**Las dos fichas, igual** (no usa ninguna palabra que cambie entre ellas):

```
Dispara tu cámara desde iPhone, iPad o Apple Watch: bulb temporizado, retardo de disparo, timelapses y GPS en cada foto. Sin adaptador. Sin cuenta. Nada se recopila.
```
[165]

---

## Palabras clave (100 caracteres, separadas por comas, sin espacios)

**es (España)**
```
intervalómetro,timelapse,bulb,cámara,geoetiqueta,mirrorless,exif,ubicación,fotografía,réflex,mando
```
[98]

**es-419 (Latinoamérica)**
```
intervalómetro,timelapse,bulb,cámara,geoetiqueta,mirrorless,exif,ubicación,fotografía,réflex,control
```
[100]

No repiten palabras del nombre ni del subtítulo (`xGRC`, `disparador`,
`remoto`, `GPS`, `obturador`, `muñeca`), que Apple ya indexa. `cámara` sí va,
porque el nombre en español no la lleva. **Sin marcas**: Sony, Fujifilm,
Canon, Nikon y Ricoh solo aparecen en la descripción, como compatibilidad. La
única diferencia es `mando` / `control`, cómo se busca un mando a distancia a
cada lado del Atlántico.

---

## Descripción (4.000 caracteres)

Pegar el bloque entero. Los párrafos van en una sola línea a propósito: App
Store Connect conserva cada salto de línea.

**es (España)**
```
xGRC convierte tu iPhone, iPad y Apple Watch en un disparador remoto Bluetooth para tu cámara, y en su GPS. Se comunica directamente con el Bluetooth integrado de las cámaras Sony, Fujifilm, Canon, Nikon y Ricoh: sin adaptador, sin Wi-Fi, sin esperar a la app del fabricante.

UN TOQUE ENFOCA, DOS DISPARAN
El obturador funciona igual en todas partes. Toca una vez para enfocar y dos para disparar. Activa Mantener AF si quieres el enfoque bloqueado mientras esperas el momento.

DISPARADO SOLO CUANDO DE VERDAD DISPARA
Cuando la cámara confirma una toma, xGRC dice Disparado y la cuenta. Cuando el Bluetooth de la cámara no da confirmación, dice Enviado. Los contadores de confirmados y enviados nunca fingen.

EXPOSICIONES LARGAS SIN CABLE
• Bulb temporizado: fija un tiempo de hasta 99 min 59 s, toca una vez y el obturador se cierra solo al terminar la cuenta atrás
• Retardo de disparo de 1 a 60 segundos, para que tu mano no toque la cámara cuando dispara
• Intervalómetro para timelapses: intervalo, número de fotogramas o hasta detenerlo, un retardo de inicio y un tiempo de obturador abierto opcional

GPS EN CADA FOTO
xGRC envía la ubicación y la hora de tu dispositivo a la cámara, que las graba en cada foto que hace. En el iPhone sigue funcionando con el móvil bloqueado y se muestra en la Dynamic Island y en la pantalla bloqueada. En el Apple Watch geoetiqueta por sí solo, aunque dejes el móvil en casa. Cada sesión guarda su ruta GPS en tu dispositivo, cada posición con su hora: mírala como puntos en un mapa en el iPhone y el iPad, y expórtala como archivo CSV desde cualquiera de ellos.

UNA APP DE VERDAD PARA APPLE WATCH
Busca, empareja, dispara y geoetiqueta desde el reloj, sin necesidad del iPhone. En el Apple Watch Series 9, Ultra 2 y posteriores, un Doble toque del índice y el pulgar dispara el obturador, así que la mano que sujeta la cámara puede quedarse donde está. Activa Tocar para disparar y un toque en la pantalla enfoca y dispara. Un widget de la Pila inteligente muestra la sesión de un vistazo.

PENSADA PARA SALIR A FOTOGRAFIAR
• Elige Remoto + Geoetiqueta, Solo remoto o Solo geoetiqueta
• Reconexión automática retoma la sesión cuando la cámara se activa o vuelve a estar al alcance
• Desconexión automática libera la cámara tras un rato sin actividad, 15 minutos salvo que lo cambies
• Atajos y controles: Disparar, Enfoque, Iniciar y Detener geoetiquetado
• Apariencia clara, oscura o del sistema en iPhone y iPad
• Controles grandes, cómodos con guantes, y vibraciones claras
• Trece idiomas, a elegir en Ajustes

COMPATIBLE CON
• Cámaras Sony Alpha, ZV, RX y FX con control remoto por Bluetooth
• Fujifilm X y GFX
• Canon EOS y PowerShot, con emparejamiento Remoto o Smartphone
• Nikon, en modo remoto (ML-L7)
• Ricoh GR III, GR IIIx y GR IV
Lo que cada cámara puede hacer por Bluetooth varía: el enfoque, el bulb y el geoetiquetado no están disponibles en todas las marcas ni en todos los modos. La lista completa está en la página de GitHub del proyecto, enlazada desde Acerca de.

PRIVADA POR DISEÑO
Sin cuenta, sin analíticas, sin anuncios, sin servidores. Tu ubicación solo va a tu cámara, por Bluetooth, y a rutas que se quedan en tu dispositivo hasta que las exportes o las elimines. xGRC es de código abierto, con licencia GPLv3.

xGRC no está afiliada a Sony, Fujifilm, Canon, Nikon ni Ricoh. Las marcas pertenecen a sus respectivos titulares.
```
[3.405]

**es-419 (Latinoamérica)**
```
xGRC convierte tu iPhone, iPad y Apple Watch en un disparador remoto Bluetooth para tu cámara, y en su GPS. Se comunica directamente con el Bluetooth integrado de las cámaras Sony, Fujifilm, Canon, Nikon y Ricoh: sin adaptador, sin Wi-Fi, sin esperar a la app del fabricante.

UN TOQUE ENFOCA, DOS DISPARAN
El obturador funciona igual en todas partes. Toca una vez para enfocar y dos para disparar. Activa Mantener AF si quieres el enfoque bloqueado mientras esperas el momento.

DISPARADO SOLO CUANDO DE VERDAD DISPARA
Cuando la cámara confirma una toma, xGRC dice Disparado y la cuenta. Cuando el Bluetooth de la cámara no da confirmación, dice Enviado. Los contadores de confirmados y enviados nunca fingen.

EXPOSICIONES LARGAS SIN CABLE
• Bulb temporizado: fija un tiempo de hasta 99 min 59 s, toca una vez y el obturador se cierra solo al terminar la cuenta regresiva
• Retardo de disparo de 1 a 60 segundos, para que tu mano no toque la cámara cuando dispara
• Intervalómetro para timelapses: intervalo, número de cuadros o hasta detenerlo, un retardo de inicio y un tiempo de obturador abierto opcional

GPS EN CADA FOTO
xGRC envía la ubicación y la hora de tu dispositivo a la cámara, que las graba en cada foto que toma. En el iPhone sigue funcionando con el celular bloqueado y se muestra en la Dynamic Island y en la pantalla bloqueada. En el Apple Watch geoetiqueta por sí solo, aunque dejes el celular en casa. Cada sesión guarda su ruta GPS en tu dispositivo, cada posición con su hora: mírala como puntos en un mapa en el iPhone y el iPad, y expórtala como archivo CSV desde cualquiera de ellos.

UNA APP DE VERDAD PARA APPLE WATCH
Busca, empareja, dispara y geoetiqueta desde el reloj, sin necesidad del iPhone. En el Apple Watch Series 9, Ultra 2 y posteriores, un Doble toque del índice y el pulgar dispara el obturador, así que la mano que sostiene la cámara puede quedarse donde está. Activa Tocar para disparar y un toque en la pantalla enfoca y dispara. Un widget de la Pila inteligente muestra la sesión de un vistazo.

PENSADA PARA SALIR A FOTOGRAFIAR
• Elige Remoto + Geoetiqueta, Solo remoto o Solo geoetiqueta
• Reconexión automática retoma la sesión cuando la cámara se activa o vuelve a estar al alcance
• Desconexión automática libera la cámara después de un rato sin actividad, 15 minutos a menos que lo cambies
• Atajos y controles: Disparar, Enfoque, Iniciar y Detener geoetiquetado
• Apariencia clara, oscura o del sistema en iPhone y iPad
• Controles grandes, cómodos con guantes, y vibraciones claras
• Trece idiomas, a elegir en Configuración

COMPATIBLE CON
• Cámaras Sony Alpha, ZV, RX y FX con control remoto por Bluetooth
• Fujifilm X y GFX
• Canon EOS y PowerShot, con emparejamiento Remoto o Smartphone
• Nikon, en modo remoto (ML-L7)
• Ricoh GR III, GR IIIx y GR IV
Lo que cada cámara puede hacer por Bluetooth varía: el enfoque, el bulb y el geoetiquetado no están disponibles en todas las marcas ni en todos los modos. La lista completa está en la página de GitHub del proyecto, enlazada desde Acerca de.

PRIVADA POR DISEÑO
Sin cuenta, sin analíticas, sin anuncios, sin servidores. Tu ubicación solo va a tu cámara, por Bluetooth, y a rutas que se quedan en tu dispositivo hasta que las exportes o las elimines. xGRC es de código abierto, con licencia GPLv3.

xGRC no está afiliada a Sony, Fujifilm, Canon, Nikon ni Ricoh. Las marcas pertenecen a sus respectivos titulares.
```
[3.426]

**Lo mismo que el inglés deja fuera, aquí también:** la transcripción
Bluetooth de la app, Mantener la cámara activa y la barra lateral del iPad.
**Cada línea de marca es más estrecha que «compatible»**: el apartado
COMPATIBLE CON nombra los modos y dice que las funciones varían. Ampliarlo
solo con resultados de dispositivos reales, y en todos los idiomas a la vez.

---

## Novedades (4.000 caracteres) — versión 1.0

**Las dos fichas, igual.** La primera versión no muestra las Novedades en la
tienda, pero App Store Connect las pide.

```
La primera versión de xGRC: disparador remoto Bluetooth y geoetiquetador GPS para iPhone, iPad y Apple Watch.
```
[109]

---

## Textos de las capturas de pantalla

Siete, en el mismo orden que el inglés; dos líneas cortas cada uno. El
recuento entre corchetes incluye el salto de línea. Para cambiarlos, edita
`lines` en `AppStorePreview/tools/frames.json` y vuelve a renderizar (ver
[AppStorePreview/](../AppStorePreview/README.md)). Las imágenes tienen que
hacerse con el sistema en español. Las capturas del Apple Watch no llevan
texto.

**1 — la pantalla de sesión, Sony conectada y geoetiquetando** (las dos fichas)
```
Disparador remoto para tu cámara.
Sin adaptador ni app oficial.
```
[63]

**2 — Disparado · confirmado, 36 tomas confirmadas** (las dos fichas)
```
Solo dice Disparado
si la cámara lo confirma.
```
[45]

**3 — un bulb de 2 min 30 s en cuenta atrás / regresiva** (las dos fichas)
```
Fija un tiempo de bulb.
Un toque y se cierra solo.
```
[50]

**4 — el intervalómetro en marcha** (las dos fichas)
```
Timelapses sin
cable que llevar.
```
[32]

**5 — la pantalla de geoetiquetado con su mapa**

es (España)
```
El GPS de tu móvil,
en cada foto.
```
[33]

es-419 (Latinoamérica)
```
El GPS de tu celular,
en cada foto.
```
[35]

**6 — la lista de cámaras** (las dos fichas)
```
Para cámaras sin espejo
y compactas.
```
[36]

**7 — un retardo de 10 s en cuenta atrás / regresiva** (las dos fichas)
```
Retardo de disparo,
sin tocar la cámara.
```
[40]

---

## Notas de redacción — propias del español

- **Se tutea**, como en toda la app («Toca», «Activa», «Empareja»).
- **«Disparado» solo para tomas confirmadas**, «Enviado» cuando la cámara no
  confirma, igual que en la app y en el inglés. No usar «disparado» como
  sinónimo de «enviado» en ningún texto.
- **No prometer el disparo en segundo plano.** En el reloj, disparar necesita
  xGRC en pantalla.
- **Sin precios en la descripción**; se fijan en App Store Connect.
- **Las tres primeras líneas son lo que se ve**; el resto queda detrás de «más».
- **Volver a contar cada bloque** tras cualquier cambio:
  `python3 -c "import re,sys; [print(len(b), b[:40]) for b in re.findall(r'\`\`\`\n(.*?)\n\`\`\`', open(sys.argv[1]).read(), re.S)]" App_Store_Intro/appstore_intro_ES.md`
