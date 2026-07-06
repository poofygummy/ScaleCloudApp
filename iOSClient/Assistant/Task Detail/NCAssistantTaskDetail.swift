//
//  NCAssistantTaskDetail.swift
//  Nextcloud
//
//  Created by Milen on 10.04.24.
//  Copyright © 2024 Marino Faggiana. All rights reserved.
//

import SwiftUI
import ScaleCloudKit
import Perception

struct NCAssistantTaskDetail: View {
    @Environment(NCAssistantModel.self) var assistantModel
    let task: AssistantTask

    var body: some View {
        WithPerceptionTracking {
        ZStack(alignment: .bottom) {
            InputOutputScrollView(task: task)

            BottomDetailsBar(task: task)
        }
        .toolbar {
            Button(action: {
                assistantModel.shareTask(task)
            }, label: {
                Image(systemName: "square.and.arrow.up")
            })
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(NSLocalizedString("_task_details_", comment: ""))
        .onAppear {
            assistantModel.selectTask(task)
        }
        } // WithPerceptionTracking
    }
}

#Preview {
    if #available(iOS 17, *) {
        let assistantModel = NCAssistantModel(controller: nil, inputModel: NCAssistantInputModel())
        NCAssistantTaskDetail(task: assistantModel.selectedTask!)
            .environment(assistantModel)
            .onAppear { assistantModel.loadDummyData() }
    }
}

struct InputOutputScrollView: View {
    @Environment(NCAssistantModel.self) var model
    let task: AssistantTask

    var body: some View {
        WithPerceptionTracking {
        ScrollView {
            VStack(alignment: .leading) {
                Text(NSLocalizedString("_input_", comment: ""))
                    .font(.headline)
                    .padding(.top, 10)

                Text(model.selectedTask?.input?.input ?? "")
                    .cappedFont(.body, maxDynamicType: .accessibility2)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding()
                    .background(Color(NCBrandColor.shared.textColor2).opacity(0.1))
                    .clipShape(.rect(cornerRadius: 8))
                    .textSelection(.enabled)

                Text(NSLocalizedString("_output_", comment: ""))
                    .font(.headline)
                    .padding(.top, 10)

                Text(model.selectedTask?.output?.output ?? "")
                    .cappedFont(.body, maxDynamicType: .accessibility2)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding()
                    .background(Color(NCBrandColor.shared.textColor2).opacity(0.1))
                    .clipShape(.rect(cornerRadius: 8))
                    .textSelection(.enabled)
            }
            .padding(.horizontal)
            .padding(.bottom, 80)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } // WithPerceptionTracking
    }
}

struct BottomDetailsBar: View {
    @Environment(NCAssistantModel.self) var assistantModel
    let task: AssistantTask

    var body: some View {
        WithPerceptionTracking {
        VStack(spacing: 0) {
            Divider()

            HStack {
                StatusInfo(task: task, showStatusText: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.bar)
                    .frame(alignment: .bottom)
            }
        }
        } // WithPerceptionTracking
    }
}
