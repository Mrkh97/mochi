; The Windows installer, built by `build.ps1 -Installer` with Inno Setup (https://jrsoftware.org/isinfo.php).
; One Mochi-Setup.exe for every PC: it carries both builds and installs the ARM64 one on ARM PCs and the
; x64 one everywhere else. It installs for the current user only, so it never asks for administrator rights.

#ifndef AppVersion
  #define AppVersion "1.0"
#endif

[Setup]
AppId={{BEC66BCF-DAC3-4F08-95A1-D0F2E03F5FE5}
AppName=Mochi
AppVersion={#AppVersion}
AppVerName=Mochi {#AppVersion}
AppPublisher=Mochi
AppPublisherURL=https://github.com/Mrkh97/mochi
AppSupportURL=https://github.com/Mrkh97/mochi/issues
DefaultDirName={localappdata}\Programs\Mochi
DisableDirPage=yes
DisableProgramGroupPage=yes
DisableReadyPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
CloseApplications=no
SetupIconFile=Mochi.ico
UninstallDisplayIcon={app}\Mochi.exe
UninstallDisplayName=Mochi
WizardStyle=modern
WizardImageFile=WizardImage-100.png,WizardImage-200.png
WizardSmallImageFile=WizardSmallImage-100.png,WizardSmallImage-200.png
WizardImageStretch=no
WizardImageBackColor=clWhite
Compression=lzma2/ultra64
SolidCompression=yes
OutputDir=..\build
OutputBaseFilename=Mochi-Setup

[Tasks]
Name: startup; Description: "Start Mochi when I sign in"
Name: desktopicon; Description: "Put a shortcut on the desktop"; Flags: unchecked

[Files]
Source: "..\build\Mochi-arm64\*"; DestDir: "{app}"; Check: IsArm64; Flags: ignoreversion
Source: "..\build\Mochi-x64\*"; DestDir: "{app}"; Check: not IsArm64; Flags: ignoreversion

[Icons]
Name: "{userprograms}\Mochi"; Filename: "{app}\Mochi.exe"
Name: "{userdesktop}\Mochi"; Filename: "{app}\Mochi.exe"; Tasks: desktopicon

[Registry]
; The same value Mochi's own Open at Login item writes, so the two agree.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "Mochi"; ValueData: """{app}\Mochi.exe"""; Tasks: startup
; Removed on uninstall however it was turned on.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: none; ValueName: "Mochi"; Flags: uninsdeletevalue

[Run]
Filename: "{app}\Mochi.exe"; Description: "Start Mochi now"; Flags: nowait postinstall

[UninstallDelete]
Type: files; Name: "{localappdata}\Mochi.exe.plist"

[Code]
// Mochi has to be closed before its files can be replaced or removed. Asking politely lets it save
// the cats first; it quits on WM_CLOSE, which is what taskkill sends without /F.
procedure CloseMochi();
var
  Code: Integer;
begin
  if Exec(ExpandConstant('{sys}\taskkill.exe'), '/IM Mochi.exe', '', SW_HIDE, ewWaitUntilTerminated, Code) and (Code = 0) then
  begin
    Sleep(1500);
    Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM Mochi.exe', '', SW_HIDE, ewWaitUntilTerminated, Code);
  end;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  CloseMochi();
  Result := '';
end;

function InitializeUninstall(): Boolean;
begin
  CloseMochi();
  Result := True;
end;
