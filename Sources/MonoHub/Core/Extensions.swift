import SwiftUI

nonisolated extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

nonisolated extension Array {
    func moving(from source: Int, to destination: Int) -> [Element] {
        guard indices.contains(source), indices.contains(destination), source != destination else { return self }
        var result = self
        let item = result.remove(at: source)
        result.insert(item, at: destination)
        return result
    }
}

nonisolated extension Array where Element: Equatable {
    func moving(_ element: Element, onto target: Element) -> [Element] {
        guard element != target,
              let source = firstIndex(of: element),
              let destination = firstIndex(of: target) else { return self }
        var reordered = self
        reordered.remove(at: source)
        reordered.insert(element, at: destination)
        return reordered
    }
}

extension Binding where Value == CGFloat {
    var doubleValue: Binding<Double> {
        Binding<Double>(
            get: { Double(wrappedValue) },
            set: { wrappedValue = CGFloat($0) }
        )
    }
}

extension Binding {
    func contains<Element: Hashable>(_ element: Element) -> Binding<Bool> where Value == Set<Element> {
        Binding<Bool>(
            get: { wrappedValue.contains(element) },
            set: { isIncluded in
                if isIncluded {
                    wrappedValue.insert(element)
                } else {
                    wrappedValue.remove(element)
                }
            }
        )
    }
}
