using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Microsoft.UI.Xaml.Printing;
using Windows.Data.Pdf;
using Windows.Graphics.Printing;
using Windows.Storage;
using Windows.Storage.Streams;

namespace CYViewer.Print;

public sealed partial class MainWindow : Window
{
    private readonly string? _pdfPath;
    private readonly List<BitmapImage> _pages = [];
    private PrintDocument? _printDocument;
    private IPrintDocumentSource? _printSource;
    private PrintManager? _printManager;
    private PrintTaskOptions? _printOptions;

    public MainWindow(string? pdfPath)
    {
        InitializeComponent();
        _pdfPath = pdfPath;
        Title = "CY뷰어 인쇄";
        AppWindow.Resize(new Windows.Graphics.SizeInt32(420, 180));
        Activated += OnActivated;
    }

    private async void OnActivated(object sender, WindowActivatedEventArgs args)
    {
        Activated -= OnActivated;
        try
        {
            if (string.IsNullOrWhiteSpace(_pdfPath) || !File.Exists(_pdfPath))
                throw new FileNotFoundException("인쇄할 PDF를 찾을 수 없습니다.");

            var file = await StorageFile.GetFileFromPathAsync(Path.GetFullPath(_pdfPath));
            var pdf = await PdfDocument.LoadFromFileAsync(file);
            for (uint index = 0; index < pdf.PageCount; index++)
            {
                using var page = pdf.GetPage(index);
                using var stream = new InMemoryRandomAccessStream();
                await page.RenderToStreamAsync(stream);
                stream.Seek(0);
                var bitmap = new BitmapImage();
                await bitmap.SetSourceAsync(stream);
                _pages.Add(bitmap);
            }

            RegisterPrinting();
            StatusText.Text = $"{_pages.Count}페이지 · Windows 인쇄창을 여는 중…";
            var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
            await PrintManagerInterop.ShowPrintUIForWindowAsync(hwnd);
        }
        catch (Exception error)
        {
            LoadingRing.IsActive = false;
            StatusText.Text = "인쇄 미리보기를 열 수 없습니다.\n" + error.Message;
        }
    }

    private void RegisterPrinting()
    {
        _printDocument = new PrintDocument();
        _printSource = _printDocument.DocumentSource;
        _printDocument.Paginate += (_, args) =>
        {
            _printOptions = args.PrintTaskOptions;
            _printDocument.SetPreviewPageCount(_pages.Count, PreviewPageCountType.Final);
        };
        _printDocument.GetPreviewPage += (_, args) =>
        {
            var description = _printOptions!.GetPageDescription((uint)Math.Max(0, args.PageNumber - 1));
            _printDocument.SetPreviewPage(args.PageNumber, CreatePrintPage(args.PageNumber - 1, description));
        };
        _printDocument.AddPages += (_, _) =>
        {
            for (var index = 0; index < _pages.Count; index++)
            {
                var description = _printOptions!.GetPageDescription((uint)index);
                _printDocument.AddPage(CreatePrintPage(index, description));
            }
            _printDocument.AddPagesComplete();
        };

        var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
        _printManager = PrintManagerInterop.GetForWindow(hwnd);
        _printManager.PrintTaskRequested += (_, args) =>
        {
            var task = args.Request.CreatePrintTask("CY뷰어 PDF 문서", sourceArgs => sourceArgs.SetSource(_printSource));
            task.Completed += (_, completed) => DispatcherQueue.TryEnqueue(() =>
            {
                StatusText.Text = completed.Completion == PrintTaskCompletion.Submitted
                    ? "인쇄 작업을 Windows 대기열에 보냈습니다."
                    : "인쇄가 취소되었거나 완료되지 않았습니다.";
                LoadingRing.IsActive = false;
            });
        };
    }

    private Grid CreatePrintPage(int pageIndex, PrintPageDescription description)
    {
        var root = new Grid
        {
            Width = description.PageSize.Width,
            Height = description.PageSize.Height,
            Background = new SolidColorBrush(Microsoft.UI.Colors.White)
        };
        root.Children.Add(new Image
        {
            Source = _pages[pageIndex],
            Stretch = Stretch.Uniform,
            Margin = new Thickness(
                description.ImageableRect.Left,
                description.ImageableRect.Top,
                Math.Max(0, description.PageSize.Width - description.ImageableRect.Right),
                Math.Max(0, description.PageSize.Height - description.ImageableRect.Bottom))
        });
        return root;
    }
}
