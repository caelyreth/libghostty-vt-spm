/// Keeps typed Swift output values addressable while a C API writes through a
/// temporary `void **` array. The pointers and their backing values cannot
/// escape the closure.
enum COutputPointers {
    @inline(__always)
    static func withPointers<First, Second, Third, Result>(
        _ first: inout First,
        _ second: inout Second,
        _ third: inout Third,
        _ body: (UnsafeMutableBufferPointer<UnsafeMutableRawPointer?>) -> Result
    ) -> Result {
        withUnsafeMutablePointer(to: &first) { firstPointer in
            withUnsafeMutablePointer(to: &second) { secondPointer in
                withUnsafeMutablePointer(to: &third) { thirdPointer in
                    withBuffer(capacity: 3) { pointers in
                        pointers[0] = UnsafeMutableRawPointer(firstPointer)
                        pointers[1] = UnsafeMutableRawPointer(secondPointer)
                        pointers[2] = UnsafeMutableRawPointer(thirdPointer)
                        return body(pointers)
                    }
                }
            }
        }
    }

    @inline(__always)
    static func withPointers<First, Second, Third, Fourth, Fifth, Result>(
        _ first: inout First,
        _ second: inout Second,
        _ third: inout Third,
        _ fourth: inout Fourth,
        _ fifth: inout Fifth,
        _ body: (UnsafeMutableBufferPointer<UnsafeMutableRawPointer?>) -> Result
    ) -> Result {
        withUnsafeMutablePointer(to: &first) { firstPointer in
            withUnsafeMutablePointer(to: &second) { secondPointer in
                withUnsafeMutablePointer(to: &third) { thirdPointer in
                    withUnsafeMutablePointer(to: &fourth) { fourthPointer in
                        withUnsafeMutablePointer(to: &fifth) { fifthPointer in
                            withBuffer(capacity: 5) { pointers in
                                pointers[0] = UnsafeMutableRawPointer(firstPointer)
                                pointers[1] = UnsafeMutableRawPointer(secondPointer)
                                pointers[2] = UnsafeMutableRawPointer(thirdPointer)
                                pointers[3] = UnsafeMutableRawPointer(fourthPointer)
                                pointers[4] = UnsafeMutableRawPointer(fifthPointer)
                                return body(pointers)
                            }
                        }
                    }
                }
            }
        }
    }

    @inline(__always)
    private static func withBuffer<Result>(
        capacity: Int,
        _ body: (UnsafeMutableBufferPointer<UnsafeMutableRawPointer?>) -> Result
    ) -> Result {
        precondition(capacity > 0)

        return withUnsafeTemporaryAllocation(
            of: UnsafeMutableRawPointer?.self,
            capacity: capacity
        ) { pointers in
            let baseAddress = pointers.baseAddress!
            baseAddress.initialize(repeating: nil, count: capacity)
            defer { baseAddress.deinitialize(count: capacity) }
            return body(pointers)
        }
    }
}
