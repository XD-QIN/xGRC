# xGRC — Texto da App Store em português do Brasil / Brazilian Portuguese App Store Copy

Texto pronto para colar no App Store Connect. Cada campo traz o seu limite de
caracteres; entre colchetes, sob cada bloco, vai a contagem real deste texto,
medida com `len()` em Python sobre o bloco exato.

**Localização do App Store Connect: Portuguese (Brazil)** — locale do app
`pt-BR`. É português do Brasil, não de Portugal: o App Store Connect trata
**Portuguese (Brazil)** e **Portuguese (Portugal)** como fichas separadas, e o
app só traz `pt-BR`. O original em inglês está em
[appstore_intro.md](appstore_intro.md); este arquivo corresponde a ele seção
por seção.

**Este texto é um rascunho feito por máquina**, assim como as strings
`pt-BR` do app (`pt-BR.json`). Um falante nativo precisa revisá-lo antes de
qualquer envio — tom, erros de digitação, termos — e medir de novo os campos
depois da revisão.

**Uma mudança que toque uma afirmação precisa ser feita em todos os arquivos
de idioma** (os dez `appstore_intro_*.md` e o inglês). Nada foi acrescentado
aqui: recursos, limites, câmeras suportadas e as suas ressalvas, privacidade,
tudo segue o inglês.

**As notas para a revisão, as respostas de App Privacy e os textos do
TestFlight ficam em inglês**: ver [appstore_intro.md](appstore_intro.md).

---

## Tabela de terminologia — tirada de `pt-BR.json`

A ficha usa as palavras que o usuário vê na tela. Se o app mudar uma string,
esta tabela e este texto mudam junto.

| English | pt-BR (app) |
|---|---|
| Shutter (botão, seção) / shutter (mecanismo) | Obturador |
| shutter button | botão do obturador |
| Shoot | Disparar |
| Fired, confirmed | Disparado, confirmado |
| Sent, not confirmed | Enviado, não confirmado |
| confirmed / sent (contadores) | confirmados / enviados |
| Focus / Focusing / Focused | Foco / Focando / Focado |
| AF hold | Manter AF |
| half-press | pressão até a metade |
| Bulb | Bulb (ajuste da câmera: `BULB`, como está) |
| Release delay / Delay | Atraso do disparo / Atraso |
| Intervalometer | Intervalômetro |
| Timelapse | Timelapse |
| Frames | Quadros |
| Shutter open (tempo de abertura) | Tempo de exposição |
| Geotag / Geotagging | Geomarcação |
| Remote + Geotag / Remote only / Geotag only | Controle remoto + geomarcação / Só controle remoto / Só geomarcação |
| GPS tracks / Track | Trilhas GPS / Trilha |
| location | localização |
| fix (GPS) | posição |
| push / pushes | envio / envios |
| Session / End session | Sessão / Encerrar sessão |
| Pair / Pairing mode / Pair again | Emparelhar / Modo de emparelhamento / Emparelhar de novo |
| Forget | Esquecer |
| Auto reconnect / Auto disconnect | Reconexão automática / Desconexão automática |
| Tap to shoot (Apple Watch) | Tocar para disparar |
| Double Tap (gesto do Apple Watch) | Toque Duplo |
| Live Activity / Dynamic Island / Lock Screen | Atividade ao Vivo / Dynamic Island / Tela Bloqueada |
| Smart Stack | Pilha Inteligente |
| Settings | Ajustes |
| camera | câmera |

Observações:

- **“Disparado” só para um disparo que a câmera confirmou**; “Enviado” para
  um comando que saiu sem confirmação. É a promessa central do app; a ficha
  nunca troca uma palavra pela outra.
- **“Bulb” fica em inglês**, como nos menus das câmeras vendidas no Brasil
  (“modo Bulb”); o ajuste da câmera aparece como `BULB`.
- **Os nomes de menu das câmeras ficam em inglês no app** (Bluetooth Rmt
  Ctrl, Location Info. Link, Pairing Registration…), por falta de um rótulo
  oficial em português conferido. A ficha não os cita.
- **“Celular”**, não “telefone” nem “telemóvel”: vocabulário brasileiro.

---

## Resumo / At a glance

| Campo | pt-BR |
|---|---|
| Categoria principal | Photo & Video |
| Categoria secundária | Utilities |
| Classificação | 4+ |
| Requer | iOS 17.0 ou posterior (iPhone, iPad); watchOS 10.0 ou posterior (Apple Watch) |
| Idiomas do app | 13 |

As categorias são escolhidas no App Store Connect, que as traduz sozinho.

---

## Nome do app (30 caracteres)

```
xGRC - Controle Remoto e GPS
```
[28]

O nome sob o ícone continua `xGRC`. “Controle”, “remoto” e “GPS” são
indexados pelo nome e não se repetem nas palavras-chave. O inglês diz
*Camera Remote & Geotag*; “geomarcação” não cabe em 30 caracteres junto com o
resto, e as palavras-chave a cobrem.

Alternativa:

```
xGRC - Disparo Remoto e GPS
```
[27]

---

## Subtítulo (30 caracteres)

```
Obturador e GPS no seu pulso
```
[28]

Calcado em *Shutter and GPS on your wrist*. “Obturador” e “pulso” ficam
indexados aqui e fora das palavras-chave.

---

## Texto promocional (170 caracteres — pode ser alterado sem nova compilação)

```
Dispare sua câmera pelo iPhone, iPad ou Apple Watch: bulb com tempo, atraso do disparo, timelapses e GPS em cada foto. Sem dongle. Sem conta. Nada é coletado.
```
[158]

As afirmações do inglês, todas: bulb com tempo, atraso do disparo,
timelapses, GPS em cada foto; sem dongle, sem conta, nada coletado.

---

## Palavras-chave (100 caracteres, separadas por vírgula, sem espaços)

```
intervalômetro,timelapse,bulb,disparador,mirrorless,exif,geomarcação,localização,fotografia,câmera
```
[98]

Nenhuma palavra do nome ou do subtítulo (`xGRC`, `controle`, `remoto`, `GPS`,
`obturador`, `pulso`). **Nenhuma marca** (Sony, Fujifilm, Canon, Nikon, Ricoh,
nem Bluetooth): motivo comum de rejeição. `mirrorless` fica em inglês
porque é assim que o fotógrafo brasileiro o digita.

---

## Descrição (4.000 caracteres)

Colar o bloco inteiro. Os parágrafos estão numa linha só de propósito: o App
Store Connect mantém cada quebra de linha.

```
O xGRC transforma o seu iPhone, iPad e Apple Watch num controle remoto Bluetooth para a sua câmera, e no GPS dela. Ele conversa direto com o Bluetooth embutido nas câmeras Sony, Fujifilm, Canon, Nikon e Ricoh: sem dongle, sem Wi-Fi, sem esperar pelo app do fabricante.

UM TOQUE FOCA, DOIS TOQUES DISPARAM
O obturador funciona igual em todo lugar. Toque uma vez para focar, duas vezes para disparar. Ative Manter AF se quiser o foco travado enquanto espera o momento.

SÓ DIZ DISPARADO QUANDO DISPAROU
Quando a câmera confirma uma foto, o xGRC diz Disparado e a conta. Quando o Bluetooth da câmera não tem confirmação, ele diz Enviado. Os contadores de confirmados e enviados nunca fingem.

LONGAS EXPOSIÇÕES SEM O CABO
• Bulb com tempo: defina até 99 min 59 s, toque uma vez, e o obturador fecha sozinho quando a contagem regressiva termina
• Atraso do disparo de 1 a 60 segundos, para que a sua mão esteja longe da câmera quando ela disparar
• Intervalômetro para timelapses: intervalo, número de quadros ou até parar, atraso de início e um tempo de exposição opcional

GPS EM CADA FOTO
O xGRC envia a localização e a hora do seu dispositivo à câmera, que as grava em cada foto que tira. No iPhone, continua com o celular bloqueado e aparece na Dynamic Island e na Tela Bloqueada. No Apple Watch, faz a geomarcação sozinho, com o celular deixado em casa. Cada sessão guarda a sua trilha GPS no seu dispositivo, cada posição com a sua hora: veja-a como pontos num mapa no iPhone e no iPad, e exporte-a como arquivo CSV de qualquer um deles.

UM APP DE VERDADE PARA APPLE WATCH
Busque, emparelhe, dispare e faça a geomarcação pelo relógio, sem precisar do iPhone. No Apple Watch Series 9, Ultra 2 e posteriores, um Toque Duplo do indicador com o polegar dispara o obturador, e a mão que segura a câmera fica onde está. Ative Tocar para disparar e um toque na tela foca e dispara. Um bloco na Pilha Inteligente mostra a sessão num relance.

FEITO PARA O CAMPO
• Escolha Controle remoto + geomarcação, Só controle remoto ou Só geomarcação
• A reconexão automática retoma a sessão quando a câmera desperta ou volta ao alcance
• A desconexão automática libera a câmera depois de um tempo parada, 15 minutos se você não mudar
• Atalhos e Controles: Disparar, Foco, Iniciar e Parar geomarcação
• Aparência clara, escura ou do sistema no iPhone e no iPad
• Controles grandes, fáceis de usar com luvas, e retorno háptico claro
• Treze idiomas, escolhidos em Ajustes

FUNCIONA COM
• Câmeras Sony Alpha, ZV, RX e FX com controle remoto por Bluetooth
• Fujifilm X e GFX
• Canon EOS e PowerShot, no emparelhamento Remoto ou Smartphone
• Nikon, no modo de controle remoto (ML-L7)
• Ricoh GR III, GR IIIx e GR IV
O que cada câmera pode fazer por Bluetooth varia: foco, bulb e geomarcação não estão disponíveis em todas as marcas ou modos. A lista completa está na página do projeto no GitHub, com link em Sobre.

PRIVADO DESDE A CONCEPÇÃO
Sem conta, sem análises, sem anúncios, sem servidores. A sua localização vai só para a sua câmera, por Bluetooth, e para trilhas que ficam no seu dispositivo até você exportá-las ou excluí-las. O xGRC é de código aberto sob a licença GPLv3.

O xGRC não é afiliado à Sony, Fujifilm, Canon, Nikon ou Ricoh. Os nomes de marca pertencem aos seus donos.
```
[3.278]

Detalhes que não são erros:

- **“Atalhos e Controles”** para *Shortcuts and Controls*: os nomes que a
  Apple usa em português (app Atalhos, controles da Central de Controle).
- **“Bloco na Pilha Inteligente”** para *Smart Stack tile*.
- **“Remoto ou Smartphone”** na linha Canon: os dois tipos de emparelhamento
  da câmera.
- **Deixado de fora de propósito, como no inglês**: a transcrição Bluetooth do app,
  Manter câmera ativa e o layout com barra lateral do iPad.

---

## Novidades (4.000 caracteres) — versão 1.0

As Novidades da primeira versão não aparecem na página da loja, mas o App
Store Connect as pede.

```
A primeira versão do xGRC: um controle remoto Bluetooth e geomarcador GPS para câmeras, no iPhone, iPad e Apple Watch.
```
[118]

---

## Textos das capturas de tela

Duas linhas curtas cada; vão em `lines` de `AppStorePreview/tools/frames.json`
(uma string por linha) antes de renderizar. A contagem entre colchetes inclui
as duas linhas e a quebra entre elas.

1. Tela da sessão, Sony conectada e geomarcando

```
Um controle remoto para a câmera.
Sem dongle, sem app do fabricante.
```
[68]

2. Disparado · confirmado, 36 fotos confirmadas

```
Só diz disparado quando
a câmera confirma.
```
[42]

3. Bulb de 2 min 30 s em contagem regressiva

```
Defina um tempo de bulb.
Um toque, e ele fecha sozinho.
```
[55]

4. Intervalômetro em andamento

```
Timelapses sem
cabo para carregar.
```
[34]

5. Tela de geomarcação com o mapa

```
O GPS do seu celular,
em cada foto.
```
[35]

6. Lista de câmeras (não no iPad)

```
Para câmeras mirrorless
e compactas.
```
[36]

7. Atraso de 10 s em contagem regressiva

```
Um atraso do disparo,
mãos longe da câmera.
```
[43]

As capturas precisam ser refeitas com o app em português: telas em inglês
numa ficha brasileira chamam atenção. As capturas do Apple Watch não têm
texto.

---

## Notas para a revisão, App Privacy, TestFlight

**Ficam em inglês. Não traduzir.** Colar como estão os blocos de
[appstore_intro.md](appstore_intro.md).
