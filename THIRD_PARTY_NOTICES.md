# Third-party and provenance notices

SwiftRLE is distributed under the Apache License, Version 2.0 ([LICENSE](LICENSE), [NOTICE](NOTICE)) per owner decision on 23 October 2026 extending [Documentation/SUITE_POLICY.md](Documentation/SUITE_POLICY.md) (`POL-07`) to SwiftRLE. The shipped library (`SwiftRLE`) will contain zero third-party source code and zero external SwiftPM package dependencies in its core target.

## In-house predecessor code and preserved MIT notice

SwiftRLE extracts and adapts RLE (PackBits and DICOM PS3.5 Annex G) codec logic and test cases from [raster-labs/DICOMKit](https://github.com/raster-labs/DICOMKit) pinned at commit [`4b68d7e22829418c88e48dd53d98b25fee50d90d`](https://github.com/raster-labs/DICOMKit/commit/4b68d7e22829418c88e48dd53d98b25fee50d90d) (`v2.9.0`, 23 October 2026).

`DICOMKit` is and remains licensed under the MIT License (`LICENSE` SHA-256: `4c0768004e1c88e30b7c28f3f4ea03998c351c89b81db0d05e333998acf8b9f4`). In accordance with the owner's licensing decision and MIT terms, the full original `DICOMKit` copyright and permission notice is retained verbatim below and in [NOTICE](NOTICE):

```text
MIT License

Copyright (c) 2026 rasterdevapps

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## In-house common contract documentation and reference surface

The seven common contract specifications under `Documentation/` and the common API/storage reference design (`SwiftJ2K` commit [`be4e7a3ad352759e7a78a90f6a2e2c3b7aa0f748`](https://github.com/raster-labs/SwiftJ2K/commit/be4e7a3ad352759e7a78a90f6a2e2c3b7aa0f748), `SwiftJLS` commit [`0791e54a5950bb8082af2218bce3800e03c777b9`](https://github.com/raster-labs/SwiftJLS/commit/0791e54a5950bb8082af2218bce3800e03c777b9)) are in-house works of Raster Images Private Limited licensed under Apache-2.0 (`POL-07`).

## Development and verification tools (never linked or shipped)

The following external tools are used strictly as out-of-process reference oracles during development and qualification testing (`R1`–`R5`). No oracle source code or binary is vendored, compiled into, or distributed with `SwiftRLE`:

| Tool | Role in qualification | Licence |
| --- | --- | --- |
| `libtiff` (`tiffcp`, `tiffinfo`) | Independent PackBits strip encode/decode verification (`R1`) | libtiff BSD-like permissive licence |
| `DCMTK` (`dcmdrle`, `dcmcrle`) | Independent DICOM RLE Lossless (`1.2.840.10008.1.2.5`) frame decode/encode oracle (`R2`) | BSD-3-Clause |
| `GDCM` (`gdcmconv`, `gdcmraw`) | Secondary independent DICOM RLE frame encode/decode oracle (`R2`) | BSD-3-Clause (Apache-2.0 compatible) |
| Swift toolchains & Xcode SDKs | Compilation, unit/regression testing, sanitizer runs and platform qualification | Apple / Swift.org terms |

## Test fixtures

All unit, regression, interoperability and benchmark fixtures introduced in `R1`–`R5` must be deterministic synthetic data generated in-house (with recorded generator script, seed and SHA-256) or explicitly licensed third-party material with recorded provenance. Zero clinical or patient health information (PHI) is permitted in source, fixtures, logs or documentation.
