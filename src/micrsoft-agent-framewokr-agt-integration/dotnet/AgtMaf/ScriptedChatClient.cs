using System.Runtime.CompilerServices;
using Microsoft.Extensions.AI;

namespace AgtMaf;

/// <summary>A scripted step where the model asks to call <paramref name="Name"/> with <paramref name="Arguments"/>.</summary>
public sealed record ToolCallStep(string Name, Dictionary<string, object?> Arguments);

/// <summary>
/// A deterministic, offline Microsoft Agent Framework chat client for reproducible demos.
///
/// The demos must run identically for every developer, with no API keys and no network —
/// while still exercising the real MAF agent pipeline so that function middleware genuinely
/// fires on tool calls. This client maps a prompt to either a scripted tool call (returns a
/// <see cref="FunctionCallContent"/>) or a direct text reply; when the conversation already
/// carries a tool result it surfaces that result as the assistant's final answer.
///
/// Swap this for an OpenAI / Azure OpenAI / Foundry <see cref="IChatClient"/> to run the very
/// same governed agent against a live model — the governance layer does not change.
/// </summary>
public sealed class ScriptedChatClient(
    IReadOnlyDictionary<string, ToolCallStep> toolPlans,
    IReadOnlyDictionary<string, string> directResponses) : IChatClient
{
    public Task<ChatResponse> GetResponseAsync(
        IEnumerable<ChatMessage> messages, ChatOptions? options = null, CancellationToken cancellationToken = default)
    {
        var transcript = messages.ToList();

        // If the last message carries a tool result, surface it as the assistant's final answer.
        var toolResult = transcript.LastOrDefault()?.Contents.OfType<FunctionResultContent>().LastOrDefault();
        if (toolResult is not null)
        {
            var resultText = toolResult.Result?.ToString() ?? "Tool completed with no output.";
            return Task.FromResult(new ChatResponse(new ChatMessage(ChatRole.Assistant, resultText)));
        }

        var prompt = transcript.LastOrDefault(m => m.Role == ChatRole.User)?.Text ?? string.Empty;

        // A scripted tool call -> emit a FunctionCallContent so the function middleware fires.
        if (toolPlans.TryGetValue(prompt, out var plan))
        {
            var callId = Guid.NewGuid().ToString("N");
            var message = new ChatMessage(
                ChatRole.Assistant,
                [new FunctionCallContent(callId, plan.Name, plan.Arguments)]);
            return Task.FromResult(new ChatResponse(message));
        }

        // A scripted direct text reply.
        var text = directResponses.TryGetValue(prompt, out var t)
            ? t
            : "I can help within the scenario's governed operating boundaries.";
        return Task.FromResult(new ChatResponse(new ChatMessage(ChatRole.Assistant, text)));
    }

    public async IAsyncEnumerable<ChatResponseUpdate> GetStreamingResponseAsync(
        IEnumerable<ChatMessage> messages, ChatOptions? options = null,
        [EnumeratorCancellation] CancellationToken cancellationToken = default)
    {
        var response = await GetResponseAsync(messages, options, cancellationToken).ConfigureAwait(false);
        foreach (var update in response.ToChatResponseUpdates())
        {
            yield return update;
        }
    }

    public object? GetService(Type serviceType, object? serviceKey = null) =>
        serviceType.IsInstanceOfType(this) ? this : null;

    public void Dispose() { }
}
