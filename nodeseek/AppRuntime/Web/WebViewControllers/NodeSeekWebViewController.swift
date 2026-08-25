//
//  NodeSeekWebViewController.swift
//  nodeseek
//
//  Created by Codex on 2026/4/30.
//

import UIKit
import WebKit

final class NodeSeekWebViewController: BaseWebViewController {
    override var usesCustomUserAgent: Bool {
        false
    }

    init(
        url: URL,
        pageTitle: String = "网页",
        automaticallyLoadsPage: Bool = true,
        allowsPageZoom: Bool = false,
        additionalUserScripts: [WKUserScript] = []
    ) {
        super.init(
            initialURL: url,
            pageTitle: pageTitle,
            automaticallyLoadsPage: automaticallyLoadsPage,
            allowsPageZoom: allowsPageZoom,
            additionalUserScripts: additionalUserScripts
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

#if DEBUG
extension NodeSeekWebViewController {
    var testInitialURL: URL {
        initialURL
    }

    static func nativePostRoute(for url: URL, baseURL: URL) -> NodeSeekPostRoute? {
        nil
    }
}
#endif
