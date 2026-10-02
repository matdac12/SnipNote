import SwiftUI

struct CloudTranscriptionProviderPickerView: View {
  @EnvironmentObject private var themeManager: ThemeManager
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Binding var selectedProvider: CloudTranscriptionProvider

  var body: some View {
    let layout = dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(spacing: 12))
      : AnyLayout(HStackLayout(spacing: 12))

    layout {
      ForEach(CloudTranscriptionProvider.allCases) { provider in
        providerCard(provider)
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("settings.cloudTranscription.provider")
  }

  private func providerCard(_ provider: CloudTranscriptionProvider) -> some View {
    let theme = themeManager.currentTheme
    let isSelected = selectedProvider == provider

    return Button {
      selectedProvider = provider
    } label: {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Spacer(minLength: 0)
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(theme.accentColor)
            .opacity(isSelected ? 1 : 0)
            .accessibilityHidden(true)
        }
        Text(provider.displayName)
          .font(.body)
          .bold()
          .foregroundStyle(theme.textColor)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(12)
      .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
      .background {
        RoundedRectangle(cornerRadius: theme.cornerRadius)
          .fill(isSelected ? theme.accentColor.opacity(0.1) : theme.secondaryBackgroundColor)
      }
      .overlay {
        RoundedRectangle(cornerRadius: theme.cornerRadius)
          .strokeBorder(isSelected ? theme.accentColor : theme.secondaryTextColor.opacity(0.2), lineWidth: 1)
      }
      .contentShape(RoundedRectangle(cornerRadius: theme.cornerRadius))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(provider.displayName)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
    .accessibilityIdentifier("settings.cloudTranscription.provider.\(provider.rawValue)")
  }
}
