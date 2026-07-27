Option Explicit

Dim shell, fileSystem, appRoot, powershellPath, bootstrapPath, sessionPath, command
Dim exitCode, attempt
Set shell = CreateObject("WScript.Shell")
Set fileSystem = CreateObject("Scripting.FileSystemObject")

appRoot = fileSystem.GetParentFolderName(WScript.ScriptFullName)
powershellPath = fileSystem.BuildPath( _
  shell.ExpandEnvironmentStrings("%SystemRoot%"), _
  "System32\WindowsPowerShell\v1.0\powershell.exe" _
)
bootstrapPath = fileSystem.BuildPath(appRoot, "setup-bootstrap.ps1")
sessionPath = fileSystem.BuildPath( _
  shell.ExpandEnvironmentStrings("%LOCALAPPDATA%"), _
  "CodexAuroraSkin\manager-session.json" _
)
command = """" & powershellPath & _
  """ -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy RemoteSigned -File """ & _
  bootstrapPath & """ -LaunchManager"

' 等待 bootstrap 返回后，再等管理器写出会话文件，避免宿主退出与后台启动竞争。
exitCode = shell.Run(command, 0, True)
If exitCode <> 0 Then WScript.Quit exitCode

For attempt = 1 To 100
  If fileSystem.FileExists(sessionPath) Then Exit For
  WScript.Sleep 100
Next

WScript.Quit 0
