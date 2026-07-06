// SPDX-FileCopyrightText: Nextcloud GmbH
// SPDX-FileCopyrightText: 2024 Milen Pivchev
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import Perception

struct NCAssistantEmptyView: View {
    @Environment(NCAssistantModel.self) var assistantModel
    let titleKey, subtitleKey: String

    var body: some View {
        WithPerceptionTracking {
        VStack {
            Image(systemName: "sparkles")
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(Color(NCBrandColor.shared.getElement(account: assistantModel.controller?.account)))
                .font(Font.system(.body).weight(.light))
                .frame(height: 100)

            Text(NSLocalizedString(titleKey, comment: ""))
                .cappedFont(.body, maxDynamicType: .accessibility2)
                .adaptiveFontWeight(.bold)
                .padding(.bottom, 5)

            Text(NSLocalizedString(subtitleKey, comment: ""))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        } // WithPerceptionTracking
    }
}

#Preview {
    if #available(iOS 17, *) {
        NCAssistantEmptyView(titleKey: "_no_tasks_", subtitleKey: "_create_task_subtitle_")
    }
}
