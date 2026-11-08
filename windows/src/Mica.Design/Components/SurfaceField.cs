using System.Numerics;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Mica.Design;

/// <summary>Text field with the start page search field look at field size (macOS MTextField prominent): surface fill,
/// hairline that strengthens on focus and a soft shadow that grows with it, glyph in text2, placeholder in text3.
/// For the main input of a small form standing on the canvas.</summary>
public sealed partial class SurfaceField : Grid
{
    public readonly TextBox Box;
    readonly Border chrome;
    readonly IconButton clear;
    public event Action? Submit;
    public SurfaceField(string placeholder, string text = "", string? symbol = null)
    {
        Height = 36;
        chrome = Ui.Rounded(Radius.Row, Palette.Surface.Brush(), Palette.Hairline.Brush(), 1);
        chrome.Shadow = Shadows.Soft; chrome.Translation = new Vector3(0, 0, 4);
        Children.Add(chrome);
        var row = new Grid { Margin = new Thickness(12, 0, 4, 0) };
        row.ColumnDefinitions.Add(Ui.Auto()); row.ColumnDefinitions.Add(Ui.Star()); row.ColumnDefinitions.Add(Ui.Auto());
        if (symbol is not null) row.Column(new Glyph(symbol, 12, Palette.Text2.Brush()) { Margin = new Thickness(0, 0, 8, 0), VerticalAlignment = VerticalAlignment.Center }, 0);
        Box = MTextField.Bare(new TextBox { PlaceholderText = placeholder, Text = text, FontSize = 13.5 });
        row.Column(Box, 1);
        clear = new IconButton("xmark.circle.fill", "очистить", 22) { Visibility = text.Length > 0 ? Visibility.Visible : Visibility.Collapsed, VerticalAlignment = VerticalAlignment.Center };
        clear.Click += () => { Box.Text = ""; Box.Focus(FocusState.Programmatic); };
        row.Column(clear, 2);
        Children.Add(row);
        Box.TextChanged += (_, _) => clear.Visibility = Box.Text.Length > 0 ? Visibility.Visible : Visibility.Collapsed;
        Box.GotFocus += (_, _) => { chrome.BorderBrush = Palette.HairlineStrong.Brush(); Motion.Translate(chrome, new Vector3(0, 0, 10), Motion.Snappy); };
        Box.LostFocus += (_, _) => { chrome.BorderBrush = Palette.Hairline.Brush(); Motion.Translate(chrome, new Vector3(0, 0, 4), Motion.Snappy); };
        Box.KeyDown += (_, e) => { if (e.Key == Windows.System.VirtualKey.Enter) { Submit?.Invoke(); e.Handled = true; } };
    }
    public string Text { get => Box.Text; set => Box.Text = value; }
    public void ClearLabel(string text) => clear.SetLabel(text);
}
