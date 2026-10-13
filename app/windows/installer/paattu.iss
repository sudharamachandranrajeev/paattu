; Paattu for Windows: Inno Setup script. The release workflow builds the app
; (flutter build windows) and compiles this with
;   iscc /DAppVersion=0.2.0 windows\installer\paattu.iss
; Installs for the current user by default (no admin prompt); the installer
; offers an all-users install too.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#define Release "..\..\build\windows\x64\runner\Release"

[Setup]
AppId={{6E0B9C1E-3D4A-4F57-9B1E-7A5C2D8F0A61}
AppName=Paattu
AppVersion={#AppVersion}
AppVerName=Paattu {#AppVersion}
AppPublisher=Rajeev Sudharamachandran
AppPublisherURL=https://github.com/sudharamachandranrajeev/paattu
AppSupportURL=https://github.com/sudharamachandranrajeev/paattu/issues
AppUpdatesURL=https://github.com/sudharamachandranrajeev/paattu/releases
DefaultDirName={autopf}\Paattu
DefaultGroupName=Paattu
DisableProgramGroupPage=yes
LicenseFile=..\..\..\LICENSE
OutputDir=..\..\build\installer
OutputBaseFilename=Paattu-{#AppVersion}-windows-x64-setup
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\paattu.exe
UninstallDisplayName=Paattu
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
CloseApplications=yes
; Windows 10 1809 or later (and Windows 11)
MinVersion=10.0.17763

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#Release}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Paattu"; Filename: "{app}\paattu.exe"; Comment: "Malayalam & Tamil music"
Name: "{autodesktop}\Paattu"; Filename: "{app}\paattu.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\paattu.exe"; Description: "{cm:LaunchProgram,Paattu}"; Flags: nowait postinstall skipifsilent
