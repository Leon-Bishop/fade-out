using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows.Media;
using NAudio.CoreAudioApi;

namespace FadeOut.Windows;

public sealed class AppMixerItem : INotifyPropertyChanged
{
    private readonly IReadOnlyList<SimpleAudioVolume> _sessions;
    private readonly Action<string, float> _saveVolume;
    private float _volume;
    private bool _muted;

    public AppMixerItem(
        string id,
        string name,
        ImageSource? icon,
        int priority,
        IReadOnlyList<SimpleAudioVolume> sessions,
        float volume,
        bool muted,
        Action<string, float> saveVolume)
    {
        Id = id;
        Name = name;
        Icon = icon;
        Priority = priority;
        _sessions = sessions;
        _volume = volume;
        _muted = muted;
        _saveVolume = saveVolume;
    }

    public string Id { get; }
    public string Name { get; }
    public ImageSource? Icon { get; }
    public int Priority { get; }

    public double Volume
    {
        get => _volume * 100;
        set
        {
            var scalar = Math.Clamp((float)value / 100f, 0f, 1f);
            if (Math.Abs(_volume - scalar) < 0.001f) return;
            _volume = scalar;
            foreach (var session in _sessions)
            {
                try { session.Volume = scalar; } catch { }
            }
            _saveVolume(Id, scalar);
            OnPropertyChanged();
            OnPropertyChanged(nameof(VolumeLabel));
        }
    }

    public string VolumeLabel => $"{Math.Round(Volume):0}%";

    public bool IsMuted
    {
        get => _muted;
        private set
        {
            if (_muted == value) return;
            _muted = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(MuteGlyph));
        }
    }

    public string MuteGlyph => IsMuted ? "🔇" : "◖";

    public void ToggleMute()
    {
        IsMuted = !IsMuted;
        foreach (var session in _sessions)
        {
            try { session.Mute = IsMuted; } catch { }
        }
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    private void OnPropertyChanged([CallerMemberName] string? name = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}
