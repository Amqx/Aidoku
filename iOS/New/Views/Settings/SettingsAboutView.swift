//
//  SettingsAboutView.swift
//  Aidoku
//
//  Created by Skitty on 9/19/25.
//

import SwiftUI

struct SettingsAboutView: View {
    @State private var showCommitSafari = false

    private static let repoUrl = "https://github.com/Amqx/Aidoku"

    // the build phase writes the short hash here, with a "-dirty" suffix for uncommitted changes
    private var commitHash: String? {
        let hash = Bundle.main.infoDictionary?["GitCommitHash"] as? String
        guard let hash, !hash.isEmpty, hash != "unknown" else { return nil }
        return hash
    }

    private var commitUrl: URL? {
        guard let commitHash else { return nil }
        // a dirty build doesn't match the commit exactly, but the parent commit is still the useful link
        let hash = commitHash.replacingOccurrences(of: "-dirty", with: "")
        return URL(string: "\(Self.repoUrl)/commit/\(hash)")
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Text(NSLocalizedString("VERSION"))
                    Spacer()
                    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
                    ?? NSLocalizedString("UNKNOWN")
                    Text(version)
                        .foregroundStyle(.secondary)
                }

                if let commitHash {
                    Button {
                        showCommitSafari = true
                    } label: {
                        HStack {
                            Text(NSLocalizedString("COMMIT"))
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(commitHash)
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .fullScreenCover(isPresented: $showCommitSafari) {
                        SafariView(url: .constant(commitUrl))
                            .ignoresSafeArea()
                    }
                } else {
                    HStack {
                        Text(NSLocalizedString("COMMIT"))
                        Spacer()
                        Text(NSLocalizedString("UNKNOWN"))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                SettingView(setting: .init(
                    title: NSLocalizedString("GITHUB_REPO"),
                    value: .link(.init(url: Self.repoUrl))
                ))
            }
        }
        .navigationTitle(NSLocalizedString("ABOUT"))
    }
}
