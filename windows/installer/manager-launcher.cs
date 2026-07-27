using System;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows.Forms;

namespace CodexAuroraSkin
{
    internal static class ManagerLauncher
    {
        [STAThread]
        private static int Main()
        {
            try
            {
                string appRoot = AppDomain.CurrentDomain.BaseDirectory;
                string powershellPath = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.System),
                    @"WindowsPowerShell\v1.0\powershell.exe");
                string bootstrapPath = Path.Combine(appRoot, "setup-bootstrap.ps1");
                string sessionPath = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    @"CodexAuroraSkin\manager-session.json");

                var startInfo = new ProcessStartInfo
                {
                    FileName = powershellPath,
                    Arguments = "-NoProfile -STA -WindowStyle Hidden " +
                        "-ExecutionPolicy RemoteSigned -File " + Quote(bootstrapPath) +
                        " -LaunchManager",
                    WorkingDirectory = appRoot,
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    WindowStyle = ProcessWindowStyle.Hidden
                };

                using (Process process = Process.Start(startInfo))
                {
                    process.WaitForExit();
                    if (process.ExitCode != 0)
                    {
                        ShowError("主题管理器启动失败，退出代码：" + process.ExitCode + "。");
                        return process.ExitCode;
                    }
                }

                // bootstrap 会先退出；确认管理 API 可用后再交给 Shell 打开默认浏览器。
                for (int attempt = 0; attempt < 100; attempt++)
                {
                    string managerUrl;
                    if (TryGetManagerUrl(sessionPath, out managerUrl))
                    {
                        Process.Start(new ProcessStartInfo
                        {
                            FileName = managerUrl,
                            UseShellExecute = true
                        });
                        return 0;
                    }
                    Thread.Sleep(100);
                }

                ShowError("主题管理器未能在 10 秒内启动，请重新打开 Codex Aurora Skin。");
                return 1;
            }
            catch (Exception exception)
            {
                ShowError("主题管理器启动失败：" + exception.Message);
                return 1;
            }
        }

        private static string Quote(string value)
        {
            return "\"" + value.Replace("\"", "\\\"") + "\"";
        }

        private static bool TryGetManagerUrl(string sessionPath, out string managerUrl)
        {
            managerUrl = null;
            try
            {
                string json = File.ReadAllText(sessionPath);
                Match portMatch = Regex.Match(json, "\"port\"\\s*:\\s*(\\d+)");
                Match tokenMatch = Regex.Match(json, "\"token\"\\s*:\\s*\"([a-f0-9]{64})\"");
                int port;
                if (!portMatch.Success || !tokenMatch.Success ||
                    !int.TryParse(portMatch.Groups[1].Value, out port) ||
                    port < 1 || port > 65535)
                {
                    return false;
                }

                string token = tokenMatch.Groups[1].Value;
                var request = (HttpWebRequest)WebRequest.Create(
                    "http://127.0.0.1:" + port + "/api/ping");
                request.Proxy = null;
                request.Headers[HttpRequestHeader.Authorization] = "Bearer " + token;
                request.Timeout = 300;
                request.ReadWriteTimeout = 300;
                using (var response = (HttpWebResponse)request.GetResponse())
                {
                    if (response.StatusCode != HttpStatusCode.OK) return false;
                }

                managerUrl = "http://127.0.0.1:" + port + "/?bootstrap=" + token;
                return true;
            }
            catch
            {
                return false;
            }
        }

        private static void ShowError(string message)
        {
            MessageBox.Show(
                message,
                "Codex Aurora Skin",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
        }
    }
}
