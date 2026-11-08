import Foundation

public enum SiteCapability: String, Codable, CaseIterable, Sendable { case camera, microphone }

public enum Decision: String, Codable, CaseIterable, Sendable { case ask, allow, deny }

public struct SitePermission: Codable, Identifiable, Equatable, Sendable {
    public var origin: String
    public var capability: SiteCapability
    public var decision: Decision
    public var id: String { origin + ":" + capability.rawValue }
    public init(origin: String, capability: SiteCapability, decision: Decision) { self.origin = origin; self.capability = capability; self.decision = decision }
}
