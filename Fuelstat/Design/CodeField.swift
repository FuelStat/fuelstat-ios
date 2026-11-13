import SwiftUI

/// Six separate digit boxes for a 2FA code, with auto-advance, paste support and one-time-code autofill.
///
/// One hidden text field holds the code, so autofill, paste and deleting work like in any text field; the boxes
/// only show its digits.
struct CodeField: View {
    @Binding var code: String
    var length = 6
    var onComplete: (() -> Void)?

    @FocusState private var isFocused: Bool
    @ScaledMetric(relativeTo: .title) private var boxHeight: CGFloat = 56

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            boxes
            // The boxes cover the hidden field, so its paste menu is out of reach: offer pasting explicitly.
            // PasteButton reads the clipboard without the system's permission prompt.
            PasteButton(payloadType: String.self) { strings in
                guard let text = strings.first else { return }
                code = String(text.filter(\.isNumber).prefix(length))
            }
            .buttonBorderShape(.capsule)
            .labelStyle(.titleAndIcon)
            .tint(Theme.brand)
        }
    }

    private var boxes: some View {
        ZStack {
            TextField("", text: $code)
                .textContentType(.oneTimeCode)
                .keyboardType(.numberPad)
                .focused($isFocused)
                .opacity(0.02)
                .accessibilityLabel(Text("Bestätigungscode, \(length) Ziffern"))
                .accessibilityValue(Text(code.map(String.init).joined(separator: " ")))
                .onChange(of: code) {
                    let digits = String(code.filter(\.isNumber).prefix(length))
                    if digits != code { code = digits }
                    if digits.count == length { onComplete?() }
                }

            HStack(spacing: Theme.Spacing.xs) {
                ForEach(0..<length, id: \.self) { index in
                    box(at: index)
                }
            }
            .accessibilityHidden(true)
            .contentShape(.rect)
            .onTapGesture { isFocused = true }
        }
        .onAppear { isFocused = true }
    }

    private func box(at index: Int) -> some View {
        let characters = Array(code)
        let digit = index < characters.count ? String(characters[index]) : ""
        let isCurrent = isFocused && index == min(characters.count, length - 1)
        return Text(digit)
            .font(.title.bold())
            .fontDesign(.rounded)
            .monospacedDigit()
            .foregroundStyle(Theme.brandDeep)
            .frame(maxWidth: .infinity, minHeight: boxHeight)
            .background(Theme.card, in: .tile)
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                    .strokeBorder(isCurrent ? Theme.brand : Color.secondary.opacity(0.35),
                                  lineWidth: isCurrent ? 2 : 1)
            }
    }
}

#Preview {
    @Previewable @State var code = "123"
    PreviewVariants {
        CodeField(code: $code)
    }
}
