import SwiftUI

struct HomeView: View {
    
    @ObservedObject var viewModel = HomeViewModel()
    
    var body: some View {
        VStack {
            Spacer()
            Text("Generated Log: \(viewModel.resentEvent?.value ?? 0)")
            Text("Generated Time Interval: \(viewModel.resentEvent?.timestamp.formatted() ?? "00:00:00")")
            Spacer()
        }
        .onAppear(perform: onAppear)
        .onDisappear(perform: onDisappear)
    }
    
    func onAppear() {
        viewModel.startService()
    }
    
    func onDisappear() {
        viewModel.stopService()
    }
}
