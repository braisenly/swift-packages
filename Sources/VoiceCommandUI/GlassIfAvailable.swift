//
//  GlassIfAvailable.swift
//  playground
//
//  Liquid Glass on iOS 26 / macOS 26 and later, a material fallback on the
//  18.2 / 15 deployment targets. Keeps call sites flat: `.glassIfAvailable()`.
//

import SwiftUI

struct GlassIfAvailable: ViewModifier {
    var cornerRadius: CGFloat = 12

    func body(content: Content) -> some View {
        if #available(iOS 26, macOS 26, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            content.background(.thinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}

extension View {
    func glassIfAvailable(cornerRadius: CGFloat = 12) -> some View {
        modifier(GlassIfAvailable(cornerRadius: cornerRadius))
    }
}
