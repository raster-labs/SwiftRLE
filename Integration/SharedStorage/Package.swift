// swift-tools-version: 6.2
// SPDX-License-Identifier: Apache-2.0
import PackageDescription
let package = Package(name:"SwiftRLESharedStorage",platforms:[.macOS(.v26)],products:[.library(name:"SharedStorage",targets:["SharedStorage"])],dependencies:[.package(path:"../.."),.package(url:"https://github.com/raster-labs/SwiftJLS.git",revision:"0791e54a5950bb8082af2218bce3800e03c777b9")],targets:[.target(name:"DICOMKitCandidate",dependencies:[.product(name:"SwiftRLE",package:"SwiftRLE")]),.target(name:"SharedStorage",dependencies:[.product(name:"SwiftRLE",package:"SwiftRLE"),.product(name:"SwiftJLS",package:"SwiftJLS")]),.testTarget(name:"SharedStorageTests",dependencies:["SharedStorage","DICOMKitCandidate"])],swiftLanguageModes:[.v6])
