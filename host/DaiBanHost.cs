using System;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

internal static class Program
{
    private const string ProductVersion = "1.3.2";
    private const string AppUserModelId = "DaiBan.Todo.Desktop";

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int MessageBox(IntPtr owner, string text, string caption, uint type);

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern int SetCurrentProcessExplicitAppUserModelID(string appId);

    private static string LoadApplicationScript()
    {
        const string loader = ". (Join-Path $script:AppRoot 'Tracking.ps1')";
        string script = ReadResourceText("DaiBan.App.ps1");
        if (!script.Contains(loader)) throw new InvalidOperationException("Tracking module insertion point missing.");
        return script.Replace(loader, ReadResourceText("DaiBan.Tracking.ps1"));
    }

    [STAThread]
    private static int Main()
    {
        try
        {
            try
            {
                SetCurrentProcessExplicitAppUserModelID(AppUserModelId);
            }
            catch
            {
            }

            string localData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            string appRoot = Path.Combine(localData, "DaiBan", "host", ProductVersion);
            Directory.CreateDirectory(appRoot);
            Directory.CreateDirectory(Path.Combine(appRoot, "themes"));

            ExtractResource("DaiBan.ui.xaml", Path.Combine(appRoot, "ui.xaml"));

            ExtractResource("DaiBan.theme.light.xaml", Path.Combine(appRoot, "themes", "light.xaml"));
            ExtractResource("DaiBan.theme.dark.xaml", Path.Combine(appRoot, "themes", "dark.xaml"));
            ExtractResource("DaiBan.app.ico", Path.Combine(appRoot, "app.ico"));
            ExtractResource("DaiBan.LICENSE", Path.Combine(appRoot, "LICENSE"));

            string script = LoadApplicationScript();
            Environment.SetEnvironmentVariable("DAIBAN_APP_ROOT", appRoot);
            Environment.CurrentDirectory = AppDomain.CurrentDomain.BaseDirectory;

            using (Runspace runspace = RunspaceFactory.CreateRunspace())
            {
                runspace.ApartmentState = ApartmentState.STA;
                runspace.Open();

                using (PowerShell powerShell = PowerShell.Create())
                {
                    powerShell.Runspace = runspace;
                    powerShell.AddScript(script);

                    try
                    {
                        powerShell.Invoke();
                    }
                    catch (Exception ex)
                    {
                        WriteHostLog(ex);
                        ShowError("待办启动失败。\r\n\r\n" + ex.Message);
                        return 1;
                    }

                    if (powerShell.Streams.Error.Count > 0)
                    {
                        StringBuilder errors = new StringBuilder();
                        foreach (ErrorRecord error in powerShell.Streams.Error)
                        {
                            errors.AppendLine(error.ToString());
                        }
                        WriteHostLog(errors.ToString());
                    }
                }
            }

            return 0;
        }
        catch (Exception ex)
        {
            WriteHostLog(ex);
            ShowError("待办启动失败。\r\n\r\n" + ex.Message);
            return 1;
        }
    }

    private static void ExtractResource(string resourceName, string destination)
    {
        using (Stream source = OpenResource(resourceName))
        using (FileStream target = new FileStream(destination, FileMode.Create, FileAccess.Write, FileShare.None))
        {
            source.CopyTo(target);
        }
    }

    private static string ReadResourceText(string resourceName)
    {
        using (Stream source = OpenResource(resourceName))
        using (StreamReader reader = new StreamReader(source, Encoding.UTF8, true))
        {
            return reader.ReadToEnd();
        }
    }

    private static Stream OpenResource(string resourceName)
    {
        Stream stream = Assembly.GetExecutingAssembly().GetManifestResourceStream(resourceName);
        if (stream == null)
        {
            throw new InvalidOperationException("Missing embedded resource: " + resourceName);
        }
        return stream;
    }

    private static void WriteHostLog(Exception ex)
    {
        WriteHostLog(ex == null ? "Unknown error." : ex.ToString());
    }

    private static void WriteHostLog(string message)
    {
        try
        {
            string folder = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                "DaiBan");
            Directory.CreateDirectory(folder);
            File.AppendAllText(
                Path.Combine(folder, "host.log"),
                "[" + DateTime.Now.ToString("s") + "] " + message + Environment.NewLine,
                Encoding.UTF8);
        }
        catch
        {
        }
    }

    private static void ShowError(string message)
    {
        try
        {
            MessageBox(IntPtr.Zero, message, "待办", 0x00000010);
        }
        catch
        {
        }
    }
}
