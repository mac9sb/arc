import Foundation

/// Generates Docker-style random names for arc processes.
///
/// Combines two words (adjective + noun) to create memorable, unique identifiers.
/// Examples: mellow-falcon, bright-lighthouse, happy-otter.
public struct ProcessNameGenerator {
    /// Adjectives for name generation.
    private static let adjectives = [
        "admiring", "adoring", "affectionate", "agitated", "amazing", "angry", "awesome",
        "beautiful", "blissful", "bold", "brave", "busy", "calm", "charming", "clever",
        "cool", "compassionate", "competent", "confident", "dazzling", "determined",
        "devoted", "diligent", "dreamy", "eager", "ecstatic", "energetic", "enlightened",
        "enthusiastic", "excited", "extraordinary", "fancy", "fantastic", "festive",
        "flamboyant", "focused", "friendly", "funny", "generous", "gentle", "genuine",
        "gifted", "happy", "hardworking", "helpful", "hilarious", "hopeful", "humble",
        "hungry", "idealistic", "incredible", "inquisitive", "inspiring", "jolly",
        "joyful", "jubilant", "kind", "knowledgeable", "laughing", "loving", "loyal",
        "lucky", "marvelous", "merry", "modest", "mystical", "mystifying", "naughty",
        "nice", "noble", "obedient", "optimistic", "peaceful", "perfect", "playful",
        "pleasant", "plucky", "powerful", "proud", "quirky", "radiant", "rational",
        "reliable", "remarkable", "resilient", "respectful", "responsible", "romantic",
        "satisfied", "selfless", "sensible", "serene", "sharp", "silly", "smart",
        "spirited", "splendid", "spontaneous", "steadfast", "stoic", "stunning",
        "stylish", "successful", "surprising", "suspicious", "sweet", "talented",
        "thoughtful", "thrifty", "thunderous", "tidy", "tired", "tranquil",
        "trustworthy", "ultimate", "unassuming", "unique", "upbeat", "vigilant",
        "vigorous", "virtuous", "vivacious", "warm", "whimsical", "whispering",
        "wise", "witty", "wonderful", "youthful", "zealous", "zen",
    ]

    /// Nouns for name generation.
    private static let nouns = [
        "aardvark", "alligator", "alpaca", "ant", "antelope", "ape", "armadillo", "asp",
        "baboon", "badger", "barracuda", "bat", "bear", "beaver", "bee", "beetle", "bison",
        "boa", "boar", "buffalo", "butterfly", "camel", "canary", "capybara", "carp",
        "cat", "caterpillar", "catfish", "centipede", "chameleon", "cheetah", "chicken",
        "chimpanzee", "cicada", "clam", "cobra", "cod", "condor", "coral", "cougar", "cow",
        "coyote", "crab", "crane", "cricket", "crocodile", "crow", "deer", "dingo", "dinosaur",
        "dog", "dolphin", "donkey", "dove", "dragon", "dragonfly", "duck", "eagle",
        "earwig", "echidna", "eel", "elephant", "elk", "emu", "falcon", "ferret", "finch",
        "fish", "flamingo", "fly", "fox", "frog", "galago", "gazelle", "gecko", "giraffe",
        "goat", "goldfish", "goose", "gorilla", "grasshopper", "grouse", "guinea_fowl",
        "gull", "hamster", "hare", "hawk", "hedgehog", "hermit_crab", "heron", "hippopotamus",
        "hornet", "horse", "human", "hummingbird", "hyena", "iguana", "impala", "jackal",
        "jaguar", "jellyfish", "kangaroo", "kitten", "koala", "ladybug", "lamprey", "lemming",
        "lemur", "leopard", "lion", "lizard", "llama", "lobster", "locust", "louse", "lynx",
        "macaw", "maggot", "magpie", "mallard", "manatee", "marten", "meerkat", "mink",
        "minnow", "mole", "mongoose", "monkey", "moose", "mosquito", "moth", "mouse",
        "mule", "muskrat", "narwhal", "newt", "nightingale", "octopus", "opossum", "oryx",
        "ostrich", "otter", "owl", "ox", "oyster", "panda", "panther", "parrot", "partridge",
        "peacock", "pelican", "penguin", "pheasant", "pig", "pigeon", "pika", "pike",
        "platypus", "porcupine", "porpoise", "prawn", "pronghorn", "puffin", "puma",
        "python", "quail", "rabbit", "raccoon", "rat", "rattlesnake", "raven", "reindeer",
        "rhinoceros", "roadrunner", "robin", "salamander", "salmon", "sawfish", "scorpion",
        "seahorse", "seal", "sea_urchin", "shark", "sheep", "shrew", "skunk", "sloth",
        "snail", "snake", "sparrow", "spider", "squid", "squirrel", "starfish", "stork",
        "swallow", "swan", "swift", "swordfish", "tapir", "tarantula", "termite", "tiger",
        "toad", "tortoise", "toucan", "trout", "turkey", "turtle", "unicorn", "viper",
        "vole", "vulture", "wallaby", "walrus", "wasp", "weasel", "whale", "whippet",
        "wombat", "woodchuck", "woodpecker", "worm", "wren", "yak", "zebra", "zebra_finch",
    ]

    /// Generates a random Docker-style process name.
    ///
    /// - Returns: A random name in the format "adjective-noun".
    public static func generate() -> String {
        let adjective = adjectives.randomElement() ?? "happy"
        let noun = nouns.randomElement() ?? "panda"
        return "\(adjective)-\(noun)"
    }

    /// Generates a random name that doesn't conflict with existing names.
    ///
    /// - Parameter existingNames: Set of names already in use.
    /// - Returns: A unique random name not in the existing set.
    public static func generateUnique(excluding existingNames: Set<String>) -> String {
        var attempts = 0
        let maxAttempts = 100

        while attempts < maxAttempts {
            let name = generate()
            if !existingNames.contains(name) {
                return name
            }
            attempts += 1
        }

        // Fallback to timestamp-based name if all random names are taken
        return "arc-\(Int(Date().timeIntervalSince1970))"
    }

    /// Validates whether a process name is valid.
    ///
    /// Valid names must:
    /// - Be 2-63 characters long
    /// - Contain only lowercase letters, numbers, and hyphens
    /// - Start and end with a letter or number
    ///
    /// - Parameter name: The name to validate.
    /// - Returns: `true` if the name is valid, `false` otherwise.
    public static func isValid(name: String) -> Bool {
        let nameRegex = "^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$"
        return name.range(of: nameRegex, options: .regularExpression) != nil
    }

    /// Sanitizes a user-provided process name to make it valid.
    ///
    /// - Parameter name: The name to sanitize.
    /// - Returns: A sanitized version of the name, or a random name if sanitization fails.
    public static func sanitize(name: String) -> String {
        // Convert to lowercase and replace invalid characters with hyphens
        var sanitized =
            name
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]", with: "-", options: .regularExpression)
            .replacingOccurrences(of: "-{2,}", with: "-", options: .regularExpression)

        // Remove leading/trailing hyphens
        sanitized = sanitized.trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        // Ensure length constraints
        if sanitized.count > 63 {
            sanitized = String(sanitized.prefix(63))
        }

        // Ensure it starts/ends with alphanumeric
        let isValidEdge: (Character) -> Bool = { character in
            character.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) }
        }
        if sanitized.isEmpty
            || sanitized.first.map(isValidEdge) == false
            || sanitized.last.map(isValidEdge) == false
        {
            // If validation fails, generate a random name
            return generate()
        }

        return isValid(name: sanitized) ? sanitized : generate()
    }
}
