import SwiftUI

extension StructuredText {
  /// Geometry for an overflow table with plain or strongly emphasized inline text.
  public struct PreparedTableLayout: Equatable, Sendable {
    public struct Cell: Equatable, Sendable {
      public let content: AttributedSubstring
      public let row: Int
      public let column: Int
      public let frame: CGRect

      public init(content: AttributedSubstring, row: Int, column: Int, frame: CGRect) {
        self.content = content
        self.row = row
        self.column = column
        self.frame = frame
      }
    }

    public let size: CGSize
    public let contentWidth: CGFloat
    public let cells: [Cell]
    public let dividers: [CGRect]

    public init(size: CGSize, contentWidth: CGFloat, cells: [Cell], dividers: [CGRect]) {
      self.size = size
      self.contentWidth = contentWidth
      self.cells = cells
      self.dividers = dividers
    }
  }

  /// A top-level Markdown table and its cells, in reading order.
  public struct TableSource: Sendable {
    public let content: AttributedString
    public let columnCount: Int
    public let rows: [[AttributedSubstring]]
  }

  nonisolated public static func tables(in document: AttributedString) -> [TableSource] {
    document.blockRuns().compactMap { block in
      guard let intent = block.intent, case .table(let columns) = intent.kind else { return nil }
      let content = document[block.range]
      let rows = content.blockRuns(parent: intent).map { row in
        let rowContent = content[row.range]
        return rowContent.blockRuns(parent: row.intent).map { rowContent[$0.range] }
      }
      return TableSource(content: AttributedString(content), columnCount: columns.count, rows: rows)
    }
  }
}

extension TextualNamespace where Base: View {
  /// Supplies prepared geometry for matching tables when using the overflow table style.
  public func preparedTables(
    _ layouts: [AttributedString: StructuredText.PreparedTableLayout]
  ) -> some View {
    base.environment(\.preparedTables, layouts)
  }
}

extension EnvironmentValues {
  @Entry var preparedTables: [AttributedString: StructuredText.PreparedTableLayout] = [:]
}
