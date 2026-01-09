import KeyPathsExtensions
import KeyPathMapper

extension Resettable where Base: Collection {
	/// Creates a proxy for collection-based mutations
	public var collection: WritableKeyPathContainer<Base> {
		WritableKeyPathContainer(
			resettable: self,
			keyPath: \.self
		)
	}
}

extension Resettable.WritableKeyPathContainer where Value: Collection {
	@discardableResult
	public func swapAt<T>(
		_ idx1: Value.Index,
		_ idx2: Value.Index,
		operation: Resettable.OperationBehavior = .default
	) -> Resettable where Value == Array<T> {
		resettable._modify(
			operation: operation,
			keyPath,
			using: { $0.swapAt(idx1, idx2) },
			undo: { $0.swapAt(idx1, idx2) }
		)
	}

	@discardableResult
	public func remove<T>(
		at idx: Value.Index,
		operation: Resettable.OperationBehavior = .default
	) -> Resettable where Value == Array<T> {
		let valueSnapshot = resettable.wrappedValue[keyPath: keyPath][idx]
		return resettable._modify(
			operation: operation,
			keyPath,
			using: { $0.remove(at: idx) },
			undo: { $0.insert(valueSnapshot, at: idx) }
		)
	}

	@discardableResult
	public func insert<T>(
		_ element: Value.Element,
		at idx: Value.Index,
		operation: Resettable.OperationBehavior = .default
	) -> Resettable where Value == Array<T> {
		return resettable._modify(
			operation: operation,
			keyPath,
			using: { $0.insert(element, at: idx) },
			undo: { $0.remove(at: idx) }
		)
	}

	@discardableResult
	public func append<T>(
		_ element: Value.Element,
		operation: Resettable.OperationBehavior = .default
	) -> Resettable where Value == Array<T> {
		return resettable._modify(
			operation: operation,
			keyPath,
			using: { $0.append(element) },
			undo: { $0.removeLast() }
		)
	}
}
