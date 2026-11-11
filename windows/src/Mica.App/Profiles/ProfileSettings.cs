using System.Numerics;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Mica.Core;
using Mica.Design;

namespace Mica.App.Settings;

/// <summary>Profiles as a gallery of cards and the editor of the chosen one: name, icon, background and glyph colour
/// (macOS ProfileSettings). The look itself is edited in the profile's window, in the space, appearance and start page
/// sections.</summary>
public sealed partial class ProfileSettings : StackPanel
{
    readonly BrowserModel browser;
    string? lastEditor;
    /// <summary>Typing a name saves it at once, but the page is rebuilt only when the field loses focus.</summary>
    bool typing;

    public ProfileSettings(BrowserModel browser)
    {
        this.browser = browser;
        Spacing = Space.Section;
        this.Bind(h => browser.Store.ProfilesChanged += h, h => browser.Store.ProfilesChanged -= h, Render);
    }

    Store store => browser.Store;
    Profile Editing => store.Profile(browser.EditingProfile ?? browser.ProfileId);

    void Render()
    {
        if (typing) return;
        Children.Clear();
        var editing = Editing;
        var cards = new VariableSizedWrapGrid { Orientation = Orientation.Horizontal, ItemWidth = 152, ItemHeight = 132 };
        foreach (var profile in store.Profiles.ToList()) cards.Children.Add(Card(profile, profile.Id == editing.Id));
        if (store.Profiles.Count < Core.Profiles.Limit) cards.Children.Add(NewCard());
        var note = Ui.Text(browser.Text("пароли, cookie, история, закладки, загрузки и расширения общие для всех профилей. профиль меняет начальную страницу, расположение вкладок и кнопок, тему, цвета, язык и регистр текста, обращение и закреплённые вкладки. в истории видно, в каком профиле открыта страница.", "Пароли, cookie, история, закладки, загрузки и расширения общие для всех профилей. Профиль меняет начальную страницу, расположение вкладок и кнопок, тему, цвета, язык и регистр текста, обращение и закреплённые вкладки. В истории видно, в каком профиле открыта страница."), 11.5, Palette.Text3.Brush(), wrap: true);
        Children.Add(Ui.V(Space.Small, cards, note));
        var opening = new Segmented<ProfileOpening>(store.Preferences.ProfileOpening, [(ProfileOpening.Ask, browser.Text("спрашивать", "Спрашивать")), (ProfileOpening.Here, browser.Text("в этом окне", "В этом окне")), (ProfileOpening.NewWindow, browser.Text("в новом окне", "В новом окне"))], minWidth: 340, label: browser.Text("профиль из меню открывать", "Профиль из меню открывать"));
        opening.Changed += v => store.Change(p => p.ProfileOpening = v);
        Children.Add(new SettingsGroup(footnote: browser.Text("в этом окне закреплённые вкладки сменятся закреплёнными вкладками профиля. в новом окне откроется окно профиля или выйдет вперёд уже открытое. в списке переходов панели задач и меню «…» профиль всегда открывается своим окном.", "В этом окне закреплённые вкладки сменятся закреплёнными вкладками профиля. В новом окне откроется окно профиля или выйдет вперёд уже открытое. В списке переходов панели задач и меню «…» профиль всегда открывается своим окном."))
            .Add(new SettingRow(browser.Text("профиль из меню открывать", "Профиль из меню открывать"), opening, divider: false)));
        var editor = Editor(editing);
        Children.Add(editor);
        // Only a different profile animates in; renaming or recolouring keeps the editor in place.
        var key = editing.Id.ToString();
        if (lastEditor is not null && lastEditor != key) Motion.Appear(editor, Motion.Edge.Bottom);
        lastEditor = key;
    }

    string Status(Profile profile) =>
        browser.ProfileId == profile.Id ? browser.Text("это окно", "Это окно")
        : store.Windows.Any(w => w.Model.ProfileId == profile.Id && !w.Model.PrivateMode) ? browser.Text("открыт в другом окне", "Открыт в другом окне")
        : profile.IsStandard ? browser.Text("основной", "Основной") : browser.Text("не открыт", "Не открыт");

    /// <summary>One profile in the gallery: its mark, name and status; the chosen card carries the focus ring.</summary>
    FrameworkElement Card(Profile profile, bool selected)
    {
        var mark = new ProfileMark(profile, 44) { HorizontalAlignment = HorizontalAlignment.Center };
        var name = Ui.Text(browser.ProfileName(profile), 12.5, Palette.Ink.Brush(), selected ? Ui.Medium : Ui.Regular); name.HorizontalAlignment = HorizontalAlignment.Center;
        var status = Ui.Text(Status(profile), 11, Palette.Text3.Brush()); status.HorizontalAlignment = HorizontalAlignment.Center;
        var content = Ui.V(Space.Small, mark, Ui.V(1, name, status));
        content.Padding = new Thickness(10, 16, 10, 12);
        var card = Ui.Rounded(Radius.Panel - 4, Palette.Surface.Brush(), selected ? Look.Primary : Palette.Hairline.Brush(), selected ? 2 : 1, content);
        card.Margin = new Thickness(0, 0, Space.Small, Space.Small);
        var more = new MenuButton(browser.Text("действия", "Действия"), () => Actions(profile), size: 22) { HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(0, 6, Space.Small + 6, 0), Opacity = 0 };
        var host = new Grid { Background = Palette.Clear, IsTabStop = true };
        host.Children.Add(card); host.Children.Add(more);
        Interaction? interaction = null;
        interaction = new Interaction(host, () =>
        {
            card.Background = interaction!.Hover && !selected ? Palette.Hover.Brush() : Palette.Surface.Brush();
            Motion.Scale(mark, interaction.Hover && !Motion.Reduced ? 1.06 : 1, Motion.Snappy);
            Motion.Fade(more, interaction.Hover ? 1 : 0);
        }, 0.97, card);
        var id = profile.Id;
        interaction.Invoked += () => { browser.EditingProfile = id; Render(); };
        host.ContextMenu(() => Actions(profile));
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(host, browser.ProfileName(profile) + ", " + Status(profile));
        return host;
    }

    FrameworkElement NewCard()
    {
        var plus = Ui.Rounded(44 * 0.3, null, Palette.HairlineStrong.Brush(), 1.5, new Glyph("plus", 16, Palette.Text2.Brush()) { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center });
        plus.Width = 44; plus.Height = 44; plus.HorizontalAlignment = HorizontalAlignment.Center;
        var title = Ui.Text(browser.Text("новый профиль", "Новый профиль"), 12.5, Palette.Text2.Brush()); title.HorizontalAlignment = HorizontalAlignment.Center;
        var hint = Ui.Text(browser.Text("вид этого окна", "Вид этого окна"), 11, Palette.Text3.Brush()); hint.HorizontalAlignment = HorizontalAlignment.Center;
        var content = Ui.V(Space.Small, plus, Ui.V(1, title, hint));
        content.Padding = new Thickness(10, 16, 10, 12);
        var card = Ui.Rounded(Radius.Panel - 4, Palette.Clear, Palette.HairlineStrong.Brush(), 1, content);
        card.Margin = new Thickness(0, 0, Space.Small, Space.Small);
        Interaction? interaction = null;
        interaction = new Interaction(card, () => { card.Background = interaction!.Hover ? Palette.Hover.Brush() : Palette.Clear; title.Foreground = interaction.Hover ? Palette.Ink.Brush() : Palette.Text2.Brush(); }, 0.97);
        interaction.Invoked += () => { browser.EditingProfile = store.AddProfile(browser.ProfileId).Id; Render(); };
        card.IsTabStop = true;
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(card, browser.Text("новый профиль", "Новый профиль"));
        return card;
    }

    IEnumerable<MenuEntry> Actions(Profile profile)
    {
        var id = profile.Id;
        yield return MenuEntry.Item(browser.Text("открыть в новом окне", "Открыть в новом окне"), () => store.OpenProfile(id, newWindow: true), "macwindow.badge.plus");
        yield return MenuEntry.Item(browser.Text("открыть в этом окне", "Открыть в этом окне"), () => browser.SwitchProfile(id), "macwindow", enabled: browser.ProfileId != id);
        yield return MenuEntry.Separator;
        yield return MenuEntry.Item(browser.Text("удалить профиль…", "Удалить профиль…"), () => _ = Remove(profile), "trash", enabled: !profile.IsStandard, destructive: true);
    }

    async Task Remove(Profile profile)
    {
        var answer = await Dialogs.Ask(browser.Window, browser.Text("удалить профиль ", "Удалить профиль ") + browser.Quoted(browser.ProfileName(profile)) + "?", browser.Text("его окна перейдут в обычный профиль, закреплённые вкладки профиля закроются. пароли, история и закладки останутся.", "Его окна перейдут в обычный профиль, закреплённые вкладки профиля закроются. Пароли, история и закладки останутся."), [browser.Text("отмена", "Отмена"), browser.Text("удалить", "Удалить")]);
        if (answer != 1) return;
        if (browser.EditingProfile == profile.Id) browser.EditingProfile = null;
        store.RemoveProfile(profile.Id);
    }

    UIElement Editor(Profile profile)
    {
        var id = profile.Id;
        // Hero: a large mark on a wash of the profile's own colour, the name field and what can be done with it.
        var mark = new ProfileMark(profile, 72) { VerticalAlignment = VerticalAlignment.Center };
        var name = new MTextField(profile.IsStandard ? browser.ProfileName(Core.Profile.Standard()) : browser.Text("название профиля", "Название профиля"), profile.Name, height: 36) { MaxWidth = 300, HorizontalAlignment = HorizontalAlignment.Left };
        // Another profile keeps its last name while the field is empty; the standard one falls back to its default.
        name.Box.TextChanged += (_, _) => { typing = true; store.ChangeProfile(id, p => p.Name = name.Text); typing = false; };
        name.Box.LostFocus += (_, _) => Render();
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(name, browser.Text("название профиля", "Название профиля"));
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, Spacing = Space.Small };
        if (profile.Id != browser.ProfileId)
        {
            var switchHere = new MButton(browser.Text("переключить это окно", "Переключить это окно"), ButtonKind.Primary, compact: true);
            switchHere.Click += () => browser.SwitchProfile(id);
            buttons.Children.Add(switchHere);
        }
        else
        {
            var here = Ui.H(5, new Glyph("checkmark", 11, Palette.Text2.Brush()) { VerticalAlignment = VerticalAlignment.Center }, Ui.Text(browser.Text("это окно", "Это окно"), 12, Palette.Text2.Brush(), Ui.Medium));
            here.VerticalAlignment = VerticalAlignment.Center;
            var chip = Ui.Rounded(Radius.Icon - 1, new SolidColorBrush(Palette.WithAlpha(Palette.Surface.Resolve(), 0.7)), null, 0, here);
            chip.Padding = new Thickness(10, 0, 10, 0); chip.Height = 26;
            buttons.Children.Add(chip);
        }
        var newWindow = new MButton(browser.Text("открыть в новом окне", "Открыть в новом окне"), ButtonKind.Secondary, compact: true);
        newWindow.Click += () => store.OpenProfile(id, newWindow: true);
        buttons.Children.Add(newWindow);
        if (!profile.IsStandard)
        {
            var remove = new IconButton("trash", browser.Text("удалить профиль…", "Удалить профиль…"), 26);
            remove.Click += () => _ = Remove(profile);
            buttons.Children.Add(remove);
        }
        var heroLine = new Grid { ColumnSpacing = 18, Padding = new Thickness(18) };
        heroLine.ColumnDefinitions.Add(Ui.Auto()); heroLine.ColumnDefinitions.Add(Ui.Star());
        heroLine.Column(mark, 0);
        var fields = Ui.V(Space.Small, name, buttons); fields.VerticalAlignment = VerticalAlignment.Center;
        heroLine.Column(fields, 1);
        var hero = new Grid();
        hero.Children.Add(Ui.Rounded(Radius.Panel - 4, Palette.Surface.Brush()));
        hero.Children.Add(Ui.Rounded(Radius.Panel - 4, new SolidColorBrush(Palette.WithAlpha(Hex.ToColor(profile.Background), 0.1)), Palette.Hairline.Brush(), 1, heroLine));

        // Mark: icon, background, glyph colour.
        var footnote = profile.Id == browser.ProfileId
            ? browser.Text("раскладка, оформление и начальная страница этого окна сохраняются в этот профиль.", "Раскладка, оформление и начальная страница этого окна сохраняются в этот профиль.")
            : browser.Text("раскладку, оформление и начальную страницу профиля настраивают в его окне.", "Раскладку, оформление и начальную страницу профиля настраивают в его окне.");
        var group = new SettingsGroup(browser.Text("значок", "Значок"), footnote);
        var icons = new VariableSizedWrapGrid { Orientation = Orientation.Horizontal, ItemWidth = 42, ItemHeight = 42 };
        var index = 0;
        foreach (var icon in ProfileCatalog.Icons)
        {
            var i = icon;
            var selected = profile.Icon == icon;
            var glyph = new ProfileMark(icon, profile.Background, 30, profile.Glyph);
            var tile = Ui.Rounded(12, Palette.Clear, selected ? Look.Primary : Palette.Clear, 2, glyph);
            tile.Padding = new Thickness(3); tile.Width = 40; tile.Height = 40; tile.IsTabStop = true;
            Interaction? interaction = null;
            interaction = new Interaction(tile, () => { if (!selected) tile.Background = interaction!.Hover ? Palette.Hover.Brush() : Palette.Clear; Motion.Scale(glyph, interaction!.Hover && !Motion.Reduced ? 1.08 : 1, Motion.Snappy); }, 0.9);
            interaction.Invoked += () => store.ChangeProfile(id, p => p.Icon = i);
            Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(tile, browser.Text("иконка ", "Иконка ") + (++index));
            icons.Children.Add(tile);
        }
        group.Add(Ui.V(Space.Small, Ui.Text(browser.Text("иконка", "Иконка"), 13), icons).Margin(14, 14, 14, 14)).Add(Ui.Hairline().Margin(14, 0, 0, 0));
        var swatches = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 2 };
        foreach (var hex in ProfileCatalog.Backgrounds)
        {
            var h = hex;
            swatches.Children.Add(new ColorDot(hex, profile.Background == hex, 24, () => store.ChangeProfile(id, p => p.Background = h)));
        }
        swatches.Children.Add(new ColorWell(() => store.Profile(id).Background, ProfileCatalog.Backgrounds, browser.Text("другой цвет", "Другой цвет"), 24, hex => store.ChangeProfile(id, p => p.Background = hex)));
        group.Add(new SettingRow(browser.Text("фон", "Фон"), swatches));
        var glyphs = new Segmented<ProfileGlyph>(profile.Glyph, [(ProfileGlyph.Auto, browser.Text("авто", "Авто")), (ProfileGlyph.Light, browser.Text("белый", "Белый")), (ProfileGlyph.Dark, browser.Text("чёрный", "Чёрный"))], minWidth: 240, label: browser.Text("цвет значка", "Цвет значка"));
        glyphs.Changed += v => store.ChangeProfile(id, p => p.Glyph = v);
        group.Add(new SettingRow(browser.Text("цвет значка", "Цвет значка"), glyphs, browser.Text("авто берёт читаемый на фоне", "Авто берёт читаемый на фоне"), divider: false));
        return Ui.V(Space.Section, hero, group);
    }
}
