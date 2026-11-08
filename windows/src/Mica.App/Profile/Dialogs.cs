using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Mica.Design;

namespace Mica.App;

/// <summary>Questions and messages (macOS NSAlert sheets). One dialog per window at a time; buttons keep their order:
/// the first is the cancelling choice, the last the default one.</summary>
public static class Dialogs
{
    static readonly SemaphoreSlim Gate = new(1, 1);

    static ContentDialog Make(BrowserWindow? window, string title, UIElement content)
    {
        var root = (window ?? Store.Shared.Windows.LastOrDefault())?.Content.XamlRoot;
        var dialog = new ContentDialog
        {
            Title = Ui.Text(title, 15, null, Ui.Semibold, wrap: true),
            Content = content, XamlRoot = root,
            RequestedTheme = Palette.ElementTheme,
            Background = Palette.Canvas.Brush(),
            CornerRadius = new CornerRadius(Radius.Modal),
        };
        return dialog;
    }

    /// <summary>Returns the index of the chosen button, 0 when closed with Esc.</summary>
    public static async Task<int> Ask(BrowserWindow? window, string title, string detail, IReadOnlyList<string> buttons)
    {
        var text = Ui.Text(detail, 13, Palette.Text2.Brush(), wrap: true);
        text.IsTextSelectionEnabled = true;
        UIElement content = detail.Length > 1600 ? new ScrollViewer { Content = text, MaxHeight = 280 } : text;
        await Gate.WaitAsync();
        try
        {
            var dialog = Make(window, title, content);
            if (dialog.XamlRoot is null) return 0;
            switch (buttons.Count)
            {
                case 1: dialog.CloseButtonText = buttons[0]; dialog.DefaultButton = ContentDialogButton.Close; break;
                case 2: dialog.CloseButtonText = buttons[0]; dialog.PrimaryButtonText = buttons[1]; dialog.DefaultButton = ContentDialogButton.Primary; break;
                default: dialog.CloseButtonText = buttons[0]; dialog.SecondaryButtonText = buttons[1]; dialog.PrimaryButtonText = buttons[2]; dialog.DefaultButton = ContentDialogButton.Primary; break;
            }
            var result = await dialog.ShowAsync();
            return result switch
            {
                ContentDialogResult.Primary => buttons.Count == 2 ? 1 : 2,
                ContentDialogResult.Secondary => 1,
                _ => 0,
            };
        }
        finally { Gate.Release(); }
    }

    /// <summary>Like Ask, with custom content in place of the text.</summary>
    public static async Task<int> AskWith(BrowserWindow? window, string title, UIElement content, IReadOnlyList<string> buttons)
    {
        await Gate.WaitAsync();
        try
        {
            var dialog = Make(window, title, content);
            if (dialog.XamlRoot is null) return 0;
            dialog.CloseButtonText = buttons[0];
            if (buttons.Count > 2) { dialog.SecondaryButtonText = buttons[1]; dialog.PrimaryButtonText = buttons[2]; } else if (buttons.Count == 2) dialog.PrimaryButtonText = buttons[1];
            dialog.DefaultButton = buttons.Count > 1 ? ContentDialogButton.Primary : ContentDialogButton.Close;
            var result = await dialog.ShowAsync();
            return result switch { ContentDialogResult.Primary => buttons.Count == 2 ? 1 : 2, ContentDialogResult.Secondary => 1, _ => 0 };
        }
        finally { Gate.Release(); }
    }

    public static async Task<string?> Prompt(BrowserWindow? window, string title, string message, string defaultText)
    {
        var field = new MTextField("", defaultText);
        var content = Ui.V(Space.Normal, Ui.Text(message, 13, Palette.Text2.Brush(), wrap: true), field);
        await Gate.WaitAsync();
        try
        {
            var dialog = Make(window, title, content);
            if (dialog.XamlRoot is null) return null;
            dialog.PrimaryButtonText = "OK"; dialog.CloseButtonText = Store.Shared.Text("отмена", "Отмена"); dialog.DefaultButton = ContentDialogButton.Primary;
            return await dialog.ShowAsync() == ContentDialogResult.Primary ? field.Text : null;
        }
        finally { Gate.Release(); }
    }

    public static async Task<(string User, string Password)?> Credentials(BrowserWindow? window, string title, string host, string userLabel, string passwordLabel, string ok, string cancel)
    {
        var user = new MTextField(userLabel);
        var secret = new PasswordBox { PlaceholderText = passwordLabel };
        var content = Ui.V(Space.Normal, Ui.Text(host, 13, Palette.Text2.Brush()), user, secret);
        await Gate.WaitAsync();
        try
        {
            var dialog = Make(window, title, content);
            if (dialog.XamlRoot is null) return null;
            dialog.PrimaryButtonText = ok; dialog.CloseButtonText = cancel; dialog.DefaultButton = ContentDialogButton.Primary;
            return await dialog.ShowAsync() == ContentDialogResult.Primary ? (user.Text, secret.Password) : null;
        }
        finally { Gate.Release(); }
    }

    /// <summary>Message without a choice: problems and results (macOS alert with OK).</summary>
    public static Task Show(BrowserWindow? window, string message) => Ask(window, "mica", message, ["OK"]);
}

public static class DialogChoices
{
    /// <summary>A question with a list to choose from (macOS alert with a pop-up button); returns the index or -1.</summary>
    public static async Task<int> Choose(BrowserWindow? window, string title, string detail, IReadOnlyList<string> options, string ok, string cancel)
    {
        var box = new Microsoft.UI.Xaml.Controls.ComboBox { ItemsSource = options.ToList(), SelectedIndex = 0, MinWidth = 280 };
        var content = Mica.Design.Ui.V(Mica.Design.Space.Normal, Mica.Design.Ui.Text(detail, 13, Mica.Design.Palette.Text2.Brush(), wrap: true), box);
        var answer = await Dialogs.AskWith(window, title, content, [cancel, ok]);
        return answer == 1 ? box.SelectedIndex : -1;
    }
}
