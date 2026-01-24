import CryptoKit
import Foundation

enum DeterministicID {
  static func generate(from relativePath: String) -> UUID {
    let data = Data(relativePath.utf8)
    let hash = SHA256.hash(data: data)
    let hashData = Data(hash)

    let uuidBytes = Array(hashData.prefix(16))
    return UUID(
      uuid: (
        uuidBytes[0], uuidBytes[1], uuidBytes[2], uuidBytes[3],
        uuidBytes[4], uuidBytes[5], uuidBytes[6], uuidBytes[7],
        uuidBytes[8], uuidBytes[9], uuidBytes[10], uuidBytes[11],
        uuidBytes[12], uuidBytes[13], uuidBytes[14], uuidBytes[15]
      ))
  }
}
