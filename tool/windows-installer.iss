#ifndef AppVersion
  #error AppVersion must be supplied
#endif
#ifndef ReleaseSuffix
  #define ReleaseSuffix ""
#endif
[Setup]
AppId={{72445F13-B96A-4EC8-A374-19665B68B6D0}
AppName=FPT Knowledge
AppVersion={#AppVersion}
AppPublisher=FPT Knowledge project
DefaultDirName={localappdata}\Programs\FPT Knowledge
DefaultGroupName=FPT Knowledge
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir={#OutputDir}
OutputBaseFilename=FPT-Knowledge-v{#AppVersion}-Setup{#ReleaseSuffix}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\FPT Knowledge.exe
CloseApplications=yes

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\FPT Knowledge"; Filename: "{app}\FPT Knowledge.exe"
Name: "{autodesktop}\FPT Knowledge"; Filename: "{app}\FPT Knowledge.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked

[Run]
Filename: "{app}\FPT Knowledge.exe"; Description: "Open FPT Knowledge"; Flags: nowait postinstall skipifsilent

; Deliberately no AppData/vault deletion: uninstall preserves personal state.
