# Security policy

## Untrusted input model

`SwiftRLE` treats all compressed PackBits byte streams, 64-byte DICOM RLE frame headers, segment offset tables, NRRD/raw CLI inputs and caller-supplied descriptors as untrusted input.

## Security invariants required in implementation (`R1`–`R5`)

1. **Checked arithmetic before allocation or indexing**: validate dimensions, component counts, storage/meaningful bits, strides, plane offsets, segment offsets and expected decoded lengths using overflow-checked integer arithmetic (`addingReportingOverflow`, `multipliedReportingOverflow`). Reject invalid or overflowing inputs with `CodecError(.invalidArgument, ...)` or `CodecError(.resourceLimitExceeded, ...)`.
2. **No input-dependent traps**: library code must never force-unwrap (`!`), force-cast (`as!`), perform unchecked integer narrowing/negation (`Int8.min` `-128` negation trap), index out of bounds on sliced `Data` (`startIndex != 0`), or call `fatalError`/`precondition`/`exit` on malformed input.
3. **Strict PackBits and DICOM RLE bounds**:
   - Reject segments that end short of the expected decoded byte count (never zero-pad missing pixels).
   - Reject literal or repeat runs that exceed the declared segment or row boundary (never clip oversized runs).
   - Enforce `segmentOffsets[0] == 64`, strictly increasing in-bounds offsets, zeroed unused offset slots (`numberOfSegments..<15`), and bounded trailing padding/no-ops.
   - Enforce a finite packet/control-byte work budget so `0x80` (`-128`) no-op floods cannot bypass time or CPU limits.
4. **Independent admission budgets (`ResourceLimits`)**: check `maximumCompressedBytes`, `maximumDecodedBytes`, `maximumWorkspaceBytes`, `maximumPixels`, `maximumDimension`, `maximumFrames`, `maximumMetadataBytes`, `maximumWorkers`, `deadlineSeconds` and aggregate `maximumMemoryBytes` before allocation. Untrusted input may never enlarge a limit.
5. **Memory ownership and concurrency safety**: pointers borrowed from `ReadOnlyImageStorage` or `WritableImageStorage` (`StorageWriteLease`) are synchronous and must never escape, be shared across concurrent tasks, or span `await`. Failed or cancelled writes after mutation begins must invalidate the `ImageDestination` and never publish partial pixel data.
6. **Safe diagnostics and zero PHI**: `CodecError` messages and CLI stderr output may report field names, byte offsets and error categories, but must never include pixel values, patient metadata, raw memory addresses or arbitrary payload dumps.
