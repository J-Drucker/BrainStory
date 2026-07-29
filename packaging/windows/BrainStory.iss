#define AppVersion GetEnv("BRAINSTORY_VERSION")
#define BuildDir GetEnv("BRAINSTORY_BUILD_DIR")
#define OutputDir GetEnv("BRAINSTORY_OUTPUT_DIR")
#define RepositoryRoot GetEnv("BRAINSTORY_REPOSITORY_ROOT")

#if AppVersion == ""
  #error "BRAINSTORY_VERSION is required."
#endif
#if BuildDir == ""
  #error "BRAINSTORY_BUILD_DIR is required."
#endif
#if OutputDir == ""
  #error "BRAINSTORY_OUTPUT_DIR is required."
#endif
#if RepositoryRoot == ""
  #error "BRAINSTORY_REPOSITORY_ROOT is required."
#endif

[Setup]
AppId={{26BC1D1F-91A9-4E7E-88DF-0F27D093E9EF}
AppName=BrainStory
AppVersion={#AppVersion}
AppVerName=BrainStory {#AppVersion}
AppPublisher=BrainStory
DefaultDirName={localappdata}\Programs\BrainStory
DefaultGroupName=BrainStory
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir={#OutputDir}
OutputBaseFilename=BrainStory-Setup-{#AppVersion}-x64
SetupIconFile={#RepositoryRoot}\gui\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\brainstory_gui.exe
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
CloseApplications=yes
RestartApplications=no

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Shortcuts:"; Flags: unchecked

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#RepositoryRoot}\engine\vendor\libeep\LICENSE"; DestDir: "{app}\licenses\libeep"; Flags: ignoreversion
Source: "{#RepositoryRoot}\engine\vendor\libeep\LICENSE.addendum"; DestDir: "{app}\licenses\libeep"; Flags: ignoreversion
Source: "{#RepositoryRoot}\engine\vendor\libeep\NOTICE.md"; DestDir: "{app}\licenses\libeep"; Flags: ignoreversion

[Icons]
Name: "{group}\BrainStory"; Filename: "{app}\brainstory_gui.exe"
Name: "{autodesktop}\BrainStory"; Filename: "{app}\brainstory_gui.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\brainstory_gui.exe"; Description: "Launch BrainStory"; Flags: nowait postinstall skipifsilent
