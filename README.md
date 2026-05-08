# MSAT ExamBrowser

Official ExamBrowser for MSAT CBT System.

## Fitur Windows Desktop
- **Full Screen Mode**: Aplikasi otomatis berjalan layar penuh.
- **Security Lock**: Mencegah aplikasi ditutup tanpa password proktor.
- **Kiosk Mode**: Meminimalisir gangguan dari aplikasi lain.

## Cara Build ke EXE

### 1. Otomatis (GitHub Actions)
Cukup lakukan `git push` ke branch `main` atau `master`. GitHub akan otomatis melakukan build dan menyediakan file `.exe` di menu **Actions**.

### 2. Manual (Lokal)
Jika ingin build di komputer sendiri, pastikan sudah terinstal **Visual Studio 2022** (dengan C++ Desktop development).

Jalankan perintah berikut di terminal:
```powershell
# 1. Inisialisasi folder windows (Hanya sekali)
flutter create --platforms=windows .

# 2. Build EXE
flutter build windows --release
```

Hasil build akan berada di folder:
`build/windows/x64/runner/Release/`
