// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import SwiftUI
import UIKit

final class KeyboardViewController: UIInputViewController {
    private let model = KeyboardModel()
    private let dictionaryOffer = DictionaryOffer()
    private var hosting: UIHostingController<KeyboardView>?

    override func viewDidLoad() {
        super.viewDidLoad()
        model.controller = self
        dictionaryOffer.controller = self
        model.onOwnCopy = { [weak dictionaryOffer] in dictionaryOffer?.noteOwnCopy() }
        let hosting = UIHostingController(rootView: KeyboardView(model: model, offer: dictionaryOffer, controller: self))
        hosting.view.backgroundColor = .clear
        hosting.sizingOptions = []
        addChild(hosting)
        view.addSubview(hosting.view)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            view.heightAnchor.constraint(equalToConstant: 236),
        ])
        hosting.didMove(toParent: self)
        self.hosting = hosting
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        HostAppResolver.keyboardWillAppear()
        model.appeared()
        dictionaryOffer.appeared(hasFullAccess: hasFullAccess)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // The host connection exists now, so the globe answer is reliable.
        model.refreshHostTraits()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        model.disappeared()
        dictionaryOffer.disappeared()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        HostAppResolver.harvest()
        dictionaryOffer.selectionChanged()
    }

    override func selectionDidChange(_ textInput: UITextInput?) {
        super.selectionDidChange(textInput)
        HostAppResolver.harvest()
        dictionaryOffer.selectionChanged()
    }

    /// Opens a URL from inside the extension. `UIApplication.open` is marked
    /// unavailable to extensions at compile time but works at runtime, so it
    /// is reached through the responder chain. `extensionContext.open` is the
    /// documented call but returns false for keyboards on current iOS.
    func openURL(_ url: URL) {
        let selector = NSSelectorFromString("openURL:options:completionHandler:")
        var responder: UIResponder? = self
        while let current = responder {
            if current is UIApplication, current.responds(to: selector), let method = current.method(for: selector) {
                typealias OpenURL = @convention(c) (AnyObject, Selector, NSURL, NSDictionary, AnyObject?) -> Void
                unsafeBitCast(method, to: OpenURL.self)(current, selector, url as NSURL, NSDictionary(), nil)
                return
            }
            responder = current.next
        }
        extensionContext?.open(url, completionHandler: nil)
    }
}
