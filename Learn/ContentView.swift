import SwiftUI

struct ContentView: View {
    @State private var responseText = "Press the button to fetch data"

    var body: some View {
        VStack(spacing: 20) {
            ScrollView {
                Text(responseText)
                    .padding()
            }

            Button(action: {
                fetchData()
            }) {
                Text("Fetch Data")
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding()
        }
    }

    func fetchData() {
        guard let url = URL(string: "https://journal.h4nk.com/api/ping") else {
            responseText = "Invalid URL"
            return
        }

        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    responseText = "Error: \(error.localizedDescription)"
                }
                return
            }

            guard let data = data else {
                DispatchQueue.main.async {
                    responseText = "No data received"
                }
                return
            }

            if let text = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    responseText = text
                }
            } else {
                DispatchQueue.main.async {
                    responseText = "Unable to decode response"
                }
            }
        }

        task.resume()
    }
}
