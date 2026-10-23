import AppKit
import Defaults
import Fuse

class Search {
  enum Mode: String, CaseIterable, Identifiable, CustomStringConvertible, Defaults.Serializable {
    case exact
    case fuzzy
    case regexp
    case mixed

    var id: Self { self }

    var description: String {
      switch self {
      case .exact:
        return NSLocalizedString("Exact", tableName: "GeneralSettings", comment: "")
      case .fuzzy:
        return NSLocalizedString("Fuzzy", tableName: "GeneralSettings", comment: "")
      case .regexp:
        return NSLocalizedString("Regex", tableName: "GeneralSettings", comment: "")
      case .mixed:
        return NSLocalizedString("Mixed", tableName: "GeneralSettings", comment: "")
      }
    }
  }

  struct SearchResult: Equatable {
    var score: Double?
    var object: Searchable
    var ranges: [Range<String.Index>] = []
  }

  typealias Searchable = HistoryItemDecorator

  private let fuse = Fuse(threshold: 0.7) // threshold found by trial-and-error
  private let fuzzySearchLimit = 5_000

  func search(string: String, within: [Searchable]) -> [SearchResult] {
    guard !string.isEmpty else {
      return within.map { SearchResult(object: $0) }
    }

    let results: [SearchResult]
    switch Defaults[.searchMode] {
    case .mixed:
      results = mixedSearch(string: string, within: within)
    case .regexp:
      results = simpleSearch(string: string, within: within, options: .regularExpression)
    case .fuzzy:
      results = fuzzySearch(string: string, within: within)
    default:
      results = simpleSearch(string: string, within: within, options: .caseInsensitive)
    }

    return prefixMatchesFirst(results)
  }

  // Stable partition: items whose match starts at the beginning of the text
  // (ignoring leading whitespace) go first, preserving the original order otherwise.
  private func prefixMatchesFirst(_ results: [SearchResult]) -> [SearchResult] {
    var prefixMatches: [SearchResult] = []
    var otherMatches: [SearchResult] = []
    for result in results {
      if isPrefixMatch(result) {
        prefixMatches.append(result)
      } else {
        otherMatches.append(result)
      }
    }
    return prefixMatches + otherMatches
  }

  private func isPrefixMatch(_ result: SearchResult) -> Bool {
    guard let start = result.ranges.map(\.lowerBound).min() else {
      return false
    }

    let title = result.object.title
    guard start >= title.startIndex, start <= title.endIndex else {
      return false
    }

    // "·", "⏎" and "⇥" are how whitespace is shown when special symbols are enabled.
    return title[title.startIndex..<start].allSatisfy { $0.isWhitespace || "·⏎⇥".contains($0) }
  }

  private func fuzzySearch(string: String, within: [Searchable]) -> [SearchResult] {
    let pattern = fuse.createPattern(from: string)
    let searchResults: [SearchResult] = within.compactMap { item in
      fuzzySearch(for: pattern, in: item.title, of: item)
    }
    let sortedResults = searchResults.sorted(by: { ($0.score ?? 0) < ($1.score ?? 0) })
    return sortedResults
  }

  private func fuzzySearch(
    for pattern: Fuse.Pattern?,
    in searchString: String,
    of item: Searchable
  ) -> SearchResult? {
    var searchString = searchString
    if searchString.count > fuzzySearchLimit {
      // shortcut to avoid slow search
      let stopIndex = searchString.index(searchString.startIndex, offsetBy: fuzzySearchLimit)
      searchString = "\(searchString[...stopIndex])"
    }

    if let fuzzyResult = fuse.search(pattern, in: searchString) {
      return SearchResult(
        score: fuzzyResult.score,
        object: item,
        ranges: fuzzyResult.ranges.map {
          let startIndex = searchString.startIndex
          let lowerBound = searchString.index(startIndex, offsetBy: $0.lowerBound)
          let upperBound = searchString.index(startIndex, offsetBy: $0.upperBound + 1)

          return lowerBound..<upperBound
        }
      )
    } else {
      return nil
    }
  }

  private func simpleSearch(
    string: String,
    within: [Searchable],
    options: NSString.CompareOptions
  ) -> [SearchResult] {
    return within.compactMap { simpleSearch(for: string, in: $0.title, of: $0, options: options) }
  }

  private func simpleSearch(
    for string: String,
    in searchString: String,
    of item: Searchable,
    options: NSString.CompareOptions
  ) -> SearchResult? {
    if let range = searchString.range(of: string, options: options, range: nil, locale: nil) {
      return SearchResult(object: item, ranges: [range])
    } else {
      return nil
    }
  }

  private func mixedSearch(string: String, within: [Searchable]) -> [SearchResult] {
    var results = simpleSearch(string: string, within: within, options: .caseInsensitive)
    guard results.isEmpty else {
      return results
    }

    results = simpleSearch(string: string, within: within, options: .regularExpression)
    guard results.isEmpty else {
      return results
    }

    results = fuzzySearch(string: string, within: within)
    guard results.isEmpty else {
      return results
    }

    return []
  }
}
