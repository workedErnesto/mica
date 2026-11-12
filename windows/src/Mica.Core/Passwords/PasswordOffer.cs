namespace Mica.Core;

public enum PasswordOfferKind { Fill, Generate }

/// <summary>What mica offers beside a focused sign-in field of the page (macOS PasswordOffer): saved accounts of
/// exactly this origin, or a strong password for a field that asks for a new one. Anchored to the field, not a dialog.</summary>
public sealed record PasswordOffer(PasswordOfferKind Kind, IReadOnlyList<SavedLogin> Logins)
{
    /// <summary>Rows the panel shows before it scrolls.</summary>
    public const int VisibleRows = 4;

    /// <summary><paramref name="isNew"/>: the field has autocomplete="new-password". <paramref name="maxLength"/>: the
    /// field's maxLength, -1 without one.</summary>
    public static PasswordOffer? Decide(Vault vault, string origin, bool isNew, int maxLength, bool offerPasswords, bool fillPasswords)
    {
        if (isNew)
        {
            // A generated password on a site excluded from saving would never be offered for saving and would be lost.
            if (!offerPasswords || vault.Never.Contains(origin) || !(maxLength < 0 || maxLength >= 8)) return null;
            return new PasswordOffer(PasswordOfferKind.Generate, []);
        }
        if (!fillPasswords) return null;
        var matches = vault.Matches(origin);
        return matches.Count == 0 ? null : new PasswordOffer(PasswordOfferKind.Fill, matches);
    }

    public bool SameAs(PasswordOffer? other) =>
        other is not null && other.Kind == Kind && other.Logins.Select(l => l.Id).SequenceEqual(Logins.Select(l => l.Id));
}

public enum PasswordOfferEvent { Focus, Click, Input, Blur, Dismiss, Accept, Leave }

/// <summary>Whether the offer beside a field is showing (macOS PasswordOfferSession). Each focus of a sign-in field gets
/// a new number from the page script. "Not now" (Esc, a click elsewhere) and typing hide the offer only for that focus:
/// it comes back when the field is focused again, clicked again, or the page changes. Nothing of this is stored; the one
/// lasting choice is "never for this site" (Vault.Never).</summary>
public sealed class PasswordOfferSession
{
    public int? Field { get; private set; }
    public bool Dismissed { get; private set; }
    public bool Visible => Field is not null && !Dismissed;

    public void Apply(PasswordOfferEvent e, int id = 0)
    {
        switch (e)
        {
            case PasswordOfferEvent.Focus: if (Field != id) { Field = id; Dismissed = false; } break;
            case PasswordOfferEvent.Click: Field = id; Dismissed = false; break;
            case PasswordOfferEvent.Input: if (Field == id) Dismissed = true; break;
            case PasswordOfferEvent.Blur: if (Field == id) { Field = null; Dismissed = false; } break;
            case PasswordOfferEvent.Dismiss: case PasswordOfferEvent.Accept: Dismissed = true; break;
            case PasswordOfferEvent.Leave: Field = null; Dismissed = false; break;
        }
    }
}

public readonly record struct OfferRect(double X, double Y, double Width, double Height)
{
    public double Right => X + Width;
    public double Bottom => Y + Height;
}

public enum OfferEdge { Above, Below }

/// <summary>Where the offer goes over the page (macOS PasswordOfferPlacement). Rectangles have a top-left origin in the
/// page view's DIPs.</summary>
public readonly record struct PasswordOfferPlacement(OfferRect Frame, OfferEdge Edge)
{
    /// <summary>A rectangle the page script measured in CSS pixels of the visual viewport, in the view's DIPs.
    /// <paramref name="innerWidth"/> is the page's window.innerWidth, so zoom is accounted for.</summary>
    public static OfferRect ViewRect(OfferRect css, double innerWidth, double viewWidth)
    {
        if (innerWidth <= 0 || viewWidth <= 0) return css;
        var k = viewWidth / innerWidth;
        return new OfferRect(css.X * k, css.Y * k, css.Width * k, css.Height * k);
    }

    /// <summary>Above the field when it fits, otherwise below, otherwise on the side with more room, clamped into the
    /// page with <paramref name="margin"/>. Leading edges line up. Null when the field is scrolled out of the page.</summary>
    public static PasswordOfferPlacement? Place(OfferRect field, double boundsWidth, double boundsHeight, double panelWidth, double panelHeight, double gap, double margin)
    {
        if (!(field.Bottom > 0 && field.Y < boundsHeight && field.Right > 0 && field.X < boundsWidth)) return null;
        var width = Math.Min(panelWidth, boundsWidth - 2 * margin);
        if (width <= 0 || panelHeight <= 0) return null;
        var x = Math.Max(margin, Math.Min(field.X, boundsWidth - margin - width));
        var above = field.Y - gap - panelHeight;
        var below = field.Bottom + gap;
        if (above >= margin) return new(new OfferRect(x, above, width, panelHeight), OfferEdge.Above);
        if (below + panelHeight <= boundsHeight - margin) return new(new OfferRect(x, below, width, panelHeight), OfferEdge.Below);
        var roomAbove = field.Y - gap - margin;
        var roomBelow = boundsHeight - margin - below;
        var edge = roomAbove > roomBelow ? OfferEdge.Above : OfferEdge.Below;
        var lowest = Math.Max(margin, boundsHeight - margin - panelHeight);
        var y = Math.Max(margin, Math.Min(edge == OfferEdge.Above ? above : below, lowest));
        return new(new OfferRect(x, y, width, panelHeight), edge);
    }
}
