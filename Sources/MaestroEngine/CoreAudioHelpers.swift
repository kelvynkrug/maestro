import CoreAudio
import Foundation

struct CoreAudioError: Error, CustomStringConvertible {
    let status: OSStatus
    let operation: String
    var description: String { "\(operation) falhou (OSStatus \(status))" }
}

func check(_ status: OSStatus, _ operation: String) throws {
    guard status == noErr else { throw CoreAudioError(status: status, operation: operation) }
}

func address(
    _ selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
}

func readProperty<T>(
    _ object: AudioObjectID,
    _ propertyAddress: AudioObjectPropertyAddress,
    into value: inout T,
    _ operation: String
) throws {
    var propertyAddress = propertyAddress
    var size = UInt32(MemoryLayout<T>.size)
    try check(AudioObjectGetPropertyData(object, &propertyAddress, 0, nil, &size, &value), operation)
}

func readArray<T>(
    _ object: AudioObjectID,
    _ propertyAddress: AudioObjectPropertyAddress,
    of _: T.Type,
    _ operation: String
) throws -> [T] {
    var propertyAddress = propertyAddress
    var size: UInt32 = 0
    try check(AudioObjectGetPropertyDataSize(object, &propertyAddress, 0, nil, &size), "\(operation) (tamanho)")
    let count = Int(size) / MemoryLayout<T>.stride
    guard count > 0 else { return [] }
    return try [T](unsafeUninitializedCapacity: count) { buffer, initializedCount in
        try check(AudioObjectGetPropertyData(object, &propertyAddress, 0, nil, &size, buffer.baseAddress!), operation)
        initializedCount = Int(size) / MemoryLayout<T>.stride
    }
}

func readString(
    _ object: AudioObjectID,
    _ propertyAddress: AudioObjectPropertyAddress,
    _ operation: String
) throws -> String {
    var propertyAddress = propertyAddress
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    var value: Unmanaged<CFString>?
    try withUnsafeMutablePointer(to: &value) { pointer in
        try check(AudioObjectGetPropertyData(object, &propertyAddress, 0, nil, &size, pointer), operation)
    }
    guard let cfString = value?.takeRetainedValue() else {
        throw CoreAudioError(status: -1, operation: "\(operation) (valor vazio)")
    }
    return cfString as String
}
