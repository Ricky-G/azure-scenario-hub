namespace AgtMaf;

/// <summary>
/// Small ANSI-colour helpers for a clean, readable demo trace. Colour can be
/// disabled by setting the environment variable <c>AGT_MAF_NO_COLOR=1</c>.
/// </summary>
public static class Display
{
    private static readonly bool NoColor =
        Environment.GetEnvironmentVariable("AGT_MAF_NO_COLOR") is { } v &&
        v is not ("" or "0" or "false" or "False");

    public static string Reset => NoColor ? "" : "\u001b[0m";
    public static string Bold => NoColor ? "" : "\u001b[1m";
    public static string Dim => NoColor ? "" : "\u001b[2m";
    public static string Red => NoColor ? "" : "\u001b[31m";
    public static string Green => NoColor ? "" : "\u001b[32m";
    public static string Yellow => NoColor ? "" : "\u001b[33m";
    public static string Blue => NoColor ? "" : "\u001b[34m";
    public static string Cyan => NoColor ? "" : "\u001b[36m";
    public static string Grey => NoColor ? "" : "\u001b[90m";

    private const int Width = 78;

    public static void Banner(string title, string? subtitle = null)
    {
        Console.WriteLine($"\n{Bold}{Blue}{new string('=', Width)}{Reset}");
        Console.WriteLine($"{Bold}{Blue}  {title}{Reset}");
        if (subtitle is not null)
        {
            Console.WriteLine($"{Grey}  {subtitle}{Reset}");
        }
        Console.WriteLine($"{Bold}{Blue}{new string('=', Width)}{Reset}");
    }

    public static void Section(string title)
    {
        var pad = Math.Max(0, Width - title.Length - 4);
        Console.WriteLine($"\n{Bold}{Cyan}-- {title} {new string('-', pad)}{Reset}");
    }

    public static void User(string text) => Console.WriteLine($"{Bold}[user]{Reset} {text}");

    public static void Intercept(string layer, string target) =>
        Console.WriteLine($"{Bold}{Cyan}AGT intercept{Reset} {Dim}[{layer}]{Reset} -> {Bold}{target}{Reset}");

    public static void Allowed(string reason) => Console.WriteLine($"{Green}   ALLOW{Reset} {Grey}{reason}{Reset}");

    public static void Denied(string reason) => Console.WriteLine($"{Red}   DENY{Reset}  {reason}");

    public static void Escalate(string reason) => Console.WriteLine($"{Yellow}   ESCALATE{Reset} {reason}");

    public static void Info(string label, string value) => Console.WriteLine($"{Grey}   {label}:{Reset} {value}");

    public static void AgentSays(string text) => Console.WriteLine($"{Bold}{Green}[agent]{Reset} {text}");

    public static void Note(string text) => Console.WriteLine($"{Grey}   {text}{Reset}");
}
