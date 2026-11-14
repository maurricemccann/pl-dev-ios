// GENERATED from C:\dev\pl-academy (src/index.ts DECKS, src/drills.ts banks) by a throwaway script. The grader and the forge
// run on the server; these are only the fixed prompts and drill passages the Academy page also carries in its own source.
import Foundation

enum AcademyBanks {
    struct Deck { let id: String; let title: String; let prompts: [String] }
    static let decks: [Deck] = [
        Deck(id: "research", title: "Research", prompts: [
            "Map three adjacent territories where 'mental luxuries' has no competitor language yet. What vocabulary do they use that the brand must never borrow?",
            "Find one luxury house that built gravity without chasing. What did it refuse to do in its first three years?",
            "Identify a subculture that already lives the Third Truth without naming it. What would they recognize in the work instantly?",
            "Study one institution the Interference body of work could address. What is its unguarded contradiction?",
            "Trace how one brand lost its sovereign language by adopting platform vocabulary. Name the exact moment.",
            "Which of the five segments is least understood right now? Draft three questions whose answers would change targeting.",
            "Locate one historical art practice sustained daily for seven-plus years. What did year eight look like?",
        ]),
        Deck(id: "doctrine", title: "Doctrine", prompts: [
            "Take today's piece. Apply the First Truth to it: where in its composition does preparation show?",
            "Write the Second Truth as a refusal — what does control of reality decline to negotiate?",
            "Pick one banned word. Write what the brand says instead, in one sentence, without losing the meaning.",
            "Explain the sequence Preparation → Control → Persistence to someone who has only ever heard the truths in parallel. Where does the misreading break things?",
            "Choose one glyph. State its truth assignment, then argue the case for a different truth. Which argument holds?",
            "Find the line in the Manifesto you have not yet earned. What would earning it require this month?",
            "Pain as doctrine, suffering as release — apply this to one decision currently open on the founder's desk.",
        ]),
        Deck(id: "operator", title: "Operator", prompts: [
            "You are the CEO. One metric moved this week — followers, subs, or orders. Which movement matters least, and why?",
            "Write the one-sentence answer to 'what is Psyched Luxuries?' for a collector, then for a stranger, then for an institution. Where do the three answers refuse to converge?",
            "Name the next decision that only the founder can make. What information is the persona missing to make it today?",
            "The proof-building chapter ends eventually. What single proof closes it?",
            "Pick one thing the brand currently does that a luxury house would never do. Keep it or kill it — rule now, justify after.",
            "If the storefront vanished tonight, which body of work carries the brand for ninety days?",
            "What does the Congregation gather around when there is no drop this month?",
        ]),
    ]
    struct Purge { let text: String; let violations: [String] }
    static let purge: [Purge] = [
        Purge(text: "We're so excited to open the new collection. Each piece was drawn before dawn; the work persists.", violations: ["excited"]),
        Purge(text: "This drop is limited to forty pieces. What persists in the mind becomes your reality.", violations: ["limited"]),
        Purge(text: "The mark holds. Forty pieces enter the archive; seven leave it. Watch this.", violations: []),
        Purge(text: "Check out the latest transmission for an exclusive look behind the practice.", violations: ["check out", "exclusive"]),
        Purge(text: "We are honored to be featured this month. The Congregation gathers; the brand does not chase.", violations: ["honored"]),
        Purge(text: "Every piece is unique — drawn daily for seven years without a missed day.", violations: ["unique"]),
        Purge(text: "Manifest your reality with the Third Truth. The practice teaches what the word cannot.", violations: ["manifest"]),
        Purge(text: "Prepared for luxury. The second truth follows the first; it never leads.", violations: []),
        Purge(text: "What an amazing response to the drop — we're blessed to walk this with you.", violations: ["amazing", "blessed"]),
        Purge(text: "The archive does not advertise. It accumulates. Seven years of mornings are the proof.", violations: []),
    ]
    struct Law { let scenario: String; let answer: Int; let why: String }
    static let laws: [Law] = [
        Law(scenario: "Three weeks to the drop. Captions written, pieces ready — but the unboxing arrives in an unbranded poly mailer.", answer: 1, why: "Preparation means already inhabiting the standard before the moment arrives. A luxury order in a poly mailer is a first truth failure — the reach outran the readiness."),
        Law(scenario: "A commenter calls the price absurd for 'a drawing.' You feel the pull to justify with materials and hours.", answer: 2, why: "You are in control of your reality. Justifying the price imports the commenter's reality and abandons authorship of your own. The price stands; the work answers."),
        Law(scenario: "Day 2,431. No sales this week, follower count flat. The question is whether to post today.", answer: 3, why: "What persists in the mind becomes your reality. The daily practice is the third truth applied — the post happens because persistence is the mechanism, not because the metrics earned it."),
        Law(scenario: "An institution offers a feature — if you soften the Interference framing.", answer: 2, why: "Control declines to negotiate. The moment the framing bends for access, the institution authors your reality. Interference that asks permission is not interference."),
        Law(scenario: "You drafted the gallery email, then noticed the catalogue link still shows placeholder text.", answer: 1, why: "The reach was right; the readiness wasn't. Prepared for luxury means the room is dressed before the guest is invited. Fix the catalogue, then send."),
        Law(scenario: "A new subscriber asks how long the daily practice will continue.", answer: 3, why: "The honest answer is the third truth itself: the practice does not have an end date because persistence is not a phase — it is the engine. What persists becomes."),
        Law(scenario: "A competitor runs a 40% discount. The pull to match it is real.", answer: 2, why: "A discount imported from a competitor's reality is a surrender of authorship. You are in control of your reality — including its prices. Houses build gravity; they do not chase."),
        Law(scenario: "The Congregation stands at seven. Buying followers would make the brand look established overnight.", answer: 3, why: "What persists in the mind becomes your reality — and a faked congregation persists as fakery, in your mind first. Seven real is a foundation; seven thousand hollow is a debt."),
        Law(scenario: "You want to start posting founder-face content but haven't decided what the persona refuses to discuss.", answer: 1, why: "The boundary is part of the costume. Stepping in front of the camera unprepared for the questions is a first truth failure — decide the refusals before the first frame."),
    ]
    static let rewrite: [String] = [
        "🔥 SO excited to drop this LIMITED collection — check it out before it's gone!!",
        "We're honored and blessed to hit 1,000 followers — thank you all SO much!!! What should we drop next? Comment below!",
        "Our unique pieces make amazing gifts for that special someone this holiday season!",
        "Don't miss out on this exclusive opportunity to manifest your best life with our new tees.",
        "Check out our story to see the process behind this one-of-a-kind piece!",
        "Big news!!! New drop coming soon — stay tuned and turn on notifications so you don't miss it!",
        "What do you guys think of this one?? Let us know in the comments!",
        "Limited stock! Once they're gone, they're gone — grab yours now before it's too late!",
    ]
}
