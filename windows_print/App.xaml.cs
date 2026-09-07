using Microsoft.UI.Xaml;
using Microsoft.Windows.AppLifecycle;
using Windows.ApplicationModel.Activation;

namespace CYViewer.Print;

public partial class App : Application
{
    private Window? _window;

    public App() => InitializeComponent();

    protected override void OnLaunched(Microsoft.UI.Xaml.LaunchActivatedEventArgs args)
    {
        string? pdfPath = null;
        var activation = AppInstance.GetCurrent().GetActivatedEventArgs();
        if (activation.Kind == ExtendedActivationKind.Protocol && activation.Data is ProtocolActivatedEventArgs protocol)
        {
            var encoded = protocol.Uri.Query.TrimStart('?').Split('&')
                .FirstOrDefault(part => part.StartsWith("path=", StringComparison.OrdinalIgnoreCase));
            if (encoded is not null)
                pdfPath = Uri.UnescapeDataString(encoded[5..]);
        }
        pdfPath ??= Environment.GetCommandLineArgs().Skip(1).FirstOrDefault();
        _window = new MainWindow(pdfPath);
        _window.Activate();
    }
}
