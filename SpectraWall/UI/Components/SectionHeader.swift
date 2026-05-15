//
//  SectionHeader.swift
//  SpectraWall
//
//  Created by Giggs Lynx on 2026/4/26.
//

import SwiftUI

struct SectionHeader: View {
    let title: LocalizedStringKey
    var imageName: String? = nil
    var systemImageName: String? = nil
    var imageIsTemplate: Bool = false
    var imageColor: Color = .secondary

    var body: some View {
        HStack(spacing: 5) {
            Group {
                if let systemImageName {
                    Image(systemName: systemImageName)
                        .font(.system(size: 13))
                        .foregroundColor(imageColor)
                } else if let imageName {
                    Image(imageName)
                        .renderingMode(imageIsTemplate ? .template : .original)
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(imageIsTemplate ? .secondary : nil)
                }
            }
            .frame(width: 20, height: 20)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }
}
