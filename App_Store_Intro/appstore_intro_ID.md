# xGRC — Teks App Store Bahasa Indonesia / Indonesian App Store Copy

Teks siap tempel untuk App Store Connect. Setiap kolom diberi batas karakternya;
angka dalam kurung siku adalah hasil hitung teks ini dengan Python `len()`.

Naskah asli bahasa Inggris ada di [appstore_intro.md](appstore_intro.md), dan
berkas ini mengikutinya bagian demi bagian. Di App Store Connect ini mengisi
lokalisasi **Indonesian** (locale aplikasi `id`). **Satu catatan App Store**
memuat aplikasi iPhone dan iPad serta aplikasi Apple Watch, jadi listing ini
harus menjual ketiganya.

**Berkas ini merupakan draf mesin**, begitu pula string aplikasi dalam bahasa
Indonesia (`id`). Seluruh teks perlu dibaca penutur asli sebelum dikirim — lihat
«Menunggu konfirmasi» di akhir.

**Perubahan pada klaim harus dilakukan di semua berkas bahasa sekaligus** —
naskah bahasa Inggris dan sebelas terjemahan lainnya selalu berjalan bersama.

**Ditulis untuk 1.0**, rilis pertama, pada 2026-10-21 terhadap
kode 1.0.0. Sebelum mengirim,
cocokkan ulang setiap klaim dengan commit yang diarsipkan.

---

## Baca ini dulu — tiga hal

**1. Istilah fotografi mengikuti yang dipakai produsen kamera dan aplikasi.**
«Rana» untuk shutter (seperti «Kecepatan Rana» di xMosaique), «tunda rana» untuk
release delay, «bulb», «intervalometer», «timelapse», «geotag» dan «geotagging»
tetap sebagai kata serapan. Merek, nama produk, dan singkatan tetap dalam bentuk
aslinya: Bluetooth, GPS, CSV, AF, BULB, iPhone, iPad, Apple Watch, Dynamic Island,
Digital Crown, Sony, Fujifilm, Canon, Nikon, Ricoh.

**2. Nama menu kamera tidak diterjemahkan.** Bluetooth Rmt Ctrl, Location Info.
Link, Store Location Info., Pairing Registration, Self-timer: 10 s/remote —
label ini muncul dalam bahasa Inggris di layar kamera, jadi aplikasi juga
mempertahankannya.

**3. Sapaan «Anda»**, dengan kalimat perintah yang lugas («Ketuk», «Nyalakan»),
sama seperti di aplikasi.

---

## Tabel terminologi — dari lokalisasi aplikasi sendiri

Teks toko wajib memakai kata-kata ini. Sumber: string `id` aplikasi
(`Apps/Shared/Localization/Localizable.xcstrings`).

| English | id (di aplikasi) |
|---|---|
| Shutter | Rana |
| Shoot | Potret |
| Focus | Fokus |
| AF hold | Tahan AF |
| Bulb | Bulb |
| Release delay | Tunda rana |
| Intervalometer | Intervalometer |
| Timelapse | Timelapse |
| Frames | Frame |
| Geotag | Geotag |
| Geotagging | Geotagging |
| GPS tracks | Jejak GPS |
| Track | Jejak |
| End session | Akhiri sesi |
| Pair again | Pasangkan lagi |
| Pairing mode | Mode pemasangan |
| Fired, confirmed | Terpicu, dikonfirmasi |
| Sent | Terkirim |
| Sent, not confirmed | Terkirim, tidak dikonfirmasi |
| confirmed (penghitung) | dikonfirmasi |
| Auto reconnect | Sambung ulang otomatis |
| Auto disconnect | Putus otomatis |
| Remote + Geotag | Remote + Geotag |
| Remote only | Hanya remote |
| Geotag only | Hanya geotag |
| Tap to shoot | Ketuk untuk memotret |
| Live Activity | Aktivitas Langsung |
| Settings | Pengaturan |
| Export CSV | Ekspor CSV |
| Send location | Kirim lokasi |

**Jaga perbedaan «Terpicu» dan «Terkirim».** «Terpicu» hanya jika kamera
mengonfirmasi pemotretan; «Terkirim» jika perintah sudah dikirim tetapi kamera
tidak mengonfirmasi. Seluruh daya tarik aplikasi bertumpu pada perbedaan ini.

**Kata yang dipakai teks tetapi tidak ada di aplikasi:** «bulb berwaktu» (timed
bulb), «dongle», «kartu Tumpukan Pintar». Gerakan tangan Double Tap memakai istilah
Apple «Ketuk Dua Kali» (huruf besar), sedangkan ketukan dua kali di layar ditulis
«ketuk dua kali» (huruf kecil).

**Satu kata glosarium xMosaique tidak dipakai:** «Light» di xMosaique adalah efek
cahaya («Cahaya»); di xGRC «Light» adalah tampilan terang, jadi aplikasi memakai
istilah Apple «Terang».

---

## Ringkasan / At a glance

| Kolom | Nilai |
|---|---|
| App name | xGRC - Remote Kamera & Geotag |
| Subtitle | Rana dan GPS di pergelangan |
| Primary category | Photo & Video |
| Secondary category | Utilities |
| Age rating | 4+ |
| Persyaratan | iOS 17.0 atau lebih baru (iPhone, iPad); watchOS 10.0 atau lebih baru (Apple Watch) |
| Bahasa | 13 |

Kategori dipilih, bukan ditulis — App Store Connect menerjemahkannya sendiri.

---

## Nama aplikasi (30 karakter)

```
xGRC - Remote Kamera & Geotag
```
[29]

Nama di bawah ikon tetap `xGRC`; ini hanya nama listing. Apple mengindeks nama dan
subjudul untuk pencarian, jadi «remote», «kamera», «geotag», «rana», «GPS», dan
«pergelangan» tidak diulang di kata kunci.

Alternatif:

```
xGRC: Remote Kamera & Tag GPS
```
[29]

---

## Subjudul (30 karakter)

```
Rana dan GPS di pergelangan
```
[27]

Alternatif:

```
Rana Bluetooth, jam & GPS
```
[25]

```
Remote kamera, tanpa kabel
```
[26]

---

## Teks promosi (170 karakter — bisa diubah tanpa build baru)

```
Picu kamera dari iPhone, iPad, atau Apple Watch: bulb berwaktu, tunda rana, timelapse, dan GPS di setiap foto. Tanpa dongle. Tanpa akun. Tak ada data dikumpulkan.
```
[162]

«Tak ada data dikumpulkan» sama dengan jawaban App Privacy «Data Not Collected».

---

## Kata kunci (100 karakter, dipisah koma, tanpa spasi)

```
intervalometer,timelapse,bulb,pemicu,mirrorless,exif,geotagging,lokasi,fotografi,dslr,shutter,jam
```
[97]

**Campuran Inggris dan Indonesia, disengaja**: banyak fotografer Indonesia mencari
dengan istilah Inggris («shutter», «mirrorless», «dslr»). **Tanpa nama merek** —
Sony, Fujifilm, Canon, Nikon, dan Ricoh adalah merek dagang; di Deskripsi mereka
hanya disebut sebagai kompatibilitas. Kata dari nama dan subjudul tidak diulang.

---

## Deskripsi (4.000 karakter)

Tempel blok ini apa adanya. Setiap paragraf sengaja satu baris panjang — App Store
Connect mempertahankan setiap baris baru.

```
xGRC mengubah iPhone, iPad, dan Apple Watch Anda menjadi remote Bluetooth untuk kamera, sekaligus GPS-nya. xGRC berkomunikasi langsung dengan Bluetooth bawaan kamera Sony, Fujifilm, Canon, Nikon, dan Ricoh: tanpa dongle, tanpa Wi-Fi, tanpa menunggu aplikasi produsen.

SATU KETUKAN UNTUK FOKUS, DUA KETUKAN UNTUK MEMOTRET
Rana bekerja sama di mana pun. Ketuk sekali untuk fokus, ketuk dua kali untuk memotret. Gunakan Tahan AF jika Anda ingin fokus terkunci sambil menunggu momen yang tepat.

TERPICU HANYA JIKA BENAR-BENAR TERPICU
Jika kamera mengonfirmasi pemotretan, xGRC menampilkan Terpicu dan menghitungnya. Jika Bluetooth kamera tidak punya konfirmasi, xGRC menampilkan Terkirim. Penghitung dikonfirmasi dan terkirim tidak pernah berpura-pura.

EKSPOSUR PANJANG TANPA KABEL
• Bulb berwaktu: atur waktu hingga 99 mnt 59 dtk, ketuk sekali, dan rana menutup sendiri saat hitung mundur selesai
• Tunda rana 1 hingga 60 detik, agar tangan Anda tidak menyentuh kamera saat rana terpicu
• Intervalometer untuk timelapse: interval, jumlah frame atau sampai dihentikan, tunda sebelum mulai, dan waktu rana terbuka opsional

GPS DI SETIAP FOTO
xGRC mengirim lokasi dan waktu perangkat Anda ke kamera, yang menuliskannya ke setiap foto yang diambil. Di iPhone, xGRC tetap berjalan saat ponsel terkunci dan tampil di Dynamic Island serta Layar Terkunci. Di Apple Watch, xGRC melakukan geotag sendiri, dengan ponsel ditinggal di rumah. Setiap sesi menyimpan jejak GPS-nya di perangkat Anda, setiap posisi beserta waktunya: lihat sebagai titik-titik di peta di iPhone dan iPad, dan ekspor sebagai file CSV dari perangkat mana pun.

APLIKASI APPLE WATCH SUNGGUHAN
Pindai, pasangkan, potret, dan geotag dari jam tangan, tanpa iPhone. Di Apple Watch Series 9, Ultra 2, dan yang lebih baru, Ketuk Dua Kali dengan jari telunjuk dan ibu jari memicu rana, sehingga tangan yang memegang kamera tetap di tempatnya. Nyalakan Ketuk untuk memotret, dan satu ketukan di layar memfokus lalu memotret. Kartu Tumpukan Pintar menampilkan sesi secara sekilas.

DIBUAT UNTUK DI LAPANGAN
• Pilih Remote + Geotag, Hanya remote, atau Hanya geotag
• Sambung ulang otomatis melanjutkan sesi saat kamera aktif kembali atau kembali dalam jangkauan
• Putus otomatis melepas kamera setelah beberapa saat tanpa aktivitas, 15 menit kecuali Anda mengubahnya
• Pintasan dan Kontrol: Potret, Fokus, Mulai dan Hentikan geotagging
• Tampilan terang, gelap, atau sistem di iPhone dan iPad
• Kontrol besar yang nyaman dipakai dengan sarung tangan, dan getaran haptik yang jelas
• Tiga belas bahasa, dipilih di Pengaturan

BEKERJA DENGAN
• Kamera Sony Alpha, ZV, RX, dan FX dengan remote control Bluetooth
• Fujifilm X dan GFX
• Canon EOS dan PowerShot, dalam pemasangan Remote atau Smartphone
• Nikon, dalam mode remote (ML-L7)
• Ricoh GR III, GR IIIx, dan GR IV
Kemampuan setiap kamera melalui Bluetooth berbeda-beda: fokus, bulb, dan geotagging tidak tersedia di setiap merek atau mode. Daftar lengkapnya ada di halaman GitHub proyek, yang ditautkan dari Tentang.

PRIVAT SEJAK DIRANCANG
Tanpa akun, tanpa analitik, tanpa iklan, tanpa server. Lokasi Anda hanya dikirim ke kamera Anda, melalui Bluetooth, dan ke jejak yang tetap tersimpan di perangkat Anda sampai Anda mengekspor atau menghapusnya. xGRC adalah open source dengan lisensi GPLv3.

xGRC tidak berafiliasi dengan Sony, Fujifilm, Canon, Nikon, atau Ricoh. Nama merek adalah merek dagang pemiliknya masing-masing.
```
[3,436]

**Sengaja tidak disebut** (seperti versi Inggris): transkrip Bluetooth di dalam
aplikasi, «Jaga kamera tetap aktif» (opsi geotagging Sony), dan tata letak bilah
samping iPad.

**Setiap baris merek lebih sempit dari «didukung»** — Deskripsi menyebut modenya
dan menyatakan jelas bahwa fitur berbeda per kamera. Jangan diperluas tanpa hasil
uji di perangkat.

---

## Yang Baru (4.000 karakter) — versi 1.0

Yang Baru untuk versi pertama tidak tampil di halaman toko, tetapi App Store Connect
tetap memintanya.

```
Rilis pertama xGRC: remote kamera Bluetooth dan geotagger GPS untuk iPhone, iPad, dan Apple Watch.
```
[98]

---

## Teks tangkapan layar

Tujuh bingkai; setiap teks dua baris pendek, seperti `lines` di
`AppStorePreview/tools/frames.json`. Hitungan `len()` tiap baris tercantum.

| # | Baris 1 | Baris 2 | Adegan |
|---|---|---|---|
| 1 | Remote untuk kamera Anda. [25] | Tanpa dongle atau aplikasi produsen. [36] | layar sesi, Sony terhubung dan geotagging |
| 2 | Disebut terpicu hanya jika [26] | kamera mengonfirmasinya. [24] | Terpicu · dikonfirmasi, 36 pemotretan dikonfirmasi |
| 3 | Atur waktu bulb. [16] | Sekali ketuk, menutup sendiri. [30] | bulb 2 mnt 30 dtk sedang menghitung mundur |
| 4 | Timelapse tanpa [15] | perlu membawa kabel. [20] | intervalometer sedang berjalan |
| 5 | GPS ponsel Anda, [16] | di setiap foto. [15] | layar Geotagging dengan peta |
| 6 | Untuk kamera mirrorless [23] | dan kamera saku. [16] | daftar kamera (tidak di iPad) |
| 7 | Tunda rana, [11] | tangan lepas dari kamera. [25] | tunda 10 dtk sedang menghitung mundur |

Tangkapan layar Apple Watch tidak diberi teks. Bingkai berbahasa Indonesia perlu
diambil ulang dengan bahasa aplikasi diatur ke Indonesia.

---

## Catatan App Review, jawaban App Privacy, dan teks TestFlight

**Tetap dalam bahasa Inggris, jangan diterjemahkan** — teks aslinya ada di [appstore_intro.md](appstore_intro.md).

---

## Catatan penulisan — khusus bahasa Indonesia

- **«Terpicu» hanya untuk pemotretan yang dikonfirmasi**, seperti di aplikasi; selebihnya «Terkirim».
- **Merek hanya sebagai kompatibilitas** — tidak di nama, subjudul, atau kata kunci.
- **Jangan melebih-lebihkan dukungan**; kalimat «berbeda-beda per kamera» harus tetap ada.
- **Jangan menjanjikan pemotretan di latar belakang.** Di jam tangan, xGRC harus tampil di layar untuk memotret.
- **Tanpa harga** — diatur di App Store Connect.
- **Ukur ulang dengan Python `len()` setelah setiap perubahan.**

---

## Menunggu konfirmasi

- Seluruh teks dan string `id` aplikasi perlu dibaca penutur asli.
- **«Tunda rana»** (release delay) dan **«Terpicu»** (fired) adalah pilihan
  penerjemah; jika ada istilah kamera yang lebih lazim, ubah di aplikasi dan di teks
  sekaligus.
- Jalur Pengaturan iOS (Privasi & Keamanan, Layanan Lokasi, Lokasi Akurat, Pusat
  Kontrol, «Kembali ke Jam» di watchOS) perlu dicocokkan dengan iOS/watchOS
  berbahasa Indonesia.
- Apakah lokalisasi Indonesia sudah aktif di App Store Connect tidak bisa diketahui dari repositori.
