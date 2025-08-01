// MARK: - CosmicScoutDataFetcher.swift
import Foundation
import CoreLocation
import Combine

enum CosmicScoutError: Error, LocalizedError {
    case networkError(Error)
    case decodingError(Error)
    case apiError(String)
    case invalidURL
    case locationError(String)
    case noDataReceived(String)

    var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Data decoding error: \(error.localizedDescription)"
        case .apiError(let message):
            return "API error: \(message)"
        case .invalidURL:
            return "Invalid URL constructed."
        case .locationError(let message):
            return "Location error: \(message)"
        case .noDataReceived(let message):
            return message
        }
    }
}

class CosmicScoutDataFetcher: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = CosmicScoutDataFetcher()

    // MARK: - API Keys
    private let newsAPIKey: String = {
        guard let path = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path),
              let key = dict["NEWS_API_KEY"] as? String else {
            fatalError("NEWS_API_KEY not found in Secrets.plist")
        }
        return key
    }()

    private let n2yoAPIKey: String = {
        guard let path = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path),
              let key = dict["N2YO_API_KEY"] as? String else {
            fatalError("N2YO_API_KEY not found in Secrets.plist")
        }
        return key
    }()

    // MARK: - Location Manager
    private let locationManager = CLLocationManager()
    private var locationCompletion: ((CLLocation?, Error?) -> Void)?

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    // MARK: - Location Methods
    func requestLocation(completion: @escaping (CLLocation?, Error?) -> Void) {
        self.locationCompletion = completion
        switch locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.requestLocation()
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            completion(nil, CosmicScoutError.locationError("Location access denied or restricted. Please enable in Settings."))
        @unknown default:
            completion(nil, CosmicScoutError.locationError("Unknown location authorization status."))
        }
    }

    // CLLocationManagerDelegate Methods
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            locationCompletion?(nil, CosmicScoutError.locationError("Location access denied or restricted."))
            locationCompletion = nil
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.first {
            locationCompletion?(location, nil)
            locationCompletion = nil
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location manager failed with error: \(error.localizedDescription)")
        locationCompletion?(nil, CosmicScoutError.locationError("Failed to get location: \(error.localizedDescription)"))
        locationCompletion = nil
    }

    // MARK: - News API Fetching
    func fetchSpaceNews(query: String? = nil, fetchForProactiveCheck: Bool = false, fromDate: Date? = nil, completion: @escaping ([SpaceEvent]?, Error?) -> Void) {
        var urlComponents = URLComponents(string: "https://newsapi.org/v2/everything")!

        var queryItems = [
            URLQueryItem(name: "q", value: query ?? "space OR astronomy OR NASA OR SpaceX OR rocket launch OR cosmic OR universe"),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "sortBy", value: "publishedAt"),
            URLQueryItem(name: "pageSize", value: "10"),
            URLQueryItem(name: "apiKey", value: newsAPIKey)
        ]

        if fetchForProactiveCheck, let date = fromDate ?? Calendar.current.date(byAdding: .day, value: -1, to: Date()) {
            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            queryItems.append(URLQueryItem(name: "from", value: dateFormatter.string(from: date)))
        }

        urlComponents.queryItems = queryItems

        guard let url = urlComponents.url else {
            completion(nil, CosmicScoutError.invalidURL)
            return
        }

        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                completion(nil, CosmicScoutError.networkError(error))
                return
            }

            guard let data = data else {
                completion(nil, CosmicScoutError.noDataReceived("No data received from News API."))
                return
            }

            do {
                let decoder = JSONDecoder()
                let apiResponse = try decoder.decode(NewsAPIResponse.self, from: data)

                if apiResponse.status == "ok", let articles = apiResponse.articles {
                    let spaceEvents = articles.compactMap { article -> SpaceEvent? in
                        guard let articleURL = URL(string: article.url) else {
                            return nil
                        }
                        
                        let dateFormatter = ISO8601DateFormatter()
                        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

                        var publishedDate: Date?
                        if let date = dateFormatter.date(from: article.publishedAt) {
                            publishedDate = date
                        } else {
                            dateFormatter.formatOptions = [.withInternetDateTime]
                            publishedDate = dateFormatter.date(from: article.publishedAt)
                        }

                        guard let finalPublishedDate = publishedDate else {
                            return nil
                        }

                        let lowercasedTitle = article.title.lowercased()
                        let lowercasedDescription = (article.description ?? "").lowercased()

                        let keywords = ["space", "astronomy", "nasa", "spacex", "rocket", "launch", "cosmic", "universe", "galaxy", "planet", "star", "mission", "telescope", "iss", "moon", "mars", "jupiter", "satellite", "orbital", "celestial", "black hole", "exoplanet"]

                        let isRelevant = keywords.contains(where: { lowercasedTitle.contains($0) || lowercasedDescription.contains($0) })

                        if !isRelevant {
                            return nil
                        }

                        let newSpaceEvent = SpaceEvent(
                            title: article.title,
                            description: article.description,
                            date: finalPublishedDate,
                            sourceURL: articleURL,
                            type: "News",
                            sourceName: article.source.name
                        )
                        return newSpaceEvent
                    }
                    completion(spaceEvents, nil)
                } else if apiResponse.status == "error", let message = apiResponse.message {
                    completion(nil, CosmicScoutError.apiError("News API Error: \(message)"))
                } else {
                    completion(nil, CosmicScoutError.apiError("Unknown News API response status."))
                }
            } catch {
                completion(nil, CosmicScoutError.decodingError(error))
            }
        }.resume()
    }

    // MARK: - N2YO API Fetching (Satellite Flyovers)
    func fetchSatelliteFlyovers(noradID: Int? = nil, completion: @escaping ([SatellitePass]?, Error?) -> Void) {
        requestLocation { [weak self] location, error in
            guard let self = self else { return }

            if let error = error {
                completion(nil, CosmicScoutError.locationError("Failed to get location for satellite data: \(error.localizedDescription)"))
                return
            }
            guard let lat = location?.coordinate.latitude, let lon = location?.coordinate.longitude else {
                completion(nil, CosmicScoutError.locationError("Location not available for satellite data."))
                return
            }

            let defaultNoradID = 25544 // ISS Norad ID
            let satelliteID = noradID ?? defaultNoradID
            let days = 3 // Look for passes in the next 3 days
            let minElevation = 10 // Minimum elevation in degrees for visibility

            let urlString = "https://api.n2yo.com/rest/v1/satellite/visualpasses/\(satelliteID)/\(lat)/\(lon)/\(minElevation)/\(days)/&apiKey=\(self.n2yoAPIKey)"

            guard let url = URL(string: urlString) else {
                completion(nil, CosmicScoutError.invalidURL)
                return
            }

            URLSession.shared.dataTask(with: url) { data, response, error in
                if let error = error {
                    completion(nil, CosmicScoutError.networkError(error))
                    return
                }

                guard let data = data else {
                    completion(nil, CosmicScoutError.noDataReceived("No data received from N2YO API."))
                    return
                }

                do {
                    let decoder = JSONDecoder()
                    if let errorResponse = try? decoder.decode(N2YOErrorResponse.self, from: data), let errorMessage = errorResponse.error {
                        completion(nil, CosmicScoutError.apiError("N2YO API Error: \(errorMessage)"))
                        return
                    }

                    let apiResponse = try decoder.decode(N2YOPassResponse.self, from: data)

                    if let n2yoPasses = apiResponse.passes {
                        let passes = n2yoPasses.map { n2yoPass -> SatellitePass in
                            return SatellitePass(
                                startAz: n2yoPass.startAz,
                                startAzCompass: n2yoPass.startAzCompass,
                                startEl: n2yoPass.startEl,
                                startUTC: n2yoPass.startUTC,
                                maxAz: n2yoPass.maxAz,
                                maxAzCompass: n2yoPass.maxAzCompass,
                                maxEl: n2yoPass.maxEl,
                                maxUTC: n2yoPass.maxUTC,
                                endAz: n2yoPass.endAz,
                                endAzCompass: n2yoPass.endAzCompass,
                                endEl: n2yoPass.endEl,
                                endUTC: n2yoPass.endUTC,
                                mag: n2yoPass.mag,
                                duration: n2yoPass.duration,
                                startVisibility: n2yoPass.startVisibility,
                                satelliteName: apiResponse.info.satname, // Include satellite name
                                direction: "From \(n2yoPass.startAzCompass) to \(n2yoPass.endAzCompass)" // Include direction
                            )
                        }
                        completion(passes, nil)
                    } else {
                        completion([], nil)
                    }
                } catch {
                    print("N2YO Decoding Error: \(error.localizedDescription)")
                    completion(nil, CosmicScoutError.decodingError(error))
                }
            }.resume()
        }
    }
}
