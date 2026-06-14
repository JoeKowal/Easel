//
//  QuickSitesPublisherTests.swift
//  EaselTests
//

import Foundation
import Testing
@testable import Easel

@MainActor
struct QuickSitesPublisherTests {
  @Test
  func suggestedSiteSlugAddsEaselPrefix() {
    let slug = DefaultQuickSitesPublisher.suggestedSiteSlug(
      for: "/Users/jk/Documents/Easel Projects/Revenue Demo"
    )

    #expect(slug == "quick-easel-revenue-demo")
  }

  @Test
  func suggestedSiteSlugDoesNotDoublePrefixQuickNames() {
    let slug = DefaultQuickSitesPublisher.suggestedSiteSlug(
      for: "/Users/jk/Documents/Easel Projects/quick-easel-existing"
    )

    #expect(slug == "quick-easel-existing")
  }

  @Test
  func publishResultDecodesQuickSitesJSON() throws {
    let data = Data(
      """
      {
        "status": "OK",
        "site": "quick-easel-demo",
        "serviceUrl": "https://quick.tail4fa75d.ts.net/sites/quick-easel-demo/",
        "compatibilityUrl": "https://hetzner.tail4fa75d.ts.net/quick/sites/quick-easel-demo/",
        "output": "/tmp/evidence",
        "proofPack": "/tmp/evidence/proof-pack.md",
        "closeout": {
          "packet": "/tmp/evidence/closeout/packet.md",
          "closeout": "/tmp/evidence/closeout/closeout.md"
        }
      }
      """.utf8
    )

    let result = try JSONDecoder().decode(QuickSitesPublishResult.self, from: data)

    #expect(result.status == "OK")
    #expect(result.site == "quick-easel-demo")
    #expect(result.serviceUrl.absoluteString == "https://quick.tail4fa75d.ts.net/sites/quick-easel-demo/")
    #expect(result.proofPack == "/tmp/evidence/proof-pack.md")
    #expect(result.closeout?.closeout == "/tmp/evidence/closeout/closeout.md")
  }

  @Test
  func suggestedMetadataUsesProjectContext() {
    let metadata = DefaultQuickSitesPublisher.suggestedMetadata(
      projectName: "Revenue Demo",
      projectDirectory: "/Users/jk/Documents/Easel Projects/Revenue Demo",
      projectKind: "prototype"
    )

    #expect(metadata.title == "Revenue Demo")
    #expect(metadata.tags.contains("easel"))
    #expect(metadata.tags.contains("prototype"))
    #expect(metadata.sensitivity == "internal")
    #expect(metadata.lifecycleStatus == "watch")
    #expect(metadata.template == "easel-prototype")
  }
}
