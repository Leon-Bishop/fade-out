using System.Diagnostics;
using System.Drawing;
using System.Text.Json;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using NAudio.CoreAudioApi;

namespace FadeOut.Windows;

public sealed class AudioMixerService : IDisposable
{
    private static readonly HashSet<string> MusicApps = new(StringComparer.OrdinalIgnoreCase)
    {
        "spotify", "music", "itunes", "tidal", "deezer", "amazon music", "youtubemusic",
        "foobar2000", "vlc", "winamp", "audirvana", "qobuz"
    };

    private static readonly HashSet<string> Browsers = new(StringComparer.OrdinalIgnoreCase)
    {
        "chrome", "msedge", "firefox", "brave", "opera", "vivaldi", "arc", "waterfox"
    };

    private static readonly HashSet<string> CommunicationApps = new(StringComparer.OrdinalIgnoreCase)
    {
        "discord", "slack", "teams", "ms-teams", "zoom", "telegram", "whatsapp", "signal", "skype"
    };

    private static readonly HashSet<string> ExcludedProcesses = new(StringComparer.OrdinalIgnoreCase)
    {
        "audiodg", "svchost", "system", "registry"
    };

    private readonly MMDeviceEnumerator _enumerator = new();
    private readonly string _settingsPath;
    private readonly Dictionary<string, float> _savedVolumes;
    private MMDevice? _device;

    public AudioMixerService()
    {
        var directory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "FadeOut");
        Directory.CreateDirectory(directory);
        _settingsPath = Path.Combine(directory, "settings.json");
        _savedVolumes = LoadSettings();
    }

    public string DeviceName => _device?.FriendlyName ?? "Default output";

    public double MasterVolume
    {
        get
        {
            try { return (_device?.AudioEndpointVolume.MasterVolumeLevelScalar ?? 1f) * 100; }
            catch { return 100; }
        }
        set
        {
            try
            {
                if (_device is not null)
                    _device.AudioEndpointVolume.MasterVolumeLevelScalar = Math.Clamp((float)value / 100f, 0f, 1f);
            }
            catch { }
        }
    }

    public IReadOnlyList<AppMixerItem> Refresh()
    {
        RefreshDefaultDevice();
        if (_device is null) return Array.Empty<AppMixerItem>();

        var groups = new Dictionary<string, SessionGroup>(StringComparer.OrdinalIgnoreCase);
        try
        {
            var sessions = _device.AudioSessionManager.Sessions;
            for (var index = 0; index < sessions.Count; index++)
            {
                var session = sessions[index];
                if (session.IsSystemSoundsSession || session.State == AudioSessionState.AudioSessionStateExpired)
                    continue;

                var processId = (int)session.GetProcessID;
                if (processId <= 0) continue;

                try
                {
                    using var process = Process.GetProcessById(processId);
                    var processName = process.ProcessName;
                    if (ExcludedProcesses.Contains(processName)) continue;

                    var path = TryGetProcessPath(process);
                    var id = string.IsNullOrWhiteSpace(path) ? processName.ToLowerInvariant() : path.ToLowerInvariant();
                    if (!groups.TryGetValue(id, out var group))
                    {
                        group = new SessionGroup(
                            id,
                            GetDisplayName(process, path),
                            GetIcon(path),
                            GetPriority(processName));
                        groups.Add(id, group);
                    }
                    group.Sessions.Add(session.SimpleAudioVolume);
                }
                catch { }
            }
        }
        catch { return Array.Empty<AppMixerItem>(); }

        return groups.Values
            .Select(group => BuildItem(group))
            .OrderBy(item => item.Priority)
            .ThenBy(item => item.Name, StringComparer.CurrentCultureIgnoreCase)
            .ToArray();
    }

    private AppMixerItem BuildItem(SessionGroup group)
    {
        var current = group.Sessions.Count == 0 ? 1f : group.Sessions.Average(session => session.Volume);
        var muted = group.Sessions.Count > 0 && group.Sessions.All(session => session.Mute);
        if (_savedVolumes.TryGetValue(group.Id, out var saved))
        {
            current = saved;
            foreach (var session in group.Sessions)
            {
                try { session.Volume = saved; } catch { }
            }
        }
        return new AppMixerItem(group.Id, group.Name, group.Icon, group.Priority,
            group.Sessions, current, muted, SaveVolume);
    }

    private void RefreshDefaultDevice()
    {
        try
        {
            var next = _enumerator.GetDefaultAudioEndpoint(DataFlow.Render, Role.Multimedia);
            if (_device?.ID == next.ID)
            {
                next.Dispose();
                return;
            }
            _device?.Dispose();
            _device = next;
        }
        catch
        {
            _device?.Dispose();
            _device = null;
        }
    }

    private static string? TryGetProcessPath(Process process)
    {
        try { return process.MainModule?.FileName; }
        catch { return null; }
    }

    private static string GetDisplayName(Process process, string? path)
    {
        try
        {
            var description = path is null ? null : FileVersionInfo.GetVersionInfo(path).FileDescription;
            if (!string.IsNullOrWhiteSpace(description)) return description;
        }
        catch { }
        return process.ProcessName;
    }

    private static ImageSource? GetIcon(string? path)
    {
        if (string.IsNullOrWhiteSpace(path)) return null;
        try
        {
            using var icon = Icon.ExtractAssociatedIcon(path);
            if (icon is null) return null;
            var image = Imaging.CreateBitmapSourceFromHIcon(
                icon.Handle, System.Windows.Int32Rect.Empty, BitmapSizeOptions.FromWidthAndHeight(32, 32));
            image.Freeze();
            return image;
        }
        catch { return null; }
    }

    private static int GetPriority(string processName)
    {
        if (MusicApps.Contains(processName)) return 0;
        if (Browsers.Contains(processName)) return 1;
        if (CommunicationApps.Contains(processName)) return 2;
        return 3;
    }

    private Dictionary<string, float> LoadSettings()
    {
        try
        {
            return JsonSerializer.Deserialize<Dictionary<string, float>>(File.ReadAllText(_settingsPath))
                ?? new Dictionary<string, float>(StringComparer.OrdinalIgnoreCase);
        }
        catch { return new Dictionary<string, float>(StringComparer.OrdinalIgnoreCase); }
    }

    private void SaveVolume(string id, float volume)
    {
        _savedVolumes[id] = volume;
        try
        {
            File.WriteAllText(_settingsPath,
                JsonSerializer.Serialize(_savedVolumes, new JsonSerializerOptions { WriteIndented = true }));
        }
        catch { }
    }

    public void Dispose()
    {
        _device?.Dispose();
        _enumerator.Dispose();
    }

    private sealed record SessionGroup(string Id, string Name, ImageSource? Icon, int Priority)
    {
        public List<SimpleAudioVolume> Sessions { get; } = new();
    }
}
