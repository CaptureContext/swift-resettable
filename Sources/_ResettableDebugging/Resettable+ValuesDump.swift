@_spi(Internals) import Resettable
import CustomDump

extension Resettable {
	@available(
		*, deprecated,
		message: """
		Might be removed due to lack of Value type constraint, \
		which makes the behavior unstable, \
		consider re-implementing this feature locally if needed
		"""
	)
	public struct ValuesDump {
		@usableFromInline
		internal init(
			items: [Object],
			currentIndex: Int
		) {
			self.items = items
			self.currentIndex = currentIndex
		}

		public let items: [Object]
		public let currentIndex: Int
	}
}

extension Resettable {
	/// Dump values for __ValueTypes__
	@available(
		*, deprecated,
		 message: """
		Might be removed due to lack of Value type constraint, \
		which makes the behavior unstable, \
		consider re-implementing this feature locally if needed
		"""
	)
	public func valuesDump() -> ValuesDump {
		let _pointer = pointer
		while pointer !== undo().pointer {}
		var buffer: [Object] = [wrappedValue]
		var indexBuffer = 0
		var currentIndex = 0

		while pointer !== redo().pointer {
			indexBuffer += 1
			let isCurrent = _pointer === pointer
			buffer.append(wrappedValue)
			if isCurrent { currentIndex = indexBuffer  }
		}

		if _pointer !== pointer {
			while _pointer !== undo().pointer {}
		}

		return ValuesDump(items: buffer, currentIndex: currentIndex)
	}

	@inlinable
	public func dump() -> String {
		var buffer = ""
		self.dump(to: &buffer)
		return buffer
	}
	
	public func dump<TargetStream: TextOutputStream>(
		to stream: inout TargetStream
	) {
		let _pointer = pointer
		while pointer !== undo().pointer {}
		var buffer: [String] = []
		var initialBuffer = ""
		customDump(wrappedValue, to: &initialBuffer)
		buffer.append(#"""""#)
		buffer.append("\n")
		buffer.append(
			initialBuffer.components(separatedBy: .newlines)
				.map { "  " + $0 }
				.joined(separator: "\n")
		)
		buffer.append("\n")

		var previous = wrappedValue

		while pointer !== redo().pointer {
			let isCurrent = _pointer === pointer
			var dump = ""
			customDump(diff(previous, wrappedValue), to: &dump)
			if dump == "nil" {
				buffer.append("\n  No state changes \n")
			} else {
				var _dump = dump.trimmingCharacters(in: [#"""#])
				if isCurrent {
					if _dump.hasPrefix("\n  ") {
						_dump.removeFirst(3)
					}
					buffer.append("\n  >>> ".appending(_dump))
				} else {
					buffer.append(_dump)
				}
			}
			previous = wrappedValue
		}

		buffer.append(#"""""#)

		stream.write(buffer.joined())

		if _pointer !== pointer {
			while _pointer !== undo().pointer {}
		}
	}
}
