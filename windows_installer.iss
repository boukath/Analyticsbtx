; --- INNO SETUP SCRIPT FOR BOITEXINFO ANALYTICS ---

#define MyAppName "BoitexInfo Analytics"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "BoitexInfo"
; 🚀 FIXED: Updated to match your actual executable name!
#define MyAppExeName "BoitexInfo_Analytics.exe"

[Setup]
; AppId uniquely identifies this application. DO NOT use the same AppId for other apps.
; (Make sure to replace this with your generated GUID from Tools > Generate GUID)
AppId={{8C42E782-884F-41D6-9D20-82B6FEF8B7BA}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
; This is where the app will install on the user's computer (Program Files)
DefaultDirName={autopf}\{#MyAppName}
; Prevents users from installing the same app multiple times
DisableProgramGroupPage=yes
; The name of the installer file you will give to users
OutputBaseFilename=BoitexInfo_Analytics_Setup
; Uses your existing app icon for the installer file itself
SetupIconFile=assets\app_icon.ico
Compression=lzma
SolidCompression=yes
; Requires Windows 10 or newer (Standard for Flutter Windows apps)
MinVersion=10.0.10240

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Tasks]
; Gives the user a checkbox to create a desktop shortcut
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; IMPORTANT: This points to your built Flutter files. 
; Make sure this script is saved in the ROOT of your Flutter project folder!
Source: "build\windows\x64\runner\Release\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; Note: Don't use "Flags: ignoreversion" on any shared system files

[Icons]
; Creates the shortcuts in the Start Menu and on the Desktop
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
; Gives the user a checkbox to launch the app immediately after installation
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent