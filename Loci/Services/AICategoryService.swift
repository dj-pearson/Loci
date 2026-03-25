import Foundation

enum AICategoryService {

    private static let categoryKeywords: [LocusCategory: [String]] = [
        .food: ["grocery", "restaurant", "eat", "cook", "dinner", "lunch", "breakfast", "recipe", "kitchen", "food"],
        .shopping: ["buy", "price", "sale", "store", "shop", "purchase", "deal", "discount", "mall", "market"],
        .parking: ["park", "lot", "garage", "meter", "parking", "valet", "spot"],
        .health: ["doctor", "pharmacy", "dentist", "hospital", "clinic", "medicine", "prescription", "appointment", "health"],
        .travel: ["hotel", "airport", "flight", "trip", "travel", "vacation", "resort", "booking", "terminal"],
        .tip: ["try", "recommend", "good", "best", "great", "awesome", "amazing", "favorite", "suggestion"],
        .warning: ["avoid", "careful", "don't", "bad", "terrible", "awful", "dangerous", "sketchy", "worst", "broken"],
        .home: ["plumber", "contractor", "repair", "fix", "renovate", "maintenance", "electrician", "leak", "install"],
        .outdoor: ["trail", "hike", "camp", "fish", "kayak", "climb", "nature", "mountain", "lake", "river"],
    ]

    static func categorize(transcription: String) -> LocusCategory {
        let lowercased = transcription.lowercased()
        let words = tokenize(lowercased)

        var bestCategory: LocusCategory = .general
        var bestCount = 0

        for (category, keywords) in categoryKeywords {
            let matchCount = keywords.reduce(0) { count, keyword in
                count + (words.contains(keyword) ? 1 : 0)
            }

            if matchCount >= 2 && matchCount > bestCount {
                bestCount = matchCount
                bestCategory = category
            }
        }

        return bestCategory
    }

    private static func tokenize(_ text: String) -> Set<String> {
        let scalars = text.unicodeScalars
        var words = Set<String>()
        var current = ""

        for scalar in scalars {
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "'" {
                current.append(Character(scalar))
            } else {
                if !current.isEmpty {
                    words.insert(current)
                    current = ""
                }
            }
        }
        if !current.isEmpty {
            words.insert(current)
        }

        return words
    }
}
