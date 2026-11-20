using System.Windows;

namespace FadeOut.Windows;

public partial class App : Application
{
    private MainWindow? _window;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        _window = new MainWindow();
        _window.Show();
    }
}
