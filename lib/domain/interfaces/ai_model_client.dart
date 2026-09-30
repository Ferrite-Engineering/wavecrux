// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:meta/meta.dart';

/// Role of a single message in an [AiRequest] conversation.
///
/// Mirrors the small, provider-neutral role set every chat-completion API
/// agrees on. Provider-specific roles (e.g. OpenAI's `function`) are mapped
/// onto these by the concrete client in the Pro overlay.
enum AiRole {
  /// System / developer instructions that frame the assistant's behavior.
  system,

  /// A message authored by the end user.
  user,

  /// A message authored by the model.
  assistant,

  /// The result of a tool/function call fed back to the model. Pair with
  /// [AiMessage.toolCallId] so the model can correlate it to its request.
  tool,
}

/// One turn in a conversation sent to (or streamed back from) an
/// [AiModelClient].
///
/// Pure data: no provider-specific fields. The concrete client adapts this to
/// whatever wire shape its endpoint expects.
@immutable
class AiMessage {
  const AiMessage({
    required this.role,
    required this.content,
    this.toolCalls = const [],
    this.toolCallId,
  });

  /// Convenience constructor for a plain user-authored message.
  const AiMessage.user(this.content)
    : role = AiRole.user,
      toolCalls = const [],
      toolCallId = null;

  /// Convenience constructor for a system/developer instruction message.
  const AiMessage.system(this.content)
    : role = AiRole.system,
      toolCalls = const [],
      toolCallId = null;

  /// The role of the author of this message.
  final AiRole role;

  /// The textual content of the message. May be empty for an assistant turn
  /// that consists solely of [toolCalls].
  final String content;

  /// Tool/function invocations requested by the model on an assistant turn.
  /// Empty for user/system/tool messages.
  final List<AiToolCall> toolCalls;

  /// For [AiRole.tool] messages: the id of the [AiToolCall] this message is
  /// the result of. `null` for every other role.
  final String? toolCallId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AiMessage &&
          role == other.role &&
          content == other.content &&
          toolCallId == other.toolCallId &&
          _listEquals(toolCalls, other.toolCalls);

  @override
  int get hashCode => Object.hash(role, content, toolCallId, toolCalls.length);

  @override
  String toString() =>
      'AiMessage(${role.name}, ${content.length} chars, '
      '${toolCalls.length} toolCalls)';
}

/// Declares a tool the model may call: a stable [name], a human-readable
/// [description], and a JSON-Schema [parametersSchema] describing its
/// arguments.
///
/// The schema is a plain JSON-natural map (the same object you would serialize
/// into a provider's `tools`/`functions` field). Keeping it as `Map` rather
/// than a typed builder lets open-core declare the viewer-navigation tools and
/// the Pro overlay declare analysis tools without a shared schema DSL.
@immutable
class AiToolSpec {
  const AiToolSpec({
    required this.name,
    required this.description,
    this.parametersSchema = const {},
  });

  /// Unique tool name (the key the model uses to invoke it).
  final String name;

  /// One-line description shown to the model so it can decide when to call.
  final String description;

  /// JSON-Schema object describing the tool's parameters.
  final Map<String, Object?> parametersSchema;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AiToolSpec &&
          name == other.name &&
          description == other.description;

  @override
  int get hashCode => Object.hash(name, description);

  @override
  String toString() => 'AiToolSpec($name)';
}

/// A tool/function invocation requested by the model.
@immutable
class AiToolCall {
  const AiToolCall({
    required this.id,
    required this.name,
    this.arguments = const {},
  });

  /// Provider-assigned id used to correlate this call with its
  /// [AiMessage.toolCallId] result.
  final String id;

  /// Name of the tool the model wants to invoke (matches an [AiToolSpec.name]).
  final String name;

  /// Decoded argument map for the call.
  final Map<String, Object?> arguments;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AiToolCall && id == other.id && name == other.name;

  @override
  int get hashCode => Object.hash(id, name);

  @override
  String toString() => 'AiToolCall($name, id: $id)';
}

/// A structured request to an [AiModelClient]: the conversation so far plus the
/// set of tools the model is allowed to call this turn.
@immutable
class AiRequest {
  const AiRequest({
    required this.messages,
    this.tools = const [],
  });

  /// Conversation history, oldest first.
  final List<AiMessage> messages;

  /// Tools the model may invoke this turn. Empty for a non-agentic
  /// single-shot call (e.g. open-core "Explain Selection").
  final List<AiToolSpec> tools;

  @override
  String toString() =>
      'AiRequest(${messages.length} messages, ${tools.length} tools)';
}

/// Why an [AiModelClient] could not produce a response. Returned as a typed
/// [AiClientUnavailable] stream event — never thrown — so callers branch on a
/// value instead of catching exceptions.
enum AiUnavailableReason {
  /// No provider/endpoint/key is configured. The open-core [AiModelClient]
  /// default always reports this.
  notConfigured,

  /// The configured endpoint could not be reached.
  networkError,

  /// The endpoint returned an error response.
  providerError,

  /// The request was cancelled before completion.
  cancelled,
}

/// One event in the response stream from [AiModelClient.send].
///
/// Sealed so callers can `switch` exhaustively over the variants.
@immutable
sealed class AiStreamEvent {
  const AiStreamEvent();
}

/// An incremental chunk of assistant text.
final class AiTextDelta extends AiStreamEvent {
  const AiTextDelta(this.text);

  /// The text fragment to append to the assistant's response.
  final String text;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is AiTextDelta && text == other.text;

  @override
  int get hashCode => text.hashCode;

  @override
  String toString() => 'AiTextDelta(${text.length} chars)';
}

/// The model has requested a tool invocation.
final class AiToolCallRequested extends AiStreamEvent {
  const AiToolCallRequested(this.call);

  /// The requested call. The caller invokes the matching tool and feeds the
  /// result back as an [AiRole.tool] [AiMessage] on the next [AiRequest].
  final AiToolCall call;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AiToolCallRequested && call == other.call;

  @override
  int get hashCode => call.hashCode;

  @override
  String toString() => 'AiToolCallRequested(${call.name})';
}

/// The response completed normally.
final class AiResponseCompleted extends AiStreamEvent {
  const AiResponseCompleted({this.finishReason});

  /// Optional provider-supplied finish reason (`stop`, `tool_calls`, …).
  final String? finishReason;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AiResponseCompleted && finishReason == other.finishReason;

  @override
  int get hashCode => finishReason.hashCode;

  @override
  String toString() => 'AiResponseCompleted($finishReason)';
}

/// The client could not produce a response. Carries a typed [reason] and an
/// optional human-readable [detail]. This is the terminal event the no-op
/// default emits.
final class AiClientUnavailable extends AiStreamEvent {
  const AiClientUnavailable(this.reason, {this.detail});

  /// Why the client is unavailable.
  final AiUnavailableReason reason;

  /// Optional detail for display (already-localized message, error text, …).
  final String? detail;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AiClientUnavailable &&
          reason == other.reason &&
          detail == other.detail;

  @override
  int get hashCode => Object.hash(reason, detail);

  @override
  String toString() => 'AiClientUnavailable(${reason.name}, $detail)';
}

/// Open-core extension point: a bring-your-own-key model client.
///
/// Abstracts "send a structured request, stream back text + tool-call
/// invocations" over an arbitrary endpoint. Open-core ships
/// [`NoopAiModelClient`](../../services/ai/noop_ai_model_client.dart) as the
/// default `aiModelClientProvider` value; it reports
/// [AiUnavailableReason.notConfigured] as a typed event rather than throwing.
/// The closed-source Pro overlay overrides the provider with a
/// concrete multi-provider client (Anthropic / OpenAI / Google / local
/// Ollama).
///
/// Implementations must never throw from [send] for an expected failure
/// (missing key, network down, provider error) — they surface it as a terminal
/// [AiClientUnavailable] event so the UI can branch on a value.
abstract class AiModelClient {
  /// Whether a provider/endpoint/key is configured. When `false`, [send]
  /// yields a single [AiClientUnavailable] with
  /// [AiUnavailableReason.notConfigured].
  bool get isConfigured;

  /// Send [request] and stream back the response as a sequence of
  /// [AiStreamEvent]s. The stream completes after a terminal event
  /// ([AiResponseCompleted] or [AiClientUnavailable]).
  Stream<AiStreamEvent> send(AiRequest request);
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
