//
//  Encryption.swift
//  StateRestoration
//
//  Created by Mateusz Kuznik on 01/06/2024.
//  Copyright © 2024 Apple. All rights reserved.
//

import Foundation
import System
import AppleArchive
import CryptoKit

struct Encryption {
    
    let fileName: String
    
    public enum Error: Swift.Error {
        case unableToCreateDecodeStream
        case unableToGetHeaderField
        case zeroDataSize
        case unableToCreateFileStream
        case unableToCreateEncryptionStream
        case unableToCreateDecryptionContext
    }
    
    func save(_ data: String) throws {
        let encryptedFilePath = FilePath(NSTemporaryDirectory() + fileName + ".aar")
        let key = SymmetricKey(size: SymmetricKeySize.bits256)
        
        try encryptString(key: key,
                          string: data,
                          unarchivedFileName: "lorem.txt",
                          destinationFilePath: encryptedFilePath)
        
        try GenericPasswordStore().deleteKey(account: fileName)
        try GenericPasswordStore().storeKey(key, account: fileName)
        print("encryptedFilePath = \(encryptedFilePath)")
        
        
    }
    
    func retrieve() throws -> String? {
        let encryptedFilePath = FilePath(NSTemporaryDirectory() + fileName + ".aar")
        let key: SymmetricKey? = try GenericPasswordStore().readKey(account: fileName)
        guard let key else { return nil }
        let result = try decryptString(key: key,
                                       sourceFilePath: encryptedFilePath)
        
        return result
    }
    
    private func encryptString(key: SymmetricKey,
                              string: String,
                              unarchivedFileName: String,
                              destinationFilePath: FilePath) throws {
        
        let context = ArchiveEncryptionContext(profile: .hkdf_sha256_aesctr_hmac__symmetric__none,
                                               compressionAlgorithm: .lzfse)
        try context.setSymmetricKey(key)
        
        // Create the destination file stream. Define the options as `[ .create, .truncate ]`.
        // The `.create` option specifies that the byte stream creates the file
        // if it doesn’t already exist. The `.truncate` option specifies that if
        // the file exists, the byte stream truncates it to zero bytes before it
        // performs any operations.
        guard let destinationFileStream = ArchiveByteStream.fileStream(
                path: destinationFilePath,
                mode: .writeOnly,
                options: [ .create, .truncate ],
                permissions: FilePermissions(rawValue: 0o644)) else {
            return
        }
        defer {
            try? destinationFileStream.close()
        }
        
        // Create the encryption output stream.
        guard let encryptionStream = ArchiveByteStream.encryptionStream(
                writingTo: destinationFileStream,
                encryptionContext: context) else {
            throw Error.unableToCreateEncryptionStream
        }
        defer {
            try? encryptionStream.close()
        }
        
        // Create the encoding stream. The encoding stream encodes its data as a
        // byte stream and sends the encoded data to the encyption stream.
        guard let encodeStream = ArchiveStream.encodeStream(writingTo: encryptionStream) else {
            return
        }
        defer {
            try? encodeStream.close()
        }
        
        // Define the header for the archive file.
        let header = ArchiveHeader()
        
        // The PAT field contains the file path. Specify the unarchived file name
        // for the PAT field.
        header.append(.string(key: ArchiveHeader.FieldKey("PAT"),
                              value: unarchivedFileName))
        
        // The TYP field contains the compressed file type. Specify `regularFile`
        // for the TYP field.
        header.append(.uint(key: ArchiveHeader.FieldKey("TYP"),
                            value: UInt64(ArchiveHeader.EntryType.regularFile.rawValue)))
        
        // The DAT field contains the compressed file payload. Specify the size
        // of the uncompressed data, in bytes, for the DAT field.
        header.append(.blob(key: ArchiveHeader.FieldKey("DAT"),
                            size: UInt64(string.utf8.count)))
        
        //  Write the header to the encode stream.
        try encodeStream.writeHeader(header)

        // Write the contents of the string as a data stream to the encode stream.
        var mutableString = string
        try mutableString.withUTF8 { textPtr in
            let rawBufferPointer = UnsafeRawBufferPointer(textPtr)

            try encodeStream.writeBlob(key: ArchiveHeader.FieldKey("DAT"),
                                       from: rawBufferPointer)
        }
    }

    private func decryptString(key: SymmetricKey,
                              sourceFilePath: FilePath) throws -> String {
        
        // Create a file stream to open the encrypted source file.
        guard let sourceFileStream = ArchiveByteStream.fileStream(
                path: sourceFilePath,
                mode: .readOnly,
                options: [ ],
                permissions: FilePermissions(rawValue: 0o644)) else {
            throw Error.unableToCreateFileStream
        }
        defer {
            try? sourceFileStream.close()
        }
        
        // Create the decryption context from the encrypted file. The compression
        // algorithm and block size are derived from the encrypted source file.
        guard let decryptionContext = ArchiveEncryptionContext(from: sourceFileStream) else {
            throw Error.unableToCreateDecryptionContext
        }
        
        // Set the key on the context.
        try decryptionContext.setSymmetricKey(key)
        
        // Create the decryption output stream.
        guard let decryptionStream = ArchiveByteStream.decryptionStream(
            readingFrom: sourceFileStream,
            encryptionContext: decryptionContext) else {
            throw Error.unableToCreateFileStream
        }
        defer {
            try? decryptionStream.close()
        }
        
        // Create a decoding stream that provides archive elements from the raw,
        // decrypted data.
        guard let decodeStream = ArchiveStream.decodeStream(
                readingFrom: decryptionStream) else {
            throw Error.unableToCreateFileStream
        }
        defer {
            try? decodeStream.close()
        }
        
        // Derive the size of the uncompressed and decrypted string from the DAT
        // field of the decode stream's header.
        let byteCount: Int = try {
            let header = try decodeStream.readHeader()
            guard
                let datField = header?.field(forKey: ArchiveHeader.FieldKey("DAT")) else {
                    throw Error.unableToGetHeaderField
            }

            switch datField {
                case .blob(_, let size, _):
                    return Int(size)
                default:
                    return 0
            }
        }()
        
        guard byteCount != 0 else {
            throw Error.zeroDataSize
        }
        
        // Create a buffer to receive the decompressed and decrypted data.
        let rawBufferPtr = UnsafeMutableRawBufferPointer.allocate(
                byteCount: byteCount,
                alignment: MemoryLayout<UTF8>.alignment)
        defer {
            rawBufferPtr.deallocate()
        }
        
        // Read the decoded data from the DAT field and write it to the
        // raw buffer pointer.
        try decodeStream.readBlob(key: ArchiveHeader.FieldKey("DAT"),
                                  into: rawBufferPtr)
        
        // Create a string from the raw buffer pointer.
        let typedPtr = rawBufferPtr.bindMemory(to: CChar.self)
        let decryptedString = String(cString: typedPtr.baseAddress!)
        return decryptedString
    }
}
