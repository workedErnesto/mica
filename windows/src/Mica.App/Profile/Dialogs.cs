namespace Mica.App;

/// <summary>Questions and messages (macOS NSAlert sheets), drawn by the window's shell as a mica card: title, text,
/// optional fields or choices and buttons. One question per window is shown at a time, the rest wait in order.
/// Buttons keep their order: the first is the cancelling choice, the last the default one.</summary>
/// <summary>What a password question is about: the site, the account to save (empty: no user name) or the generated password.</summary>
public sealed record PasswordCard(string Origin, string? Account = null, string? Secret = null);

public static class Dialogs
{
    public sealed class Question
    {
        public int Id { get; } = Interlocked.Increment(ref next);
        public string Title { get; init; } = "";
        public string Text { get; init; } = "";
        public IReadOnlyList<string> Buttons { get; init; } = ["OK"];
        public IReadOnlyList<string>? Choices { get; init; }
        /// <summary>Text fields: label and whether it hides what is typed; their values come back with the answer.</summary>
        public IReadOnlyList<(string Label, string Value, bool Secret)>? Fields { get; init; }
        public bool Destructive { get; init; }
        /// <summary>A password question: the shell draws the site's icon with a key and the account or password on a plate.</summary>
        public PasswordCard? Password { get; init; }
        /// <summary>A page's dialog or permission question: the shell draws that site's icon instead of mica's.</summary>
        public string? Site { get; init; }
        internal TaskCompletionSource<(int Index, string[] Values)> Answer { get; } = new();
        static int next;
    }

    static BrowserModel? Owner(BrowserWindow? window) => (window ?? Store.Shared.Active?.Window ?? Store.Shared.Windows.LastOrDefault())?.Model;

    static async Task<(int Index, string[] Values)> Present(BrowserWindow? window, Question question)
    {
        if (Owner(window) is not { } owner) return (0, []);
        owner.Questions.Add(question);
        owner.Window?.Bring();
        owner.Touch();
        try { return await question.Answer.Task; }
        finally { owner.Questions.Remove(question); owner.Touch(); }
    }

    /// <summary>The shell answered: index of the button, 100 + index of a choice, field values in order.</summary>
    public static void Answer(BrowserModel owner, int id, int index, string[] values)
    {
        if (owner.Questions.FirstOrDefault(q => q.Id == id) is { } question) question.Answer.TrySetResult((index, values));
    }

    /// <summary>Closing the window cancels what it was asking.</summary>
    public static void CancelAll(BrowserModel owner)
    {
        foreach (var question in owner.Questions.ToList()) question.Answer.TrySetResult((0, []));
    }

    /// <summary>Returns the index of the chosen button, 0 when closed with Esc.</summary>
    public static async Task<int> Ask(BrowserWindow? window, string title, string detail, IReadOnlyList<string> buttons, bool destructive = false, PasswordCard? password = null, string? site = null) =>
        (await Present(window, new Question { Title = title, Text = detail, Buttons = buttons, Destructive = destructive, Password = password, Site = site })).Index;

    public static Task Show(BrowserWindow? window, string message) => Ask(window, "mica", message, ["OK"]);

    /// <summary>A prompt() of a page: the default text in one field. Null when cancelled.</summary>
    public static async Task<string?> Prompt(BrowserWindow? window, string title, string message, string defaultText, string? site = null)
    {
        var owner = Owner(window);
        var cancel = owner?.Text("отмена", "Отмена") ?? "Cancel";
        var (index, values) = await Present(window, new Question { Title = title, Text = message, Buttons = [cancel, "OK"], Fields = [("", defaultText, false)], Site = site });
        return index == 1 && values.Length > 0 ? values[0] : null;
    }

    /// <summary>HTTP authentication of a site: user name and password. Null when cancelled.</summary>
    public static async Task<(string User, string Password)?> Credentials(BrowserWindow? window, string title, string host, string userLabel, string passwordLabel, string ok, string cancel)
    {
        var (index, values) = await Present(window, new Question { Title = title, Text = host, Buttons = [cancel, ok], Fields = [(userLabel, "", false), (passwordLabel, "", true)] });
        return index == 1 && values.Length == 2 ? (values[0], values[1]) : null;
    }
}

public static class DialogChoices
{
    /// <summary>One of several options (an account to fill); -1 when cancelled.</summary>
    public static async Task<int> Choose(BrowserWindow? window, string title, string detail, IReadOnlyList<string> options, string ok, string cancel, PasswordCard? password = null)
    {
        var owner = window?.Model ?? Store.Shared.Active;
        if (owner is null) return -1;
        var question = new Dialogs.Question { Title = title, Text = detail, Buttons = [cancel], Choices = options, Password = password };
        owner.Questions.Add(question);
        owner.Touch();
        try
        {
            var (index, _) = await question.Answer.Task;
            return index >= 100 && index - 100 < options.Count ? index - 100 : -1;
        }
        finally { owner.Questions.Remove(question); owner.Touch(); }
    }
}
