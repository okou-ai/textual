import SwiftUI
import Synchronization

// Styling belongs to the code block rather than to a transient hosting view.
struct HighlightedTextFragment: View {
  @Environment(\.textEnvironment) private var textEnvironment
  @Environment(\.codeHighlightCache) private var cache
  @State private var highlighted: (StructuredText.CodeHighlightCache.Key, AttributedString)?

  private let content: AttributedSubstring
  private let languageHint: String?
  private let theme: StructuredText.HighlighterTheme

  init(
    _ content: AttributedSubstring, languageHint: String?, theme: StructuredText.HighlighterTheme
  ) {
    self.content = content
    self.languageHint = languageHint
    self.theme = theme
  }

  var body: some View {
    let key = StructuredText.CodeHighlightCache.Key(
      content: AttributedString(content), language: languageHint, theme: theme,
      environment: textEnvironment)
    let rendered =
      highlighted.flatMap { $0.0 == key ? $0.1 : nil }
      ?? cache?.cached(key) ?? key.content
    TextFragment(rendered)
      .foregroundStyle(theme.foregroundColor)
      .task(id: key) {
        guard cache?.cached(key) == nil else { return }
        let value: AttributedString
        if let cache {
          value = await cache.highlight(key)
        } else {
          value = await StructuredText.CodeHighlightCache.render(key)
        }
        guard !Task.isCancelled else { return }
        highlighted = (key, value)
      }
  }
}

extension StructuredText {
  /// Reuses code styling across views that share a document or workspace lifecycle.
  public actor CodeHighlightCache {
    public init() {}

    struct Key: Hashable, Sendable {
      let content: AttributedString
      let language: String?
      let theme: StructuredText.HighlighterTheme
      let environment: TextEnvironmentValues
    }

    private struct Storage: Sendable {
      var values: [Key: AttributedString] = [:]
      var order: [Key] = []
    }
    private let storage = Mutex(Storage())
    private var pending: [Key: Task<AttributedString, Never>] = [:]

    nonisolated func cached(_ key: Key) -> AttributedString? {
      storage.withLock { $0.values[key] }
    }

    func highlight(_ key: Key) async -> AttributedString {
      if let cached = cached(key) { return cached }
      if let existing = pending[key] { return await existing.value }
      let task = Task { await Self.render(key) }
      pending[key] = task
      let result = await task.value
      pending.removeValue(forKey: key)
      if key.content.characters.prefix(16_385).count <= 16_384 {
        storage.withLock { storage in
          storage.values[key] = result
          storage.order.append(key)
          if storage.order.count > 32 {
            storage.values.removeValue(forKey: storage.order.removeFirst())
          }
        }
      }
      return result
    }

    fileprivate static func render(_ key: Key) async -> AttributedString {
      let code = String(key.content.characters)
      let tokens: [CodeToken]
      if let tokenizer = CodeTokenizer.shared, let language = key.language {
        tokens = await tokenizer.tokenize(code: code, language: language)
      } else {
        tokens = [CodeToken(content: code, type: .plain)]
      }

      var attributes = AttributeContainer()
      // Pasteboard formatters use the original intent to reconstruct the code block.
      attributes.presentationIntent = key.content.presentationIntent
      ForegroundColorProperty(key.theme.foregroundColor)
        .apply(in: &attributes, environment: key.environment)
      var highlighted = AttributedString()
      for token in tokens {
        var content = AttributedString(token.content)
        var tokenAttributes = attributes
        key.theme.tokenProperties[token.type]?.apply(
          in: &tokenAttributes, environment: key.environment)
        content.mergeAttributes(tokenAttributes)
        highlighted.append(content)
      }
      return highlighted
    }
  }
}

extension EnvironmentValues {
  @Entry var codeHighlightCache: StructuredText.CodeHighlightCache? = nil
}

extension TextualNamespace where Base: View {
  /// Shares prepared syntax highlighting between code blocks in this view subtree.
  public func codeHighlightCache(_ cache: StructuredText.CodeHighlightCache) -> some View {
    base.environment(\.codeHighlightCache, cache)
  }
}
