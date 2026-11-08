using System.Numerics;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Automation.Provider;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using Mica.Core;
using Path = Microsoft.UI.Xaml.Shapes.Path;

namespace Mica.Design;

public enum ButtonKind { Primary, Secondary, Ghost, Destructive }

/// <summary>Base for mica's own controls: a real Control (enabled state, focus, automation) around a Grid.</summary>
public abstract partial class MicaControl : UserControl
{
    protected readonly Grid Root = new() { Background = Palette.Clear };
    protected MicaControl() { Content = Root; IsTabStop = true; UseSystemFocusVisuals = true; }
}

/// <summary>Glyph by SF Symbol name, drawn with Segoe Fluent Icons; the incognito mark is mica's own drawing.</summary>
public sealed partial class Glyph : Grid
{
    public const string Incognito = "mica.incognito";
    readonly FontIcon? icon;
    readonly Path? hat, glasses;
    public Glyph(string name, double size, Brush? brush = null)
    {
        IsHitTestVisible = false;
        if (name == Incognito)
        {
            var box = size * 1.25;
            Width = box; Height = box;
            var unit = box / 20;
            hat = new Path { Data = IncognitoHat(unit), Fill = brush ?? Palette.Ink.Brush() };
            glasses = new Path { Data = IncognitoGlasses(unit), Stroke = brush ?? Palette.Ink.Brush(), StrokeThickness = unit * 1.55, StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round };
            Children.Add(hat); Children.Add(glasses);
        }
        else
        {
            icon = new FontIcon { FontFamily = Fonts.Icons, Glyph = Glyphs.For(name), FontSize = size, Foreground = brush ?? Palette.Ink.Brush() };
            Children.Add(icon);
        }
    }
    public Brush Foreground
    {
        set { if (icon is not null) icon.Foreground = value; if (hat is not null) hat.Fill = value; if (glasses is not null) glasses.Stroke = value; }
    }
    public void SetSymbol(string name) { if (icon is not null) icon.Glyph = Glyphs.For(name); }

    static Geometry IncognitoHat(double u)
    {
        Windows.Foundation.Point P(double x, double y) => new(x * u, y * u);
        var crown = new PathFigure { StartPoint = P(5.2, 8.6), IsClosed = true, IsFilled = true };
        crown.Segments.Add(new LineSegment { Point = P(6.6, 3.6) });
        crown.Segments.Add(new QuadraticBezierSegment { Point1 = P(7.0, 2.4), Point2 = P(8.1, 2.7) });
        crown.Segments.Add(new QuadraticBezierSegment { Point1 = P(10.0, 3.6), Point2 = P(11.9, 2.7) });
        crown.Segments.Add(new QuadraticBezierSegment { Point1 = P(13.0, 2.4), Point2 = P(13.4, 3.6) });
        crown.Segments.Add(new LineSegment { Point = P(14.8, 8.6) });
        var geometry = new GeometryGroup();
        var path = new PathGeometry(); path.Figures.Add(crown);
        geometry.Children.Add(path);
        geometry.Children.Add(new RectangleGeometry { Rect = new Windows.Foundation.Rect(1.6 * u, 8.9 * u, 16.8 * u, 1.9 * u) });
        return geometry;
    }

    static Geometry IncognitoGlasses(double u)
    {
        var group = new GeometryGroup();
        group.Children.Add(new EllipseGeometry { Center = new Windows.Foundation.Point(5.3 * u, 15 * u), RadiusX = 2.7 * u, RadiusY = 2.4 * u });
        group.Children.Add(new EllipseGeometry { Center = new Windows.Foundation.Point(14.7 * u, 15 * u), RadiusX = 2.7 * u, RadiusY = 2.4 * u });
        var bridge = new PathFigure { StartPoint = new Windows.Foundation.Point(8 * u, 14.6 * u), IsFilled = false };
        bridge.Segments.Add(new QuadraticBezierSegment { Point1 = new Windows.Foundation.Point(10 * u, 13.4 * u), Point2 = new Windows.Foundation.Point(12 * u, 14.6 * u) });
        var path = new PathGeometry(); path.Figures.Add(bridge);
        group.Children.Add(path);
        return group;
    }
}

/// <summary>Filled rounded button: primary, secondary, ghost or destructive (macOS MButtonStyle).</summary>
public sealed partial class MButton : MicaControl
{
    readonly Border fill;
    readonly TextBlock label;
    readonly ButtonKind kind;
    readonly Interaction interaction;
    public event Action? Click;
    public MButton(string title, ButtonKind kind = ButtonKind.Secondary, bool compact = false, bool stretch = false, Action? click = null)
    {
        this.kind = kind;
        IsTabStop = true; UseSystemFocusVisuals = true;
        Height = compact ? 26 : 32;
        HorizontalAlignment = stretch ? HorizontalAlignment.Stretch : HorizontalAlignment.Left;
        fill = Ui.Rounded(compact ? Radius.Icon - 1 : Radius.Icon);
        label = Ui.Text(title, compact ? 12 : 13, null, Ui.Medium);
        label.HorizontalAlignment = HorizontalAlignment.Center;
        label.Margin = new Thickness(compact ? 10 : 14, 0, compact ? 10 : 14, 0);
        AutomationProperties.SetAccessibilityView(label, AccessibilityView.Raw);
        Root.Children.Add(fill); Root.Children.Add(label);
        Root.Background = Palette.Clear;
        interaction = new Interaction(this, Render, 0.965);
        interaction.Invoked += () => Click?.Invoke();
        if (click is not null) Click += click;
        AutomationProperties.SetName(this, title);
        IsEnabledChanged += (_, _) => { interaction.Enabled = IsEnabled; Render(); };
        Look.Changed += Render;
        Render();
    }
    public string Title { get => label.Text; set { label.Text = value; AutomationProperties.SetName(this, value); } }
    void Render()
    {
        bool hover = interaction.Hover, pressed = interaction.Pressed;
        label.Foreground = kind switch { ButtonKind.Primary => Look.OnPrimary, ButtonKind.Destructive => Palette.Danger.Brush(), _ => Palette.Ink.Brush() };
        fill.Background = kind switch
        {
            ButtonKind.Primary => pressed ? Look.PrimaryPressed : hover ? Look.PrimaryHover : Look.Primary,
            ButtonKind.Secondary => pressed ? Palette.SecondaryPressed.Brush() : hover ? Palette.SecondaryHover.Brush() : Palette.Secondary.Brush(),
            ButtonKind.Ghost => pressed ? Palette.Pressed.Brush() : hover ? Palette.Hover.Brush() : Palette.Clear,
            _ => new SolidColorBrush(Palette.WithAlpha(Palette.Danger.Resolve(), pressed ? 0.2 : hover ? 0.15 : 0.1)),
        };
        Opacity = IsEnabled ? 1 : 0.42;
    }
    internal void Invoke() { if (IsEnabled) Click?.Invoke(); }
    protected override AutomationPeer OnCreateAutomationPeer() => new MButtonPeer(this);
}

/// <summary>Exposes MButton as a button that screen readers and UI Automation can press.</summary>
public sealed partial class MButtonPeer(MButton owner) : FrameworkElementAutomationPeer(owner), IInvokeProvider
{
    protected override AutomationControlType GetAutomationControlTypeCore() => AutomationControlType.Button;
    protected override string GetClassNameCore() => nameof(MButton);
    protected override object GetPatternCore(PatternInterface pattern) => pattern == PatternInterface.Invoke ? this : base.GetPatternCore(pattern);
    public void Invoke() => owner.Invoke();
}

/// <summary>Square icon button with hover fill and press scale (macOS IconButton).</summary>
public sealed partial class IconButton : MicaControl
{
    readonly Border fill;
    Glyph glyph;
    readonly Interaction interaction;
    bool selected;
    string symbol;
    readonly double size;
    public event Action? Click;
    public IconButton(string symbol, string label, double size = 28, bool selected = false, Action? click = null)
    {
        this.symbol = symbol; this.size = size; this.selected = selected;
        Width = size; Height = size; IsTabStop = true; UseSystemFocusVisuals = true;
        Root.Background = Palette.Clear;
        fill = Ui.Rounded(Radius.Icon);
        glyph = new Glyph(symbol, size * 0.48) { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        Root.Children.Add(fill); Root.Children.Add(glyph);
        interaction = new Interaction(this, Render, 0.9);
        interaction.Invoked += () => Click?.Invoke();
        if (click is not null) Click += click;
        this.Tip(label);
        IsEnabledChanged += (_, _) => { interaction.Enabled = IsEnabled; Render(); };
        Render();
    }
    public bool Selected { get => selected; set { selected = value; Render(); } }
    public string Symbol
    {
        get => symbol;
        set
        {
            if (value == symbol) return;
            symbol = value;
            Root.Children.Remove(glyph);
            glyph = new Glyph(symbol, size * 0.48) { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
            Root.Children.Add(glyph); Render();
        }
    }
    public void SetLabel(string label) => this.Tip(label);
    void Render()
    {
        var on = interaction.Hover || selected;
        glyph.Foreground = !IsEnabled ? new SolidColorBrush(Palette.WithAlpha(Palette.Text3.Resolve(), 0.6)) : on ? Palette.Ink.Brush() : Palette.Text2.Brush();
        fill.Background = selected ? Palette.Pressed.Brush() : interaction.Hover ? Palette.Hover.Brush() : Palette.Clear;
    }
}

/// <summary>Capsule switch with a sliding knob that widens while pressed (macOS SwitchKnob).</summary>
public sealed partial class Switch : MicaControl
{
    readonly Border track, knob, overlay;
    readonly Interaction interaction;
    bool on;
    public event Action<bool>? Toggled;
    public Switch(bool on, string label)
    {
        this.on = on;
        Width = 36; Height = 20; IsTabStop = true; UseSystemFocusVisuals = true;
        track = Ui.Rounded(10);
        overlay = Ui.Rounded(10);
        knob = Ui.Rounded(8);
        knob.Width = 16; knob.Height = 16; knob.HorizontalAlignment = HorizontalAlignment.Left; knob.Margin = new Thickness(2);
        knob.Shadow = Shadows.Soft; knob.Translation = new Vector3(0, 0, 4);
        Root.Children.Add(track); Root.Children.Add(overlay); Root.Children.Add(knob);
        interaction = new Interaction(this, Render);
        interaction.Invoked += () => { IsOn = !this.on; Toggled?.Invoke(this.on); };
        AutomationProperties.SetName(this, label);
        IsEnabledChanged += (_, _) => { interaction.Enabled = IsEnabled; Render(); };
        Look.Changed += Render;
        Loaded += (_, _) => Render(animated: false);
    }
    public bool IsOn { get => on; set { on = value; Render(); } }
    void Render() => Render(true);
    void Render(bool animated)
    {
        var pressed = interaction.Pressed && !Motion.Reduced;
        track.Background = on ? Look.Primary : Palette.SwitchOff.Brush();
        overlay.Background = new SolidColorBrush(Palette.WithAlpha(Microsoft.UI.Colors.White, interaction.Hover && !on ? 0.06 : 0));
        knob.Background = on ? Look.OnPrimary : Palette.KnobOff.Brush();
        knob.Width = pressed ? 21 : 16;
        var travel = 36 - 4 - knob.Width;
        Motion.Translate(knob, new Vector3(on ? (float)travel : 0, 0, 4), Motion.Snappy, animated);
        Opacity = IsEnabled ? 1 : 0.45;
    }
}

/// <summary>Label on the left, switch on the right; a whole settings row (macOS MToggleStyle in RowInset).</summary>
public sealed partial class ToggleRow : Grid
{
    public readonly Switch Switch;
    public ToggleRow(string title, bool on, Action<bool> changed, bool divider = true, string? detail = null)
    {
        ColumnDefinitions.Add(Ui.Star()); ColumnDefinitions.Add(Ui.Auto());
        RowDefinitions.Add(Ui.RowAuto()); RowDefinitions.Add(Ui.RowAuto());
        var labels = Ui.V(2, Ui.Text(title, 13, wrap: true));
        if (detail is not null) labels.Children.Add(Ui.Text(detail, 11.5, Palette.Text3.Brush(), wrap: true));
        labels.Margin = new Thickness(14, 10, 12, 10);
        Switch = new Switch(on, title) { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 14, 0) };
        Switch.Toggled += changed;
        this.Column(labels, 0); this.Column(Switch, 1);
        if (divider) { var line = Ui.Hairline(); line.Margin = new Thickness(14, 0, 0, 0); Grid.SetColumnSpan(line, 2); this.Row(line, 1); }
    }
}

/// <summary>Segmented control with a sliding thumb (macOS Segmented with matchedGeometryEffect).</summary>
public sealed partial class Segmented<T> : MicaControl where T : notnull
{
    readonly List<(T Value, string Title)> options;
    readonly Border thumb;
    readonly Grid row;
    readonly List<(Border Hover, TextBlock Text, Interaction Interaction)> cells = [];
    T selection;
    public event Action<T>? Changed;
    public Segmented(T selection, IEnumerable<(T Value, string Title)> options, bool compact = false, double minWidth = 0, string label = "", IReadOnlyList<string>? symbols = null)
    {
        this.selection = selection; this.options = options.ToList();
        Root.Padding = new Thickness(2);
        Root.Background = Palette.Track.Brush();
        Root.CornerRadius = new CornerRadius(Radius.Track);
        MinWidth = minWidth;
        HorizontalAlignment = HorizontalAlignment.Left;
        thumb = Ui.Rounded(Radius.Thumb, Palette.Thumb.Brush());
        thumb.Shadow = Shadows.Soft; thumb.Translation = new Vector3(0, 0, 2);
        thumb.HorizontalAlignment = HorizontalAlignment.Left;
        row = new Grid { ColumnSpacing = 2 };
        Root.Children.Add(thumb); Root.Children.Add(row);
        for (var i = 0; i < this.options.Count; i++)
        {
            row.ColumnDefinitions.Add(Ui.Star());
            var cell = new Grid { Height = compact ? 22 : 26, Background = Palette.Clear, IsTabStop = true, UseSystemFocusVisuals = true };
            var hover = Ui.Rounded(Radius.Thumb);
            var text = Ui.Text(this.options[i].Title, compact ? 11.5 : 12.5);
            var content = Ui.H(6);
            if (symbols is not null && i < symbols.Count) content.Children.Add(new Glyph(symbols[i], compact ? 10 : 11, Palette.Text2.Brush()));
            content.Children.Add(text);
            content.HorizontalAlignment = HorizontalAlignment.Center;
            content.Margin = new Thickness(compact ? 8 : 10, 0, compact ? 8 : 10, 0);
            cell.Children.Add(hover); cell.Children.Add(content);
            var index = i;
            var interaction = new Interaction(cell, Render, 0.96);
            interaction.Invoked += () => { Selection = this.options[index].Value; Changed?.Invoke(this.selection); };
            AutomationProperties.SetName(cell, this.options[i].Title);
            cells.Add((hover, text, interaction));
            Grid.SetColumn(cell, i);
            row.Children.Add(cell);
        }
        AutomationProperties.SetName(this, label);
        row.SizeChanged += (_, _) => PlaceThumb(false);
        IsEnabledChanged += (_, _) => Opacity = IsEnabled ? 1 : 0.45;
        Render();
    }
    public T Selection { get => selection; set { selection = value; Render(); PlaceThumb(true); } }
    void Render()
    {
        for (var i = 0; i < cells.Count; i++)
        {
            var chosen = EqualityComparer<T>.Default.Equals(options[i].Value, selection);
            var (hover, text, interaction) = cells[i];
            text.Foreground = chosen || interaction.Hover ? Palette.Ink.Brush() : Palette.Text2.Brush();
            text.FontWeight = chosen ? Ui.Medium : Ui.Regular;
            hover.Background = !chosen && interaction.Hover ? Palette.Hover.Brush() : Palette.Clear;
        }
    }
    void PlaceThumb(bool animated)
    {
        var index = options.FindIndex(o => EqualityComparer<T>.Default.Equals(o.Value, selection));
        if (index < 0 || row.ActualWidth <= 0) { thumb.Opacity = 0; return; }
        thumb.Opacity = 1;
        var each = (row.ActualWidth - 2 * (options.Count - 1)) / options.Count;
        thumb.Width = each; thumb.Height = row.ActualHeight;
        Motion.Translate(thumb, new Vector3((float)(index * (each + 2)), 0, 2), Motion.Snappy, animated);
    }
}

/// <summary>Slider with a capsule track and a round knob that grows while dragged (macOS MSlider).</summary>
public sealed partial class MSlider : MicaControl
{
    readonly Border track, filled;
    readonly Ellipse knob;
    double value; readonly double min, max;
    bool dragging, hover;
    public event Action<double>? Changed;
    const double KnobSize = 16;
    public MSlider(double value, double min, double max, string label)
    {
        this.value = value; this.min = min; this.max = max;
        Height = 22; Root.Background = Palette.Clear; IsTabStop = true; UseSystemFocusVisuals = true;
        track = Ui.Rounded(2, Palette.Track.Brush()); track.Height = 4; track.VerticalAlignment = VerticalAlignment.Center;
        filled = Ui.Rounded(2, Look.Primary); filled.Height = 4; filled.HorizontalAlignment = HorizontalAlignment.Left; filled.VerticalAlignment = VerticalAlignment.Center;
        knob = new Ellipse { Width = KnobSize, Height = KnobSize, Fill = Palette.ThumbSolid.Brush(), Stroke = Palette.HairlineStrong.Brush(), StrokeThickness = 0.5, HorizontalAlignment = HorizontalAlignment.Left, VerticalAlignment = VerticalAlignment.Center, Shadow = Shadows.Soft, Translation = new Vector3(0, 0, 4) };
        Root.Children.Add(track); Root.Children.Add(filled); Root.Children.Add(knob);
        AutomationProperties.SetName(this, label);
        PointerEntered += (_, _) => { hover = true; Grow(); };
        PointerExited += (_, _) => { hover = false; Grow(); };
        PointerPressed += (_, e) => { if (!IsEnabled) return; dragging = true; CapturePointer(e.Pointer); Move(e.GetCurrentPoint(this).Position.X); Grow(); e.Handled = true; };
        PointerMoved += (_, e) => { if (dragging) Move(e.GetCurrentPoint(this).Position.X); };
        PointerReleased += (_, e) => { dragging = false; ReleasePointerCapture(e.Pointer); Grow(); };
        PointerCaptureLost += (_, _) => { dragging = false; Grow(); };
        KeyDown += (_, e) =>
        {
            var step = (this.max - this.min) / 20;
            if (e.Key is Windows.System.VirtualKey.Right or Windows.System.VirtualKey.Up) { Value = this.value + step; Changed?.Invoke(this.value); e.Handled = true; }
            if (e.Key is Windows.System.VirtualKey.Left or Windows.System.VirtualKey.Down) { Value = this.value - step; Changed?.Invoke(this.value); e.Handled = true; }
        };
        SizeChanged += (_, _) => Place();
        IsEnabledChanged += (_, _) => Opacity = IsEnabled ? 1 : 0.45;
    }
    public double Value { get => value; set { this.value = Math.Clamp(value, min, max); Place(); } }
    void Move(double x)
    {
        var travel = Math.Max(1, ActualWidth - KnobSize);
        Value = min + Math.Clamp((x - KnobSize / 2) / travel, 0, 1) * (max - min);
        Changed?.Invoke(value);
    }
    void Place()
    {
        var travel = Math.Max(1, ActualWidth - KnobSize);
        var fraction = (value - min) / (max - min);
        filled.Width = KnobSize / 2 + fraction * travel;
        knob.Margin = new Thickness(fraction * travel, 0, 0, 0);
    }
    void Grow() => Motion.Scale(knob, dragging ? 1.18 : hover ? 1.08 : 1, Motion.Press);
}

/// <summary>Text field with mica chrome: field fill, hairline that turns into a focus ring (macOS MTextField).</summary>
public sealed partial class MTextField : Grid
{
    public readonly TextBox Box;
    readonly Border chrome;
    readonly IconButton clear;
    public event Action? Submit;
    public event Action? Escape;
    public MTextField(string placeholder, string text = "", string? symbol = null, double height = 32)
    {
        Height = height;
        chrome = Ui.Rounded(Radius.Row, Palette.Field.Brush(), Palette.HairlineStrong.Brush(), 1);
        Children.Add(chrome);
        var row = new Grid { Margin = new Thickness(10, 0, 4, 0) };
        row.ColumnDefinitions.Add(Ui.Auto()); row.ColumnDefinitions.Add(Ui.Star()); row.ColumnDefinitions.Add(Ui.Auto());
        if (symbol is not null) row.Column(new Glyph(symbol, 12, Palette.Text3.Brush()) { Margin = new Thickness(0, 0, 8, 0), VerticalAlignment = VerticalAlignment.Center }, 0);
        Box = Bare(new TextBox { PlaceholderText = placeholder, Text = text, FontSize = 13 });
        row.Column(Box, 1);
        clear = new IconButton("xmark.circle.fill", "очистить", 22) { Visibility = text.Length > 0 ? Visibility.Visible : Visibility.Collapsed, VerticalAlignment = VerticalAlignment.Center };
        clear.Click += () => { Box.Text = ""; Box.Focus(FocusState.Programmatic); };
        row.Column(clear, 2);
        Children.Add(row);
        Box.TextChanged += (_, _) => clear.Visibility = Box.Text.Length > 0 ? Visibility.Visible : Visibility.Collapsed;
        Box.GotFocus += (_, _) => { chrome.BorderBrush = Look.Focus; chrome.BorderThickness = new Thickness(1.5); };
        Box.LostFocus += (_, _) => { chrome.BorderBrush = Palette.HairlineStrong.Brush(); chrome.BorderThickness = new Thickness(1); };
        Box.KeyDown += (_, e) =>
        {
            if (e.Key == Windows.System.VirtualKey.Enter) { Submit?.Invoke(); e.Handled = true; }
            if (e.Key == Windows.System.VirtualKey.Escape) { Escape?.Invoke(); e.Handled = true; }
        };
    }
    public string Text { get => Box.Text; set => Box.Text = value; }
    public void ClearLabel(string text) => clear.SetLabel(text);

    /// <summary>A TextBox without its own border, fill and focus underline, so mica's chrome around it is the only frame.</summary>
    public static TextBox Bare(TextBox box)
    {
        foreach (var key in new[] { "TextControlBackground", "TextControlBackgroundPointerOver", "TextControlBackgroundFocused", "TextControlBackgroundDisabled",
                                    "TextControlBorderBrush", "TextControlBorderBrushPointerOver", "TextControlBorderBrushFocused", "TextControlBorderBrushDisabled" })
            box.Resources[key] = Palette.Clear;
        box.Resources["TextControlForeground"] = Palette.Ink.Brush();
        box.Resources["TextControlForegroundFocused"] = Palette.Ink.Brush();
        box.Resources["TextControlForegroundPointerOver"] = Palette.Ink.Brush();
        box.Resources["TextControlPlaceholderForeground"] = Palette.Text3.Brush();
        box.Resources["TextControlPlaceholderForegroundFocused"] = Palette.Text3.Brush();
        box.Resources["TextControlPlaceholderForegroundPointerOver"] = Palette.Text3.Brush();
        box.Resources["TextControlSelectionHighlightColor"] = Look.Primary;
        box.Resources["TextControlButtonForeground"] = Palette.Text3.Brush();
        box.BorderThickness = new Thickness(0);
        box.Padding = new Thickness(0, 5, 0, 5);
        box.MinHeight = 0;
        box.Background = Palette.Clear;
        box.FontFamily = Fonts.Text;
        box.VerticalAlignment = VerticalAlignment.Center;
        return box;
    }
}

/// <summary>Grouped settings surface: title, rows with inset hairlines, footnote (macOS SettingsGroup).</summary>
public sealed partial class SettingsGroup : StackPanel
{
    public readonly StackPanel Rows = new();
    public SettingsGroup(string? title = null, string? footnote = null)
    {
        Spacing = Space.Small;
        if (title is not null) Children.Add(Ui.Text(title, 12, Palette.Text2.Brush(), Ui.Medium));
        Children.Add(Ui.Rounded(Radius.Panel - 4, Palette.Surface.Brush(), Palette.Hairline.Brush(), 1, Rows));
        if (footnote is not null) { var note = Ui.Text(footnote, 11.5, Palette.Text3.Brush(), wrap: true); note.LineHeight = 16; Children.Add(note); }
    }
    public SettingsGroup Add(UIElement row) { Rows.Children.Add(row); return this; }
}

/// <summary>Title and optional detail on the left, a control on the right; wraps under the title when narrow.</summary>
public sealed partial class SettingRow : Grid
{
    public SettingRow(string title, UIElement? trailing = null, string? detail = null, bool divider = true, string? info = null)
    {
        ColumnDefinitions.Add(Ui.Star()); ColumnDefinitions.Add(Ui.Auto());
        RowDefinitions.Add(Ui.RowAuto()); RowDefinitions.Add(Ui.RowAuto());
        var titleRow = Ui.H(5, Ui.Text(title, 13, wrap: true));
        if (info is not null) titleRow.Children.Add(new InfoTip(title, info));
        var labels = Ui.V(2, titleRow);
        if (detail is not null) labels.Children.Add(Ui.Text(detail, 11.5, Palette.Text3.Brush(), wrap: true));
        labels.Margin = new Thickness(14, 10, 12, 10);
        labels.VerticalAlignment = VerticalAlignment.Center;
        this.Column(labels, 0);
        if (trailing is FrameworkElement fe) { fe.VerticalAlignment = VerticalAlignment.Center; fe.Margin = new Thickness(0, 8, 14, 8); this.Column(fe, 1); }
        if (divider) { var line = Ui.Hairline(); line.Margin = new Thickness(14, 0, 0, 0); Grid.SetColumnSpan(line, 2); this.Row(line, 1); }
    }
}

/// <summary>A full-width row of arbitrary content with the standard inset and an optional divider.</summary>
public sealed partial class RowInset : StackPanel
{
    public RowInset(UIElement content, bool divider = true)
    {
        if (content is FrameworkElement fe) fe.Margin = new Thickness(14, 10, 14, 10);
        Children.Add(content);
        if (divider) { var line = Ui.Hairline(); line.Margin = new Thickness(14, 0, 0, 0); Children.Add(line); }
    }
}

/// <summary>Question mark next to a setting title; the explanation opens in a flyout.</summary>
public sealed partial class InfoTip : Grid
{
    public InfoTip(string title, string text)
    {
        var button = new IconButton("questionmark.circle", title, 18);
        var flyout = new Flyout { Content = Ui.V(Space.Small, Ui.Text(title, 13, null, Ui.Medium), Ui.Text(text, 12, Palette.Text2.Brush(), wrap: true)).Size(300) };
        button.Click += () => flyout.ShowAt(button);
        Children.Add(button);
    }
}

/// <summary>Quiet full-width row that navigates somewhere (macOS LinkRow).</summary>
public sealed partial class LinkRow : Grid
{
    public LinkRow(string title, string symbol, Action action)
    {
        Height = 32;
        var fill = Ui.Rounded(Radius.Row, new SolidColorBrush(Palette.WithAlpha(Palette.Track.Resolve(), Palette.Track.Resolve().A / 255.0 * 0.6)));
        var text = Ui.Text(title, 12.5, Palette.Text2.Brush());
        var row = new Grid { Margin = new Thickness(10, 0, 10, 0) };
        row.ColumnDefinitions.Add(Ui.Star()); row.ColumnDefinitions.Add(Ui.Auto());
        row.Column(text, 0); row.Column(new Glyph(symbol, 10.5, Palette.Text3.Brush()) { VerticalAlignment = VerticalAlignment.Center }, 1);
        Children.Add(fill); Children.Add(row);
        Background = Palette.Clear; IsTabStop = true;
        Interaction? interaction = null;
        interaction = new Interaction(this, () => { text.Foreground = interaction!.Hover ? Palette.Ink.Brush() : Palette.Text2.Brush(); fill.Background = interaction.Hover ? Palette.Hover.Brush() : new SolidColorBrush(Palette.WithAlpha(Palette.Track.Resolve(), Palette.Track.Resolve().A / 255.0 * 0.6)); }, 0.98);
        interaction.Invoked += action;
        AutomationProperties.SetName(this, title);
    }
}

/// <summary>Navigation row in settings with a selection plate (macOS NavItem).</summary>
public sealed partial class NavItem : Grid
{
    readonly Border plate;
    readonly TextBlock? title;
    readonly Glyph glyph;
    readonly Interaction interaction;
    bool selected;
    public NavItem(string text, string symbol, bool selected, bool compact, Action action)
    {
        this.selected = selected;
        Height = 32; Background = Palette.Clear; IsTabStop = true;
        plate = Ui.Rounded(Radius.Row);
        glyph = new Glyph(symbol, 12) { Width = 18 };
        var row = Ui.H(10, glyph);
        if (!compact) { title = Ui.Text(text, 13); row.Children.Add(title); }
        row.Margin = new Thickness(10, 0, 10, 0);
        Children.Add(plate); Children.Add(row);
        interaction = new Interaction(this, Render, 0.98);
        interaction.Invoked += action;
        this.Tip(text);
        Render();
    }
    public bool Selected { get => selected; set { selected = value; Render(); } }
    void Render()
    {
        var on = selected || interaction.Hover;
        glyph.Foreground = on ? Palette.Ink.Brush() : Palette.Text2.Brush();
        if (title is not null) { title.Foreground = on ? Palette.Ink.Brush() : Palette.Text2.Brush(); title.FontWeight = selected ? Ui.Medium : Ui.Regular; }
        plate.Background = selected ? Palette.Selected.Brush() : interaction.Hover ? Palette.Hover.Brush() : Palette.Clear;
        plate.Shadow = selected ? Shadows.Soft : null;
        plate.Translation = new Vector3(0, 0, selected ? 2 : 0);
    }
}

/// <summary>Site letter shown until a favicon is known. <c>plain</c> drops the track plate for tiles that draw their
/// own; <c>tint</c> defaults to Text2.</summary>
public sealed partial class Monogram : Grid
{
    public Monogram(string? host, double size = 16, bool plain = false, Brush? tint = null)
    {
        Width = size; Height = size; IsHitTestVisible = false;
        var bare = (host ?? "").ToLowerInvariant();
        if (bare.StartsWith("www.", StringComparison.Ordinal)) bare = bare[4..];
        var letter = bare.Length > 0 ? char.ToUpperInvariant(bare[0]).ToString() : "";
        var brush = tint ?? Palette.Text2.Brush();
        if (!plain) Children.Add(Ui.Rounded(size * 0.3, Palette.Track.Brush()));
        if (letter.Length == 0) Children.Add(new Glyph("globe", size * (plain ? 0.66 : 0.6), brush) { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center });
        else { var t = Ui.Text(letter, size * (plain ? 0.68 : 0.58), brush, Ui.Semibold); t.HorizontalAlignment = HorizontalAlignment.Center; t.VerticalAlignment = VerticalAlignment.Center; t.TextTrimming = TextTrimming.None; Children.Add(t); }
        AutomationProperties.SetAccessibilityView(this, AccessibilityView.Raw);
    }
}

/// <summary>Progress ring driven by load progress events, never a perpetual animation.</summary>
public sealed partial class ProgressRing : Grid
{
    readonly Path arc;
    readonly double size;
    public ProgressRing(double size = 16)
    {
        this.size = size; Width = size; Height = size; IsHitTestVisible = false;
        Children.Add(new Ellipse { Width = size - 2, Height = size - 2, Stroke = Palette.Track.Brush(), StrokeThickness = 2 });
        arc = new Path { Stroke = Look.Accent is null ? Palette.Ink.Brush() : Look.Primary, StrokeThickness = 2, StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round };
        Children.Add(arc);
    }
    public void SetProgress(double value)
    {
        var p = Math.Clamp(Math.Max(0.06, value), 0, 0.999);
        var r = (size - 4) / 2; var c = size / 2;
        var angle = p * 2 * Math.PI - Math.PI / 2;
        var figure = new PathFigure { StartPoint = new Windows.Foundation.Point(c, c - r), IsFilled = false };
        figure.Segments.Add(new ArcSegment { Point = new Windows.Foundation.Point(c + r * Math.Cos(angle), c + r * Math.Sin(angle)), Size = new Windows.Foundation.Size(r, r), IsLargeArc = p > 0.5, SweepDirection = SweepDirection.Clockwise });
        var geometry = new PathGeometry(); geometry.Figures.Add(figure);
        arc.Data = geometry;
    }
}

public static class KeyHint
{
    public static Border Make(string keys) => new()
    {
        Child = Ui.Text(keys, 11, Palette.Text3.Brush(), Ui.Medium),
        Padding = new Thickness(6, 0, 6, 0), Height = 18, CornerRadius = new CornerRadius(5),
        BorderBrush = Palette.HairlineStrong.Brush(), BorderThickness = new Thickness(1),
    };
}

public sealed partial class EmptyState : StackPanel
{
    public EmptyState(string symbol, string text)
    {
        Spacing = Space.Normal; HorizontalAlignment = HorizontalAlignment.Center; VerticalAlignment = VerticalAlignment.Center;
        var badge = Ui.Rounded(11, Palette.Track.Brush(), child: new Glyph(symbol, 16, Palette.Text3.Brush()) { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center });
        badge.Width = 40; badge.Height = 40; badge.HorizontalAlignment = HorizontalAlignment.Center;
        var label = Ui.Text(text, 12.5, Palette.Text3.Brush(), wrap: true); label.TextAlignment = TextAlignment.Center;
        Children.Add(badge); Children.Add(label);
    }
}
