import FunctionalKeyPath

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
/// Records changes performed on an Object
/// - Note: Any recorded changes will clear redo buffer
@propertyWrapper
@dynamicMemberLookup
public class Resettable<Object> {
	public convenience init(wrappedValue: Object) {
		self.init(wrappedValue)
	}

	public init(_ object: Object) {
		self.object = object
		self.pointer = Pointer(undo: nil, redo: nil)
	}

	@usableFromInline
	internal var object: Object
	
	@inlinable
	public var wrappedValue: Object { object }
	
	@inlinable
	public var projectedValue: Resettable { self }

	@_spi(Internals)
	public var pointer: Pointer

	// MARK: - Undo/Redo

	/// Undo latest operation
	@discardableResult
	public func undo() -> Resettable {
		pointer = pointer.undo(&object)
		return self
	}

	/// Redo latest undone operation
	@discardableResult
	public func redo() -> Resettable {
		pointer = pointer.redo(&object)
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
		_ keyPath: FunctionalKeyPath<Object, Value>,
		using action: @escaping (inout Value) -> Void
	) -> Resettable {
		__modify {
			pointer.apply(
				modification: action,
				for: &object, keyPath,
				operation: operation
			)
		}
	}

	/// Modifies value by keyPath
	@discardableResult
	public func _modify<Value>(
		operation: OperationBehavior = .default,
		_ keyPath: FunctionalKeyPath<Object, Value>,
		using action: @escaping (inout Value) -> Void,
		undo: @escaping (inout Value) -> Void
	) -> Resettable {
		__modify {
			pointer.apply(
				modification: action,
				for: &object, keyPath,
				undo: undo,
				operation: operation
			)
		}
	}

	/// Modifies an object
	@discardableResult
	public func _modify(
		operation: OperationBehavior = .default,
		using action: @escaping (inout Object) -> Void,
		undo: @escaping (inout Object) -> Void
	) -> Resettable {
		__modify {
			pointer.apply(
				modification: action,
				undo: undo,
				for: &object,
				operation: operation
			)
		}
	}
	
	// MARK: - DynamicMemberLookup
	
	// MARK: Default
	
	@inlinable
	public subscript<Value>(
		dynamicMember keyPath: WritableKeyPath<Object, Value>
	) -> WritableKeyPathContainer<Value> {
		WritableKeyPathContainer(
			resettable: self,
			keyPath: .init(keyPath)
		)
	}
	
	@inlinable
	public subscript<Value>(
		dynamicMember keyPath: KeyPath<Object, Value>
	) -> KeyPathContainer<Value> {
		KeyPathContainer(
			resettable: self,
			keyPath: .getonly(keyPath)
		)
	}
	
	// MARK: Optional
	
	@inlinable
	public subscript<Value, Wrapped>(
		dynamicMember keyPath: WritableKeyPath<Wrapped, Value>
	) -> WritableKeyPathContainer<Value?> where Object == Optional<Wrapped> {
		WritableKeyPathContainer<Value?>(
			resettable: self,
			keyPath: FunctionalKeyPath(keyPath).optional()
		)
	}
	
	@inlinable
	public subscript<Value, Wrapped>(
		dynamicMember keyPath: KeyPath<Wrapped, Value>
	) -> KeyPathContainer<Value?> where Object == Optional<Wrapped> {
		KeyPathContainer<Value?>(
			resettable: self,
			keyPath: FunctionalKeyPath.getonly(keyPath).optional()
		)
	}
	
	// MARK: Collection
	
	@inlinable
	public subscript<Value>(
		dynamicMember keyPath: WritableKeyPath<Object, Value>
	) -> WritableCollectionProxy<Value> where Value: Swift.Collection {
		WritableCollectionProxy<Value>(
			resettable: self,
			keyPath: .init(keyPath)
		)
	}
	
	@inlinable
	public subscript<Value>(
		dynamicMember keyPath: KeyPath<Object, Value>
	) -> CollectionProxy<Value> where Value: Swift.Collection {
		CollectionProxy<Value>(
			resettable: self,
			keyPath: .getonly(keyPath)
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
			undo: ((inout Object) -> Void)? = nil,
			redo: ((inout Object) -> Void)? = nil
		) {
			self.prev = prev
			self.next = next
			self._undo = undo
			self._redo = redo
		}

		public var prev: Pointer?

		public var next: Pointer?

		@usableFromInline
		var _undo: ((inout Object) -> Void)?
		
		@usableFromInline
		var _redo: ((inout Object) -> Void)?
		
		// MARK: - Undo/Redo

		@inlinable
		public func undo(_ object: inout Object) -> Pointer {
			_undo?(&object)
			return prev ?? self
		}

		@inlinable
		public func redo(_ object: inout Object) -> Pointer {
			_redo?(&object)
			return next ?? self
		}
		
		// MARK: - Apply

		@inlinable
		public func apply<Value>(
			modification action: @escaping (inout Value) -> Void,
			for object: inout Object,
			_ keyPath: FunctionalKeyPath<Object, Value>,
			operation: OperationBehavior = .default
		) -> Pointer {
			var didPrepareObjectForAmend = false
			if operation == .amend {
				self._undo?(&object)
				didPrepareObjectForAmend = true
			}
			let valueSnapshot = keyPath.extract(from: object)
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
			for object: inout Object,
			_ keyPath: FunctionalKeyPath<Object, Value>,
			undo: @escaping (inout Value) -> Void,
			operation: OperationBehavior = .default,
			didPrepareObjectForAmend: Bool = false
		) -> Pointer {
			return apply(
				modification: { object in
					keyPath.embed(
						modification(
							of: keyPath.extract(from: object),
							with: action
						),
						in: &object
					)
				},
				undo: { object in
					keyPath.embed(
						modification(
							of: keyPath.extract(from: object),
							with: undo
						),
						in: &object
					)
				},
				for: &object,
				operation: operation,
				didPrepareObjectForAmend: didPrepareObjectForAmend
			)
		}

		@inlinable
		public func apply(
			modification: @escaping (inout Object) -> Void,
			undo: @escaping (inout Object) -> Void,
			for object: inout Object,
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
		internal init(
			resettable: Resettable<Object>,
			keyPath: FunctionalKeyPath<Object, Value>
		) {
			self.resettable = resettable
			self.keyPath = keyPath
		}
		
		@usableFromInline
		let resettable: Resettable
		
		@usableFromInline
		let keyPath: FunctionalKeyPath<Object, Value>
		
		// MARK: - DynamicMemberLookup
		
		// MARK: Default
		
		@inlinable
		public subscript<LocalValue>(
			dynamicMember keyPath: ReferenceWritableKeyPath<Value, LocalValue>
		) -> WritableKeyPathContainer<LocalValue> {
			WritableKeyPathContainer<LocalValue>(
				resettable: resettable,
				keyPath: self.keyPath.appending(path: .init(keyPath))
			)
		}
		
		@inlinable
		public subscript<LocalValue>(
			dynamicMember keyPath: KeyPath<Value, LocalValue>
		) -> KeyPathContainer<LocalValue> {
			KeyPathContainer<LocalValue>(
				resettable: resettable,
				keyPath: self.keyPath.appending(path: .getonly(keyPath))
			)
		}
		
		// MARK: Optional
		
		@inlinable
		public subscript<LocalValue, Wrapped>(
			dynamicMember keyPath: ReferenceWritableKeyPath<Wrapped, LocalValue>
		) -> WritableKeyPathContainer<LocalValue?> where Value == Optional<Wrapped> {
			WritableKeyPathContainer<LocalValue?>(
				resettable: resettable,
				keyPath: self.keyPath.appending(path: .init(keyPath))
			)
		}
		
		@inlinable
		public subscript<LocalValue, Wrapped>(
			dynamicMember keyPath: KeyPath<Wrapped, LocalValue>
		) -> KeyPathContainer<LocalValue?> where Value == Optional<Wrapped> {
			KeyPathContainer<LocalValue?>(
				resettable: resettable,
				keyPath: self.keyPath.appending(path: .getonly(keyPath))
			)
		}
		
		// MARK: Collection
		
		@inlinable
		public subscript<LocalValue>(
			dynamicMember keyPath: ReferenceWritableKeyPath<Value, LocalValue>
		) -> WritableCollectionProxy<LocalValue> where LocalValue: Swift.Collection {
			WritableCollectionProxy<LocalValue>(
				resettable: resettable,
				keyPath: self.keyPath.appending(path: .init(keyPath))
			)
		}
		
		@inlinable
		public subscript<LocalValue>(
			dynamicMember keyPath: KeyPath<Value, LocalValue>
		) -> CollectionProxy<LocalValue> where LocalValue: Swift.Collection {
			CollectionProxy<LocalValue>(
				resettable: resettable,
				keyPath: self.keyPath.appending(path: .getonly(keyPath))
			)
		}
	}
	
	@dynamicMemberLookup
	public struct WritableKeyPathContainer<Value> {
		@usableFromInline
		internal init(
			resettable: Resettable<Object>,
			keyPath: FunctionalKeyPath<Object, Value>
		) {
			self.resettable = resettable
			self.keyPath = keyPath
		}
		
		@usableFromInline
		let resettable: Resettable
		
		@usableFromInline
		let keyPath: FunctionalKeyPath<Object, Value>
		
		// MARK: Modification
		
		@discardableResult
		@inlinable
		public func callAsFunction(_ value: Value, operation: OperationBehavior = .default) -> Resettable {
			return self.callAsFunction(operation) { $0 = value }
		}
		
		@discardableResult
		@inlinable
		public func callAsFunction(_ operation: OperationBehavior = .default, _ action: @escaping (inout Value) -> Void) -> Resettable {
			return resettable._modify(operation: operation, keyPath, using: action)
		}
		
		@discardableResult
		@inlinable
		public func callAsFunction(
			_ operation: OperationBehavior = .default,
			_ action: @escaping (inout Value) -> Void,
			undo: @escaping (inout Value) -> Void
		) -> Resettable {
			return resettable._modify(operation: operation, keyPath, using: action, undo: undo)
		}
		
		
		// MARK: - DynamicMemberLookup
		
		// MARK: Default
		
		@inlinable
		public subscript<LocalValue>(
			dynamicMember keyPath: WritableKeyPath<Value, LocalValue>
		) -> WritableKeyPathContainer<LocalValue> {
			WritableKeyPathContainer<LocalValue>(
				resettable: resettable,
				keyPath: self.keyPath.appending(path: .init(keyPath))
			)
		}
		
		@inlinable
		public subscript<LocalValue>(
			dynamicMember keyPath: KeyPath<Value, LocalValue>
		) -> KeyPathContainer<LocalValue> {
			KeyPathContainer<LocalValue>(
				resettable: resettable,
				keyPath: self.keyPath.appending(path: .getonly(keyPath))
			)
		}
		
		// MARK: Optional
		
		@inlinable
		public subscript<LocalValue, Wrapped>(
			dynamicMember keyPath: WritableKeyPath<Wrapped, LocalValue>
		) -> WritableKeyPathContainer<LocalValue?> where Value == Optional<Wrapped> {
			WritableKeyPathContainer<LocalValue?>(
				resettable: resettable,
				keyPath: self.keyPath.appending(path: .init(keyPath))
			)
		}
		
		@inlinable
		public subscript<LocalValue, Wrapped>(
			dynamicMember keyPath: KeyPath<Wrapped, LocalValue>
		) -> KeyPathContainer<LocalValue?> where Value == Optional<Wrapped> {
			KeyPathContainer<LocalValue?>(
				resettable: resettable,
				keyPath: self.keyPath.appending(path: .getonly(keyPath))
			)
		}
		
		// MARK: Collection
		
		@inlinable
		public subscript<LocalValue>(
			dynamicMember keyPath: WritableKeyPath<Value, LocalValue>
		) -> WritableCollectionProxy<LocalValue> where LocalValue: Swift.Collection {
			WritableCollectionProxy<LocalValue>(
				resettable: resettable,
				keyPath: self.keyPath.appending(path: .init(keyPath))
			)
		}
		
		@inlinable
		public subscript<LocalValue>(
			dynamicMember keyPath: KeyPath<Value, LocalValue>
		) -> CollectionProxy<LocalValue> where LocalValue: Swift.Collection {
			CollectionProxy<LocalValue>(
				resettable: resettable,
				keyPath: self.keyPath.appending(path: .getonly(keyPath))
			)
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

extension Resettable: Identifiable where Object: Identifiable {
	@inlinable
	public var id: Object.ID { wrappedValue.id }
}
