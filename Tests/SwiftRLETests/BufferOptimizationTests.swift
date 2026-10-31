// SPDX-License-Identifier: Apache-2.0
import Foundation
import Testing
@testable import SwiftRLE
@Suite struct BufferOptimizationTests {
 @Test func copiedSessionsRemainIndependent() throws {
  let decoder=try PackBitsDecoder()
  var a=try decoder.makeIncrementalSession(expectedByteCount:4)
  try a.append(Data([3,1]))
  var b=a
  try a.append(Data([2,3,4]));try b.append(Data([9,8,7]))
  #expect(try a.finish().data==Data([1,2,3,4]))
  #expect(try b.finish().data==Data([1,9,8,7]))
 }
 @Test func allPacketBoundariesAndSplits() throws {
  let encoder=try PackBitsEncoder(),decoder=try PackBitsDecoder()
  for length in [1,2,3,126,127,128,129,130,255,256,257] {
   for run in [1,2,3,127,128,129] {
    let input=Data((0..<length).map{UInt8(($0/run)%5)})
    let stream=try encoder.encode(input).data
    #expect(try decoder.decode(stream,expectedByteCount:input.count).data==input)
    for split in 0...stream.count {
     var session=try decoder.makeIncrementalSession(expectedByteCount:input.count)
     try session.append(stream.prefix(split));try session.append(stream.dropFirst(split))
     #expect(try session.finish().data==input)
    }
   }
  }
 }
}
