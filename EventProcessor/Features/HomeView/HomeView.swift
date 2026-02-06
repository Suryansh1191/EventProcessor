import SwiftUI

struct HomeView: View {
    
    @ObservedObject var viewModel = HomeViewModel()
    
    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [
                    Color.black,
                    Color.purple.opacity(0.8),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 4) {
                    Text("Event Processor")
                        .font(.largeTitle.weight(.bold))
                        .foregroundColor(.white)
                    Text("Live random events and LLM insights")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                }
                
                // Status pill
                HStack(spacing: 8) {
                    Circle()
                        .fill(viewModel.processingLogs ? Color.green : Color.gray)
                        .frame(width: 10, height: 10)
                    Text(viewModel.processingLogs ? "Processing logs" : "Idle")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.9))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                
                // Content cards
                VStack(spacing: 16) {
                    // Latest event card
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Latest Event")
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        if let event = viewModel.resentEvent {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Value")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.6))
                                    Text("\(event.value)")
                                        .font(.title2.weight(.semibold))
                                        .foregroundColor(.white)
                                }
                                
                                Spacer()
                                
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text("Timestamp")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.6))
                                    Text(event.timestamp.formatted(date: .omitted, time: .standard))
                                        .font(.body)
                                        .foregroundColor(.white)
                                }
                            }
                        } else {
                            Text("Waiting for first event…")
                                .font(.body)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    
                    // LLM output card
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Latest LLM Output")
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        ScrollView {
                            Text(viewModel.resentLLMOutput)
                                .font(.body)
                                .foregroundColor(.white.opacity(0.9))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(minHeight: 80, maxHeight: 160)
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .padding(.top, 32)
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
