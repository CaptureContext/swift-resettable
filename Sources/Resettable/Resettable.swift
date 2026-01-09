import KeyPathsExtensions
@_spi(Internals) import SwiftMarkerProtocols

extension Resettable {
	public enum OperationBehavior {
		case `default`
		case amend
		case insert
		case inject
	}
}

/// Undo/Redo manager class
///
/// Records changes performed on Base
/// - Note: Any recorded changes will clear redo buffer
@propertyWrapper
@dynamicMemberLookup
public class Resettable<Base> {
	@available(*, deprecated, renamed: "Base")
	public typealias Object = Base

	public convenience init(wrappedValue: Base) {
		self.init(wrappedValue)
	}

	public init(_ base: Base) {
		self.base = base
		self.pointer = Pointer(undo: nil, redo: nil)
	}

	@usableFromInline
	internal var base: Base

	@inlinable
	public var wrappedValue: Base {
		_read { yield base }
	}
	
	@inlinable
	public var projectedValue: Resettable { self }

	@_spi(Internals)
	public var pointer: Pointer

	// MARK: - Undo/Redo

	/// Undo latest operation
	@discardableResult
	public func undo() -> Resettable {
		pointer = pointer.undo(&base)
		return self
	}

	/// Redo latest undone operation
	@discardableResult
	public func redo() -> Resettable {
		pointer = pointer.redo(&base)
		return self
	}

	/// Undo a sequence of latest operations
	@discardableResult
	@inlinable
	public func undo(_ count: Int) -> Resettable {
		for _ in 0..<count { undo() }
		return self
	}

	/// Redo a sequence of latest operations
	@discardableResult
	@inlinable
	public func redo(_ count: Int) -> Resettable {
		for _ in 0..<count { redo() }
		return self
	}

	/// Undo all recorded operations
	@discardableResult
	public func undoAll() -> Resettable {
		while pointer !== undo().pointer {}
		return self
	}

	/// Redo all undone operations
	@discardableResult
	public func redoAll() -> Resettable {
		while pointer !== redo().pointer {}
		return self
	}
	
	// MARK: - Unsafe modification
	
	@discardableResult
	internal func __modify(
		_ nextPointer: () -> Pointer
	) -> Resettable {
		self.pointer = nextPointer()
		return self
	}

	/// Modifies value by keyPath
	///
	/// - Note: Undo operation relies on setting value to an old snapshot,
	///         if change involves reference-based mutation, this mutation
	///         won't be recorded in undo buffer. You can use an overload
	///         with explicit undo action to record such mutations.
	@discardableResult
	public func _modify<Value>(
		operation: OperationBehavior = .default,
		_ keyPath: WritableKeyPath<Base, Value>,
		using action: @escaping (inout Value) -> Void
	) -> Resettable {
		__modify {
			pointer.apply(
				modification: action,
				for: &base, keyPath,
				operation: operation
			)
		}
	}

	/// Modifies value by keyPath
	@discardableResult
	public func _modify<Value>(
		operation: OperationBehavior = .default,
		_ keyPath: WritableKeyPath<Base, Value>,
		using action: @escaping (inout Value) -> Void,
		undo: @escaping (inout Value) -> Void
	) -> Resettable {
		__modify {
			pointer.apply(
				modification: action,
				for: &base, keyPath,
				undo: undo,
				operation: operation
			)
		}
	}

	/// Modifies an object
	@discardableResult
	public func _modify(
		operation: OperationBehavior = .default,
		using action: @escaping (inout Base) -> Void,
		undo: @escaping (inout Base) -> Void
	) -> Resettable {
		__modify {
			pointer.apply(
				modification: action,
				undo: undo,
				for: &base,
				operation: operation
			)
		}
	}
	
	// MARK: - DynamicMemberLookup
	
	// MARK: Default
	
	@inlinable
	public subscript<Value>(
		dynamicMember keyPath: WritableKeyPath<Base, Value>
	) -> WritableKeyPathContainer<Value> {
		WritableKeyPathContainer(
			resettable: self,
			keyPath: keyPath
		)
	}
	
	@inlinable
	public subscript<Value>(
		dynamicMember keyPath: KeyPath<Base, Value>
	) -> KeyPathContainer<Value> {
		KeyPathContainer(
			resettable: self,
			keyPath: keyPath
		)
	}
}

// MARK: - Undo/Redo Core

extension Resettable {
	@_spi(Internals)
	public class Pointer {
		@_spi(Internals)
		@inlinable
		public init(
			prev: Pointer? = nil,
			next: Pointer? = nil,
			undo: ((inout Base) -> Void)? = nil,
			redo: ((inout Base) -> Void)? = nil
		) {
			self.prev = prev
			self.next = next
			self._undo = undo
			self._redo = redo
		}

		public var prev: Pointer?

		public var next: Pointer?

		@usableFromInline
		var _undo: ((inout Base) -> Void)?

		@usableFromInline
		var _redo: ((inout Base) -> Void)?

		// MARK: - Undo/Redo

		@inlinable
		public func undo(_ object: inout Base) -> Pointer {
			_undo?(&object)
			return prev ?? self
		}

		@inlinable
		public func redo(_ object: inout Base) -> Pointer {
			_redo?(&object)
			return next ?? self
		}
		
		// MARK: - Apply

		@inlinable
		public func apply<Value>(
			modification action: @escaping (inout Value) -> Void,
			for object: inout Base,
			_ keyPath: WritableKeyPath<Base, Value>,
			operation: OperationBehavior = .default
		) -> Pointer {
			var didPrepareObjectForAmend = false
			if operation == .amend {
				self._undo?(&object)
				didPrepareObjectForAmend = true
			}
			let valueSnapshot = object[keyPath: keyPath]
			return apply(
				modification: action,
				for: &object,
				keyPath,
				undo: { $0 = valueSnapshot },
				operation: operation,
				didPrepareObjectForAmend: didPrepareObjectForAmend
			)
		}

		@inlinable
		public func apply<Value>(
			modification action: @escaping (inout Value) -> Void,
			for object: inout Base,
			_ keyPath: WritableKeyPath<Base, Value>,
			undo: @escaping (inout Value) -> Void,
			operation: OperationBehavior = .default,
			didPrepareObjectForAmend: Bool = false
		) -> Pointer {
			return apply(
				modification: { object in
					object[keyPath: keyPath] = modification(
						of: object[keyPath: keyPath],
						with: action
					)
				},
				undo: { object in
					object[keyPath: keyPath] = modification(
						of: object[keyPath: keyPath],
						with: undo
					)
				},
				for: &object,
				operation: operation,
				didPrepareObjectForAmend: didPrepareObjectForAmend
			)
		}

		@inlinable
		public func apply(
			modification: @escaping (inout Base) -> Void,
			undo: @escaping (inout Base) -> Void,
			for object: inout Base,
			operation: OperationBehavior = .default,
			didPrepareObjectForAmend: Bool = false
		) -> Pointer {
			if operation == .inject {
				modification(&object)
				
				let prevUndo = self._undo
				self._undo = { object in
					undo(&object)
					prevUndo?(&object)
				}
				
				let prevRedo = self.prev?._redo
				self.prev?._redo = { object in
					prevRedo?(&object)
					modification(&object)
				}
				
				return self
			}
			
			if operation == .amend {
				if !didPrepareObjectForAmend {
					self._undo?(&object)
				}
				modification(&object)
				self._undo = undo
				self.prev?._redo = modification
				return self
			}
			
			let pointer = Pointer(
				prev: self,
				next: operation == .insert ? self.next : nil,
				undo: undo,
				redo: operation == .insert ? self._redo : nil
			)
			
			modification(&object)
			self.next = pointer
			self._redo = modification
			
			return pointer
		}
	}
}

// MARK: Modification public API

extension Resettable {
	@dynamicMemberLookup
	public struct KeyPathContainer<Value> {
		@usableFromInline
		let resettable: Resettable

		@usableFromInline
		let keyPath: KeyPath<Base, Value>

		@usableFromInline
		internal init(
			resettable: Resettable<Base>,
			keyPath: KeyPath<Base, Value>
		) {
			self.resettable = resettable
			self.keyPath = keyPath
		}
		
		// MARK: - DynamicMemberLookup
		
		// MARK: Default
		
		@inlinable
		public subscript<LocalValue>(
			dynamicMember keyPath: ReferenceWritableKeyPath<Value, LocalValue>
		) -> WritableKeyPathContainer<LocalValue> {
			WritableKeyPathContainer<LocalValue>(
				resettable: resettable,
				keyPath: self.keyPath.appending(path: keyPath)
			)
		}
		
		@inlinable
		public subscript<LocalValue>(
			dynamicMember keyPath: KeyPath<Value, LocalValue>
		) -> KeyPathContainer<LocalValue> {
			KeyPathContainer<LocalValue>(
				resettable: resettable,
				keyPath: self.keyPath.appending(path: keyPath)
			)
		}
	}
	
	@dynamicMemberLookup
	public struct WritableKeyPathContainer<Value> {
		@usableFromInline
		let resettable: Resettable

		@usableFromInline
		let keyPath: WritableKeyPath<Base, Value>

		@usableFromInline
		internal init(
			resettable: Resettable<Base>,
			keyPath: WritableKeyPath<Base, Value>
		) {
			self.resettable = resettable
			self.keyPath = keyPath
		}
		
		// MARK: Modification
		
		@discardableResult
		@inlinable
		public func callAsFunction(_ value: Value, operation: OperationBehavior = .default) -> Resettable {
			return self.callAsFunction(operation) { $0 = value }
		}
		
		@discardableResult
		@inlinable
		public func callAsFunction(
			_ operation: OperationBehavior = .default,
			_ action: @escaping (inout Value) -> Void
		) -> Resettable {
			return resettable._modify(
				operation: operation,
				keyPath,
				using: action
			)
		}
		
		@discardableResult
		@inlinable
		public func callAsFunction(
			_ operation: OperationBehavior = .default,
			_ action: @escaping (inout Value) -> Void,
			undo: @escaping (inout Value) -> Void
		) -> Resettable {
			return resettable._modify(
				operation: operation,
				keyPath,
				using: action,
				undo: undo
			)
		}
		
		
		// MARK: - DynamicMemberLookup
		
		// MARK: Default
		
		@inlinable
		public subscript<LocalValue>(
			dynamicMember keyPath: WritableKeyPath<Value, LocalValue>
		) -> WritableKeyPathContainer<LocalValue> {
			WritableKeyPathContainer<LocalValue>(
				resettable: resettable,
				keyPath: self.keyPath.appending(path: keyPath)
			)
		}
		
		@inlinable
		public subscript<LocalValue>(
			dynamicMember keyPath: KeyPath<Value, LocalValue>
		) -> KeyPathContainer<LocalValue> {
			KeyPathContainer<LocalValue>(
				resettable: resettable,
				keyPath: self.keyPath.appending(path: keyPath)
			)
		}
	}

	@dynamicMemberLookup
	public struct IfLetKeyPathContainer<Wrapped> {
		public typealias Value = Wrapped?

		@usableFromInline
		let resettable: Resettable

		@usableFromInline
		let keyPath: KeyPath<Base, Value>

		@usableFromInline
		internal init(
			resettable: Resettable<Base>,
			keyPath: KeyPath<Base, Value>
		) {
			self.resettable = resettable
			self.keyPath = keyPath
		}

		// MARK: - DynamicMemberLookup

		// MARK: Default

		@inlinable
		public subscript<LocalValue>(
			dynamicMember keyPath: ReferenceWritableKeyPath<Wrapped, LocalValue>
		) -> IfLetWritableKeyPathContainer<LocalValue> {
			IfLetWritableKeyPathContainer<LocalValue>(
				resettable: resettable,
				keyPath: self.keyPath.appending(path: keyPath)
			)
		}

		@inlinable
		public subscript<LocalValue>(
			dynamicMember keyPath: KeyPath<Wrapped, LocalValue>
		) -> IfLetKeyPathContainer<LocalValue> {
			IfLetKeyPathContainer<LocalValue>(
				resettable: resettable,
				keyPath: self.keyPath.appending(path: keyPath)
			)
		}
	}

	@dynamicMemberLookup
	public struct IfLetWritableKeyPathContainer<Wrapped> {
		public typealias Value = Wrapped?

		@usableFromInline
		let resettable: Resettable

		@usableFromInline
		let keyPath: WritableKeyPath<Base, Value>

		@usableFromInline
		internal init(
			resettable: Resettable<Base>,
			keyPath: WritableKeyPath<Base, Value>
		) {
			self.resettable = resettable
			self.keyPath = keyPath
		}

		// MARK: Modification

		@discardableResult
		@inlinable
		public func callAsFunction(
			_ value: Wrapped,
			operation: OperationBehavior = .default
		) -> Resettable {
			guard resettable.wrappedValue[keyPath: keyPath] != nil else { return resettable }
			return self.callAsFunction(operation) { $0 = value }
		}

		@discardableResult
		@inlinable
		public func callAsFunction(
			_ operation: OperationBehavior = .default,
			_ action: @escaping (inout Wrapped) -> Void
		) -> Resettable {
			guard let value = resettable.wrappedValue[keyPath: keyPath] else { return resettable }
			return resettable._modify(
				operation: operation,
				keyPath.unwrapped(with: value),
				using: action
			)
		}

		@discardableResult
		@inlinable
		public func callAsFunction(
			_ operation: OperationBehavior = .default,
			_ action: @escaping (inout Wrapped) -> Void,
			undo: @escaping (inout Wrapped) -> Void
		) -> Resettable {
			guard let value = resettable.wrappedValue[keyPath: keyPath] else { return resettable }
			return resettable._modify(
				operation: operation,
				keyPath.unwrapped(with: value),
				using: action,
				undo: undo
			)
		}


		// MARK: - DynamicMemberLookup

		// MARK: Default

		@inlinable
		public subscript<LocalValue>(
			dynamicMember keyPath: WritableKeyPath<Wrapped, LocalValue>
		) -> IfLetWritableKeyPathContainer<LocalValue> {
			IfLetWritableKeyPathContainer<LocalValue>(
				resettable: resettable,
				keyPath: self.keyPath.appending(path: keyPath)
			)
		}

		@inlinable
		public subscript<LocalValue>(
			dynamicMember keyPath: KeyPath<Wrapped, LocalValue>
		) -> IfLetKeyPathContainer<LocalValue> {
			IfLetKeyPathContainer<LocalValue>(
				resettable: resettable,
				keyPath: self.keyPath.appending(path: keyPath)
			)
		}
	}
}

// MARK: - IfLet

extension Resettable where Base: _OptionalProtocol {
	public var ifLet: IfLetWritableKeyPathContainer<Base.Wrapped> {
		.init(resettable: self, keyPath: \.__marker_value)
	}
}

extension Resettable {
	public func ifLet<Wrapped>(
		_ keyPath: WritableKeyPath<Base, Wrapped?>
	) -> IfLetWritableKeyPathContainer<Wrapped> {
		.init(resettable: self, keyPath: keyPath)
	}

	public func ifLet<Wrapped>(
		_ keyPath: KeyPath<Base, Wrapped?>
	) -> IfLetKeyPathContainer<Wrapped> {
		.init(resettable: self, keyPath: keyPath)
	}
}

extension Resettable.WritableKeyPathContainer where Value: _OptionalProtocol {
	/// Provides ifLet configuration block for current keyPath
	///
	/// "`?`" operator support is not available through dynamic member lookup
	///
	/// ```swift
	/// .optionalProperty?.subproperty(value) // ❌
	/// ```
	///
	/// So this property is used instead
	///
	/// ```swift
	/// .optionalProperty.ifLet.subproperty(value) // ✅
	/// .ifLet(\.optionalProperty).subproperty(value) // ✅ this also works
	/// ```
	public var ifLet: Resettable<Base>.IfLetWritableKeyPathContainer<Value.Wrapped> {
		.init(resettable: resettable, keyPath: keyPath.appending(path: \.__marker_value))
	}

	/// Registers update for the current value. Applied only if currentValue is nil
	///
	/// Example:
	/// ```swift
	/// .optionalIntValue.ifNil(0)
	/// ```
	///
	/// If you need to proceed with further configuration use `ifLet(else:)`
	///
	/// ```swift
	/// .optionalIntValue.ifLet(else: 0).modify { $0 += 1 }
	/// ```
	///
	/// - Parameters:
	///   - value: New value to set the current one to
	///
	/// - Returns: A new container with updated stored configuration
	public func ifNil(
		_ value: Value,
		operation: Resettable.OperationBehavior = .default
	) -> Resettable {
		guard resettable.wrappedValue[keyPath: keyPath].__marker_value == nil
		else { return resettable }
		return resettable._modify(
			operation: operation,
			keyPath,
			using: { $0 = value }
		)
	}
}

extension Resettable.KeyPathContainer where Value: _OptionalProtocol {
	/// Provides ifLet configuration block for current keyPath
	///
	/// "`?`" operator support is not available through dynamic member lookup
	///
	/// ```swift
	/// .optionalProperty?.subproperty(value) // ❌
	/// ```
	///
	/// So this property is used instead
	///
	/// ```swift
	/// .optionalProperty.ifLet.subproperty(value) // ✅
	/// .ifLet(\.optionalProperty).subproperty(value) // ✅ this also works
	/// ```
	public var ifLet: Resettable<Base>.IfLetKeyPathContainer<Value.Wrapped> {
		.init(resettable: resettable, keyPath: keyPath.appending(path: \.__marker_value))
	}
}

extension Resettable.IfLetWritableKeyPathContainer where Wrapped: _OptionalProtocol {
	/// Provides ifLet configuration block for current keyPath
	///
	/// "`?`" operator support is not available through dynamic member lookup
	///
	/// ```swift
	/// .optionalProperty?.subproperty(value) // ❌
	/// ```
	///
	/// So this property is used instead
	///
	/// ```swift
	/// .optionalProperty.ifLet.subproperty(value) // ✅
	/// .ifLet(\.optionalProperty).subproperty(value) // ✅ this also works
	/// ```
	public var ifLet: Resettable<Base>.IfLetWritableKeyPathContainer<Wrapped.Wrapped> {
		.init(
			resettable: resettable,
			keyPath: keyPath.appending(path: \.__flattened_non_aggressive_marker_value)
		)
	}
}

extension Resettable.IfLetKeyPathContainer where Wrapped: _OptionalProtocol {
	/// Provides ifLet configuration block for current keyPath
	///
	/// "`?`" operator support is not available through dynamic member lookup
	///
	/// ```swift
	/// .optionalProperty?.subproperty(value) // ❌
	/// ```
	///
	/// So this property is used instead
	///
	/// ```swift
	/// .optionalProperty.ifLet.subproperty(value) // ✅
	/// .ifLet(\.optionalProperty).subproperty(value) // ✅ this also works
	/// ```
	public var ifLet: Resettable<Base>.IfLetKeyPathContainer<Wrapped.Wrapped> {
		.init(
			resettable: resettable,
			keyPath: keyPath.appending(path: \.__flattened_non_aggressive_marker_value)
		)
	}
}

// MARK: Derived

extension Resettable.WritableKeyPathContainer {
	/// Provides ifLet configuration block for specified keyPath
	///
	/// "`?`" operator support is not available through dynamic member lookup
	///
	/// ```swift
	/// .optionalProperty?.subproperty(value) // ❌
	/// ```
	///
	/// So this function is used instead
	///
	/// ```swift
	/// .ifLet(\.optionalProperty).subproperty(value) // ✅
	/// .optionalProperty.ifLet.subproperty(value) // ✅ this also works
	/// ```
	public func ifLet<Wrapped>(
		_ keyPath: WritableKeyPath<Value, Wrapped?>
	) -> Resettable.IfLetWritableKeyPathContainer<Wrapped> {
		self[dynamicMember: keyPath].ifLet
	}

	/// Provides ifLet configuration block for specified keyPath
	///
	/// "`?`" operator support is not available through dynamic member lookup
	///
	/// ```swift
	/// .optionalProperty?.subproperty(value) // ❌
	/// ```
	///
	/// So this function is used instead
	///
	/// ```swift
	/// .ifLet(\.optionalProperty).subproperty(value) // ✅
	/// .optionalProperty.ifLet.subproperty(value) // ✅ this also works
	/// ```
	public func ifLet<Wrapped>(
		_ keyPath: KeyPath<Value, Wrapped?>
	) -> Resettable.IfLetKeyPathContainer<Wrapped> {
		self[dynamicMember: keyPath].ifLet
	}
}

extension Resettable.KeyPathContainer {
	/// Provides ifLet configuration block for specified keyPath
	///
	/// "`?`" operator support is not available through dynamic member lookup
	///
	/// ```swift
	/// .optionalProperty?.subproperty(value) // ❌
	/// ```
	///
	/// So this function is used instead
	///
	/// ```swift
	/// .ifLet(\.optionalProperty).subproperty(value) // ✅
	/// .optionalProperty.ifLet.subproperty(value) // ✅ this also works
	/// ```
	public func ifLet<Wrapped>(
		_ keyPath: ReferenceWritableKeyPath<Value, Wrapped?>
	) -> Resettable.IfLetWritableKeyPathContainer<Wrapped> {
		self[dynamicMember: keyPath].ifLet
	}

	/// Provides ifLet configuration block for specified keyPath
	///
	/// "`?`" operator support is not available through dynamic member lookup
	///
	/// ```swift
	/// .optionalProperty?.subproperty(value) // ❌
	/// ```
	///
	/// So this function is used instead
	///
	/// ```swift
	/// .ifLet(\.optionalProperty).subproperty(value) // ✅
	/// .optionalProperty.ifLet.subproperty(value) // ✅ this also works
	/// ```
	public func ifLet<Wrapped>(
		_ keyPath: KeyPath<Value, Wrapped?>
	) -> Resettable.IfLetKeyPathContainer<Wrapped> {
		self[dynamicMember: keyPath].ifLet
	}
}

extension Resettable.IfLetWritableKeyPathContainer {
	/// Provides ifLet configuration block for specified keyPath
	///
	/// "`?`" operator support is not available through dynamic member lookup
	///
	/// ```swift
	/// .optionalProperty?.subproperty(value) // ❌
	/// ```
	///
	/// So this function is used instead
	///
	/// ```swift
	/// .ifLet(\.optionalProperty).subproperty(value) // ✅
	/// .optionalProperty.ifLet.subproperty(value) // ✅ this also works
	/// ```
	public func ifLet<LocalWrapped>(
		_ keyPath: WritableKeyPath<Wrapped, LocalWrapped?>
	) -> Resettable.IfLetWritableKeyPathContainer<LocalWrapped> {
		return self[dynamicMember: keyPath].ifLet
	}

	/// Provides ifLet configuration block for specified keyPath
	///
	/// "`?`" operator support is not available through dynamic member lookup
	///
	/// ```swift
	/// .optionalProperty?.subproperty(value) // ❌
	/// ```
	///
	/// So this function is used instead
	///
	/// ```swift
	/// .ifLet(\.optionalProperty).subproperty(value) // ✅
	/// .optionalProperty.ifLet.subproperty(value) // ✅ this also works
	/// ```
	public func ifLet<LocalWrapped>(
		_ keyPath: KeyPath<Wrapped, LocalWrapped?>
	) -> Resettable.IfLetKeyPathContainer<LocalWrapped> {
		return self[dynamicMember: keyPath].ifLet
	}
}

extension Resettable.IfLetKeyPathContainer {
	/// Provides ifLet configuration block for specified keyPath
	///
	/// "`?`" operator support is not available through dynamic member lookup
	///
	/// ```swift
	/// .optionalProperty?.subproperty(value) // ❌
	/// ```
	///
	/// So this function is used instead
	///
	/// ```swift
	/// .ifLet(\.optionalProperty).subproperty(value) // ✅
	/// .optionalProperty.ifLet.subproperty(value) // ✅ this also works
	/// ```
	public func ifLet<LocalWrapped>(
		_ keyPath: ReferenceWritableKeyPath<Wrapped, LocalWrapped?>
	) -> Resettable.IfLetWritableKeyPathContainer<LocalWrapped> {
		return self[dynamicMember: keyPath].ifLet
	}

	/// Provides ifLet configuration block for specified keyPath
	///
	/// "`?`" operator support is not available through dynamic member lookup
	///
	/// ```swift
	/// .optionalProperty?.subproperty(value) // ❌
	/// ```
	///
	/// So this function is used instead
	///
	/// ```swift
	/// .ifLet(\.optionalProperty).subproperty(value) // ✅
	/// .optionalProperty.ifLet.subproperty(value) // ✅ this also works
	/// ```
	public func ifLet<LocalWrapped>(
		_ keyPath: KeyPath<Wrapped, LocalWrapped?>
	) -> Resettable.IfLetKeyPathContainer<LocalWrapped> {
		return self[dynamicMember: keyPath].ifLet
	}
}

extension Optional where Wrapped: _OptionalProtocol {
	var __flattened_non_aggressive_marker_value: Wrapped.Wrapped? {
		get { self.flatMap(\.__marker_value) }
		set {
			guard var wrapped = self else { return }
			wrapped.__marker_value = newValue
			self = wrapped
		}
	}
}

@usableFromInline
@discardableResult
internal func modification<T>(
	of object: T,
	with action: (inout T) -> Void
) -> T {
	var _object = object
	action(&_object)
	return _object
}

extension Resettable: Identifiable where Base: Identifiable {
	@inlinable
	public var id: Base.ID { wrappedValue.id }
}
