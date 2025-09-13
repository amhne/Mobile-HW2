import Foundation
import FoundationNetworking

struct CreateGameResponse: Codable {
    let game_id: String
}

struct GuessRequest: Codable {
    let game_id: String
    let guess: String
}

struct GuessResponse: Codable {
    let black: Int
    let white: Int
}

struct ErrorResponse: Codable {
    let error: String
}

class MastermindGame {
    let baseURL = "https://mastermind.darkube.app"
    var gameId: String?
    let exitSemaphore = DispatchSemaphore(value: 0)

    func start() {
        DispatchQueue.global().async {
            while true {
                print("Welcome to Mastermind! Type your guess (4 digits between 1-6), 'delete' to delete game, or 'exit' to quit.")
                let semaphore = DispatchSemaphore(value: 0)
                self.createGame { success, errorMessage in
                    if !success {
                        print("Error: \(errorMessage ?? "Unknown error")")
                        exit(1)
                    }
                    semaphore.signal()
                }
                semaphore.wait()

                if !self.gameLoop() {
                    break
                }
            }
            self.exitSemaphore.signal()
        }
        exitSemaphore.wait()
    }

    private func gameLoop() -> Bool {
        guard let gameId = gameId else { return false }
        while true {
            print("Enter your guess:")
            guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else { continue }

            if input == "exit" {
                print("Exiting game.")
                return false
            }

            if input == "delete" {
                let semaphore = DispatchSemaphore(value: 0)
                deleteGame(gameId: gameId) { success, errorMessage in
                    if success {
                        print("Game deleted.")
                    } else {
                        print("Error: \(errorMessage ?? "Unknown error")")
                    }
                    semaphore.signal()
                }
                semaphore.wait()
                self.gameId = nil

                print("Do you want to start a new game? (y/n):")
                guard let answer = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
                    return false
                }
                if answer == "y" {
                    return true
                } else {
                    return false
                }
            }

            let semaphore = DispatchSemaphore(value: 0)
            var guessSuccess = false
            var guessResponse: GuessResponse?
            var guessErrorMessage: String?

            sendGuess(gameId: gameId, guess: input) { success, response, errorMessage in
                guessSuccess = success
                guessResponse = response
                guessErrorMessage = errorMessage
                semaphore.signal()
            }
            semaphore.wait()

            if guessSuccess, let response = guessResponse {
                let blackStr = String(repeating: "B", count: response.black)
                let whiteStr = String(repeating: "W", count: response.white)
                print("Result: \(blackStr)\(whiteStr)")
                if response.black == 4 {
                    print("Congratulations! You won!")
                    print("Do you want to play again? (y/n):")
                    guard let answer = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
                        return false
                    }
                    if answer == "y" {
                        return true
                    } else {
                        return false
                    }
                }
            } else {
                print("Error: \(guessErrorMessage ?? "Unknown error")")
            }
        }
    }

    private func createGame(completion: @escaping (Bool, String?) -> Void) {
        guard let url = URL(string: "\(baseURL)/game") else {
            completion(false, "Invalid URL")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        URLSession.shared.dataTask(with: request) { data, response, error in
            if error != nil {
                completion(false, "network error")
                return
            }
            if let httpResp = response as? HTTPURLResponse, !(200...299).contains(httpResp.statusCode) {
                if let data = data, let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                    completion(false, errorResponse.error)
                } else {
                    completion(false, "HTTP error: \(httpResp.statusCode)")
                }
                return
            }
            guard let data = data else {
                completion(false, "No data received")
                return
            }
            if let createResponse = try? JSONDecoder().decode(CreateGameResponse.self, from: data) {
                self.gameId = createResponse.game_id
                completion(true, nil)
            } else if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                completion(false, errorResponse.error)
            } else {
                completion(false, "Failed to decode response")
            }
        }.resume()
    }

    private func sendGuess(gameId: String, guess: String, completion: @escaping (Bool, GuessResponse?, String?) -> Void) {
        guard let url = URL(string: "\(baseURL)/guess") else {
            completion(false, nil, "Invalid URL")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let guessRequest = GuessRequest(game_id: gameId, guess: guess)
        guard let jsonData = try? JSONEncoder().encode(guessRequest) else {
            completion(false, nil, "Failed to encode guess")
            return
        }
        request.httpBody = jsonData
        URLSession.shared.dataTask(with: request) { data, response, error in
            if error != nil {
                completion(false, nil, "network error")
                return
            }
            if let httpResp = response as? HTTPURLResponse, !(200...299).contains(httpResp.statusCode) {
                if let data = data, let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                    completion(false, nil, errorResponse.error)
                } else {
                    completion(false, nil, "HTTP error: \(httpResp.statusCode)")
                }
                return
            }
            guard let data = data else {
                completion(false, nil, "No data received")
                return
            }
            if let guessResponse = try? JSONDecoder().decode(GuessResponse.self, from: data) {
                completion(true, guessResponse, nil)
            } else if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                completion(false, nil, errorResponse.error)
            } else {
                completion(false, nil, "Failed to decode response")
            }
        }.resume()
    }

    private func deleteGame(gameId: String, completion: @escaping (Bool, String?) -> Void) {
        guard let url = URL(string: "\(baseURL)/game/\(gameId)") else {
            completion(false, "Invalid URL")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        URLSession.shared.dataTask(with: request) { _, response, error in
            if error != nil {
                completion(false, "network error")
                return
            }
            if let httpResp = response as? HTTPURLResponse {
                if httpResp.statusCode == 204 {
                    completion(true, nil)
                } else {
                    completion(false, "HTTP error: \(httpResp.statusCode)")
                }
            } else {
                completion(false, "Invalid response")
            }
        }.resume()
    }
}

let game = MastermindGame()
game.start()
