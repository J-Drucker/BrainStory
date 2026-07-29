# BrainStory Windows installer

The installer contains the Flutter application, BrainStory's Rust engine,
Flutter and plugin DLLs, the app data directory, the Microsoft Visual C++
runtime DLLs, and the bundled LIBEEP license notices. End users do not need
Flutter, Rust, Cargo, Python, Visual Studio, or Inno Setup.

## Build in GitHub Actions

Open the repository's **Actions** tab, choose **Windows installer**, select
**Run workflow**, and enter a version such as `0.1.0`. The completed run
provides a `BrainStory-Windows-<version>` artifact containing the installer and
its SHA-256 checksum.

## Build on Windows

The build computer needs:

- Flutter with Windows desktop support
- Rust and Cargo
- Visual Studio 2022 with **Desktop development with C++**
- Inno Setup 6.3 or newer

From the repository root, run:

```powershell
.\scripts\build_windows_installer.ps1 -Version 0.1.0
```

The installer and checksum are written to `dist\`.
