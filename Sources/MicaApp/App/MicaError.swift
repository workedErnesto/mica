import AppKit
import WebKit
import CryptoKit
import MicaCore

enum MicaError: LocalizedError { case message(String); var errorDescription: String? { switch self { case .message(let text): return text } } }
