//
//  String+Extension.swift
//  iOSJavascriptPlayground
//
//  Created by Jim Learning on 2025/2/5.
//

import Foundation
import CommonCrypto

extension URL {
    func withScheme(_ scheme: String) -> URL? {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.scheme = scheme
        return components.url
    }
}

extension String {
    func sha256() -> String {
        let data = Data(self.utf8)
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(buffer.count), &hash)
        }
        return Data(hash).map { String(format: "%02hhx", $0) }.joined()
    }
}
