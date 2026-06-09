//
//  AboutView.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/5/30.
//

import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                Text(AppConstants.appName)
                    .font(.system(size: 16, weight: .semibold))
                Text("Version \(AppConstants.shortVersion) (\(AppConstants.buildNumber))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(AppConstants.gitCommit)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                infoRow(label: "Author") {
                    Text(AppConstants.author)
                }
                infoRow(label: "Source") {
                    if let url = AppConstants.githubURL {
                        Link(destination: url) {
                            HStack(spacing: 4) {
                                Text(url.host.map { $0 + url.path } ?? AppConstants.githubURLString)
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 9))
                            }
                        }
                    }
                }
                infoRow(label: "License") {
                    Text(AppConstants.license)
                }
            }

            Divider()

            Text("© 2026 \(AppConstants.appName)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(20)
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func infoRow<Content: View>(
        label: LocalizedStringKey,
        @ViewBuilder value: () -> Content
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.callout)
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)
            value()
                .font(.callout)
            Spacer(minLength: 0)
        }
    }
}
