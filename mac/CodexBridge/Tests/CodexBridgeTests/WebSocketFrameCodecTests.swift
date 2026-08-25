import Foundation
import Testing
@testable import CodexBridge

@Test func decodesShortServerFrame() throws {
    var buffer = Data([0x81, 0x05]) + Data("hello".utf8)
    let decoded = try WebSocketFrameCodec.popServerFrame(from: &buffer)
    let frame = try #require(decoded)
    #expect(frame == WebSocketFrame(final: true, opcode: 0x1, payload: Data("hello".utf8)))
    #expect(buffer.isEmpty)
}

@Test func waitsForCompleteServerFrame() throws {
    var buffer = Data([0x81, 0x05, 0x68])
    #expect(try WebSocketFrameCodec.popServerFrame(from: &buffer) == nil)
    #expect(buffer == Data([0x81, 0x05, 0x68]))
}

@Test func decodesConsecutiveFramesAfterBufferIndexMoves() throws {
    var buffer = Data([0x81, 0x01, 0x61, 0x81, 0x01, 0x62])
    let decodedFirst = try WebSocketFrameCodec.popServerFrame(from: &buffer)
    let first = try #require(decodedFirst)
    let decodedSecond = try WebSocketFrameCodec.popServerFrame(from: &buffer)
    let second = try #require(decodedSecond)
    #expect(first.payload == Data("a".utf8))
    #expect(second.payload == Data("b".utf8))
    #expect(buffer.isEmpty)
}

@Test func encodesMaskedClientFrame() {
    let frame = WebSocketFrameCodec.clientFrame(opcode: 0x1, payload: Data("hello".utf8))
    #expect(frame[0] == 0x81)
    #expect(frame[1] & 0x80 != 0)
    #expect(frame.count == 2 + 4 + 5)
}
