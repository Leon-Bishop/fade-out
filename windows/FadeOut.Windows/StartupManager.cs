using Microsoft.Win32;

namespace FadeOut.Windows;

internal static class StartupManager
{
    private const string KeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "FadeOut";

    public static bool IsEnabled
    {
        get
        {
            using var key = Registry.CurrentUser.OpenSubKey(KeyPath);
            return key?.GetValue(ValueName) is string;
        }
        set
        {
            using var key = Registry.CurrentUser.CreateSubKey(KeyPath, true);
            if (value)
            {
                var executable = Environment.ProcessPath
                    ?? throw new InvalidOperationException("Unable to locate Fade Out.");
                key.SetValue(ValueName, $"\"{executable}\" --background");
            }
            else
            {
                key.DeleteValue(ValueName, false);
            }
        }
    }
}
