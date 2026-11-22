using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Windows;
using System.Windows.Input;
using System.Windows.Threading;
using Forms = System.Windows.Forms;

namespace FadeOut.Windows;

public partial class MainWindow : Window
{
    private readonly AudioMixerService _audio = new();
    private readonly ObservableCollection<AppMixerItem> _items = new();
    private readonly DispatcherTimer _refreshTimer;
    private readonly Forms.NotifyIcon _trayIcon;
    private bool _updatingMaster;
    private bool _updatingStartup;
    private bool _quitting;

    public MainWindow()
    {
        InitializeComponent();
        MixerItems.ItemsSource = _items;

        _trayIcon = new Forms.NotifyIcon
        {
            Icon = System.Drawing.Icon.ExtractAssociatedIcon(Environment.ProcessPath!),
            Text = "fadeout",
            Visible = true
        };
        _trayIcon.DoubleClick += (_, _) => Dispatcher.Invoke(ShowFromTray);
        var menu = new Forms.ContextMenuStrip();
        menu.Items.Add("Open mixer", null, (_, _) => Dispatcher.Invoke(ShowFromTray));
        menu.Items.Add("Quit", null, (_, _) => Dispatcher.Invoke(Quit));
        _trayIcon.ContextMenuStrip = menu;

        _refreshTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(2) };
        _refreshTimer.Tick += (_, _) => RefreshMixer();

        Loaded += (_, _) =>
        {
            _updatingStartup = true;
            StartupCheck.IsChecked = StartupManager.IsEnabled;
            _updatingStartup = false;
            RefreshMixer();
            _refreshTimer.Start();
            if (Environment.GetCommandLineArgs().Contains("--background", StringComparer.OrdinalIgnoreCase))
                Hide();
        };
    }

    private void RefreshMixer()
    {
        var rows = _audio.Refresh();
        _items.Clear();
        foreach (var row in rows) _items.Add(row);

        _updatingMaster = true;
        MasterSlider.Value = _audio.MasterVolume;
        MasterLabel.Text = $"{Math.Round(MasterSlider.Value):0}%";
        _updatingMaster = false;
        ActiveLabel.Text = $"{rows.Count} available";
        DeviceLabel.Text = $"output  ·  {_audio.DeviceName}";
        EmptyState.Visibility = rows.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
    }

    private void MasterSlider_Changed(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        MasterLabel.Text = $"{Math.Round(e.NewValue):0}%";
        if (!_updatingMaster) _audio.MasterVolume = e.NewValue;
    }

    private static void Mute_Click(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { DataContext: AppMixerItem item }) item.ToggleMute();
    }

    private void Startup_Changed(object sender, RoutedEventArgs e)
    {
        if (_updatingStartup) return;
        try { StartupManager.IsEnabled = StartupCheck.IsChecked == true; }
        catch
        {
            _updatingStartup = true;
            StartupCheck.IsChecked = StartupManager.IsEnabled;
            _updatingStartup = false;
        }
    }

    private void Header_Drag(object sender, MouseButtonEventArgs e)
    {
        if (e.LeftButton == MouseButtonState.Pressed) DragMove();
    }

    private void Minimize_Click(object sender, RoutedEventArgs e) => WindowState = WindowState.Minimized;
    private void Hide_Click(object sender, RoutedEventArgs e) => Hide();

    private void ShowFromTray()
    {
        Show();
        WindowState = WindowState.Normal;
        Activate();
    }

    private void Quit_Click(object sender, RoutedEventArgs e) => Quit();

    private void Quit()
    {
        _quitting = true;
        _refreshTimer.Stop();
        _trayIcon.Visible = false;
        _trayIcon.Dispose();
        _audio.Dispose();
        Close();
        System.Windows.Application.Current.Shutdown();
    }

    protected override void OnClosing(CancelEventArgs e)
    {
        if (!_quitting)
        {
            e.Cancel = true;
            Hide();
        }
        base.OnClosing(e);
    }
}
