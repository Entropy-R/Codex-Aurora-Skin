#ifndef AppVersion
  #error AppVersion must be supplied by build-release.ps1
#endif
#ifndef StageRoot
  #error StageRoot must be supplied by build-release.ps1
#endif
#ifndef OutputDir
  #error OutputDir must be supplied by build-release.ps1
#endif

#define AppName "Codex Aurora Skin"
#define AppPublisher "Entropy-R"
#define AppUrl "https://github.com/Entropy-R/Codex-Aurora-Skin"
#define PowerShellPath "{sysnative}\WindowsPowerShell\v1.0\powershell.exe"

[Setup]
AppId={{CF71617D-6475-46F8-BC26-049F5F66B424}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppUrl}
AppSupportURL={#AppUrl}
AppUpdatesURL=https://github.com/Entropy-R/Codex-Aurora-Skin/releases
DefaultDirName={localappdata}\Programs\CodexAuroraSkin
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
WizardStyle=modern
Compression=lzma2/ultra64
SolidCompression=yes
OutputDir={#OutputDir}
OutputBaseFilename=CodexAuroraSkin-Setup-v{#AppVersion}
SetupIconFile={#StageRoot}\payload\assets\codex-aurora-skin.ico
UninstallDisplayIcon={app}\payload\assets\codex-aurora-skin.ico
UninstallDisplayName={#AppName}
VersionInfoVersion={#AppVersion}.0
VersionInfoCompany={#AppPublisher}
VersionInfoDescription={#AppName} installer
VersionInfoProductName={#AppName}
VersionInfoProductVersion={#AppVersion}
CloseApplications=no
RestartApplications=no
RestartIfNeededByRun=no
ChangesAssociations=no
ChangesEnvironment=no
SetupLogging=yes
MinVersion=10.0

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "chinesesimplified"; MessagesFile: "{#StageRoot}\languages\ChineseSimplified.isl"

[Messages]
english.ConfirmUninstall=Uninstall will close Codex, restore its original appearance, remove the Aurora Skin runtime, and keep saved themes and images.%n%nContinue?
chinesesimplified.ConfirmUninstall=卸载将关闭 Codex、恢复官方外观并移除 Aurora Skin 运行时；已保存主题和图片会保留。%n%n是否继续？

[Files]
; Keep a second, temporary copy so initialization runs before Inno starts
; copying/registering the installed application files. Exceptions from
; CurStepChanged(ssInstall) are fatal and therefore stop Setup cleanly.
Source: "{#StageRoot}\setup-bootstrap.ps1"; DestDir: "{tmp}"; Flags: dontcopy noencryption
Source: "{#StageRoot}\payload\*"; DestDir: "{tmp}\payload"; Flags: dontcopy noencryption recursesubdirs createallsubdirs
Source: "{#StageRoot}\setup-bootstrap.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#StageRoot}\CodexAuroraSkin.Launcher.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#StageRoot}\LICENSE.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#StageRoot}\NOTICE.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#StageRoot}\payload\*"; DestDir: "{app}\payload"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Codex Aurora Skin"; Filename: "{app}\CodexAuroraSkin.Launcher.exe"; WorkingDir: "{app}"; IconFilename: "{app}\payload\assets\codex-aurora-skin.ico"
Name: "{group}\恢复官方外观"; Filename: "{#PowerShellPath}"; Parameters: "-NoProfile -ExecutionPolicy RemoteSigned -File ""{localappdata}\CodexAuroraSkin\engine\scripts\restore-aurora-skin.ps1"" -ForceRestart"; WorkingDir: "{localappdata}\CodexAuroraSkin\engine"; IconFilename: "{app}\payload\assets\codex-aurora-skin.ico"

[Run]
Filename: "{app}\CodexAuroraSkin.Launcher.exe"; WorkingDir: "{app}"; Description: "启动 Codex Aurora Skin"; Flags: nowait postinstall skipifsilent

[Code]
function PowerShellArguments(
  const ScriptPath: String;
  const ActionArguments: String;
  const Silent: Boolean
): String;
begin
  Result := '-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy RemoteSigned -File ' +
    AddQuotes(ScriptPath) + ' ' + ActionArguments;
  if Silent then
    Result := Result + ' -Silent';
end;

function RunBootstrap(
  const ScriptPath: String;
  const ActionArguments: String;
  const Silent: Boolean;
  var ExitCode: Integer
): Boolean;
begin
  Result := Exec(
    ExpandConstant('{#PowerShellPath}'),
    PowerShellArguments(ScriptPath, ActionArguments, Silent),
    ExtractFileDir(ScriptPath),
    SW_HIDE,
    ewWaitUntilTerminated,
    ExitCode
  );
end;

function InstallInitializationFailureMessage(const ExitCode: Integer): String;
begin
  Result := 'Codex Aurora Skin could not be initialized (exit code ' +
    IntToStr(ExitCode) + '). No installed application files were changed.';
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ExitCode: Integer;
  TemporaryBootstrap: String;
begin
  if CurStep <> ssInstall then
    exit;

  ExtractTemporaryFiles('{tmp}\setup-bootstrap.ps1');
  ExtractTemporaryFiles('{tmp}\payload\*');
  TemporaryBootstrap := ExpandConstant('{tmp}\setup-bootstrap.ps1');
  if not RunBootstrap(TemporaryBootstrap, '-Install', WizardSilent, ExitCode) then
    RaiseException('Codex Aurora Skin initialization could not be started.');
  if ExitCode <> 0 then
    RaiseException(InstallInitializationFailureMessage(ExitCode));
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  ExitCode: Integer;
begin
  if CurUninstallStep <> usUninstall then
    exit;

  { The standard Inno confirmation has completed before usUninstall. }
  if not RunBootstrap(ExpandConstant('{app}\setup-bootstrap.ps1'), '-Uninstall', True, ExitCode) then
    RaiseException('Codex Aurora Skin restoration could not be started. No installed files were removed.');
  if ExitCode <> 0 then
    RaiseException(
      'Codex Aurora Skin could not restore Codex (exit code ' +
      IntToStr(ExitCode) + '). No installed files were removed.'
    );
end;
