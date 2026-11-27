import SwiftUI
import AVFoundation

/// The course (his ask 11-26: "I gave you the workbook and the first book so you can literally go through it and make a course which is
/// the gate app"). Every exercise of the Guidance Manual's six Waves in its order, with the 1977 workbook's breathing, balloon, bar, body
/// maps, clock, daily tools and record sheet folded into the lesson that teaches each one. Our own words throughout: no text or audio of
/// theirs. The manual's rule is the gate: repeat each exercise until it is comfortable, then move to the next. How many held sessions
/// come before "comfortable" can be tapped is ours (Focus 10 gets the most: the workbook calls it the key to the whole system).

enum GateTool: String {
    case box, pattern, mission, questions, five, viewing, body, count, breath
    var title: String {
        switch self {
        case .box: "the box"; case .pattern: "patterning"; case .mission: "missions"; case .questions: "the question inbox"
        case .five: "five questions"; case .viewing: "the viewing game"; case .body: "the body map"; case .count: "your count"; case .breath: "one breath"
        }
    }
}

struct GateLesson: Identifiable, Hashable {
    let id: String
    let title: String
    let why: String
    let steps: [String]
    var signals: [String] = []
    var tool: GateTool? = nil
    var minutes = 30
    var holds = 3
    var level = 10      // 3, 10, 12, or 20 for a lesson that ends in sleep
    var quiet = false   // Waves V and VI: no spoken steps, only his purpose
}

/// The manual's encodings and the workbook's daily tools: one-breath signals for waking life, each opened by the lesson that teaches it.
struct GateSignal { let key: String; let title: String; let how: String }

enum GateCourse {
    static let waves: [(name: String, lessons: [GateLesson])] = [
        ("Wave I · Discovery", discovery), ("Wave II · Threshold", threshold), ("Wave III · Freedom", freedom),
        ("Wave IV · Adventure", adventure), ("Wave V · Exploring", exploring), ("Wave VI · Prospecting", prospecting)]
    static let all: [GateLesson] = waves.flatMap { $0.lessons }
    static func wave(of l: GateLesson) -> String { waves.first { $0.lessons.contains(l) }?.name ?? "Any time" }

    /// Outside the six Waves (his picks 11-26 from the 1970s Monroe overview, CIA-RDP96-00788R001700270009-7): no hold count, each opens
    /// once the lesson that teaches its level is comfortable.
    static let extras: [GateLesson] = [
        GateLesson(id: "one", title: "One-Minute 10",
                   why: "The paper's patients dropped into ten between stressful moments at work. One minute, eyes open if you need them.",
                   steps: ["Breathe in bright energy and think ten.",
                           "On the out-breath let the face, shoulders and hands go.",
                           "Three slow breaths in ten, right where you are.",
                           "Think one. Back to it."],
                   minutes: 1, holds: 1),
        GateLesson(id: "nap", title: "Nap and Gentle Wake",
                   why: "The paper's wake-up: let sleep go light near the end, then a brighter tone brings you up without a jolt. 30 minutes for a nap, 90 for a full cycle.",
                   steps: ["Lie the way you sleep. Five slow breaths.",
                           "Count one to twenty into light, easy sleep.",
                           "Sleep.",
                           "Rising now. Slowly. Ten, down to one. Move your fingers, open your eyes."],
                   minutes: 30, holds: 1, level: 20), three]
    static let extraOpensAfter = ["one": "1.2", "nap": "1.5", "three": "2.1"]
    static let three = GateLesson(id: "three", title: "One Question, Three Answers",
                   why: "An artist's way from the 1977 accounts: one real question into twelve, three short answers back, worked with like oracle lines for weeks.",
                   steps: ["Write the one question you most want answered before you start.",
                           "In twelve, put it at your centre and let it go.",
                           "Take the first short answer that comes, then ask again for a second, and a third.",
                           "Write all three the moment you are back. Live with them; do not explain them away."],
                   minutes: 20, holds: 1, level: 12)

    static let discovery: [GateLesson] = [
        GateLesson(id: "1.1", title: "Orientation",
                   why: "The preparation every later session stands on: the box, the breathing, the hum, your affirmation, and the count to three.",
                   steps: ["Make your box. Any shape you like: a chest, a vault, a sphere of light. Put real things in it: your wallet for money, your watch for time, a face that is on your mind. Close the lid.",
                           "Six breaths, filling from the top down: head, chest and arms, belly, hips, thighs and knees, lower legs and feet. Each out-breath goes slow through the lips, as if at a candle, and the stale air leaves through your soles.",
                           "Keep that breath and hum out loud on every out-breath: aah, ooh, mm. Eyes open on the way in, closed on the way out.",
                           "Say your affirmation: why you are here, and that you allow in only what is equal to you or above. Write it once in your own words on the course page.",
                           "Count one, two, three. That is Focus 3: mind and brain moving together.",
                           "If you ever go too deep, breathe normally, open your eyes or move the fingers of your right hand."],
                   tool: .box, holds: 3, level: 3),
        GateLesson(id: "1.2", title: "Introduction to Focus 10",
                   why: "Body asleep, mind awake. Everything after this is built on it.",
                   steps: ["After the preparation and the count to three, let the face go: jaw, eyelids, lips, forehead, cheeks, scalp, neck, eyes. Let it sink inward.",
                           "Four, feet and toes. Five, each leg. Six, the hips. Seven, the belly. Eight, chest and lungs. Nine, the back. Ten, arms, hands and shoulders.",
                           "Look at each part with your eyes closed, from a little way off. Ask how it feels, not whether it is relaxed.",
                           "Notice what comes: tingling, pulse, warmth or cold, rising, rocking, sinking. Nothing is wrong and nothing is required.",
                           "On the way back, tell yourself your body balances itself. Count ten down to one."],
                   signals: ["awake", "memory"], holds: 5),
        GateLesson(id: "1.3", title: "Advanced Focus 10",
                   why: "The energy balloon: a field around you that keeps out what you do not want and draws in what helps.",
                   steps: ["In ten, breathe energy up and out of the top of your head like a fountain, down around you, and back in through your feet.",
                           "Turn the flow into a spiral, winding down around you and coiling back up inside.",
                           "Now from right to left: breathe it in from your right, let it out to your left. Faster, brighter, rounder, until it is a light ball around you.",
                           "Then every direction at once. Feel it behind you as well as in front.",
                           "Pop it with one breath: breathe in, see a bright moving ring with ten inside it, let it fall around you as you breathe out.",
                           "Count down to one, then come back to ten once more to set it. Let the balloon soak back into you at the end."],
                   signals: ["ten", "balloon", "back"], holds: 5),
        GateLesson(id: "1.4", title: "Release and Recharge",
                   why: "Open the box: the fear, the feeling under it, and the clean energy that was there before. Daily, with or without a session.",
                   steps: ["Do the preparation on your own: box, breathing, hum, balloon, affirmation, down to ten.",
                           "Open the box. Take the first fear you meet and let it rise away like a bubble in water. Do not choose it; take what comes.",
                           "Find the feeling the fear was covering. Let it rise away the same way.",
                           "Under both is something clean: a memory, or how you were before this. Pull that energy back in.",
                           "Do it three times. If you find nothing, let nothing float away and still pull the clean energy in. Close the lid and rest in ten."],
                   signals: ["letgo", "lift"], tool: .box, holds: 3),
        GateLesson(id: "1.5", title: "Exploration, Sleep",
                   why: "Sleep as a door: rehearse floating out, then count into real sleep. Lie the way you sleep.",
                   steps: ["In ten, remember how it feels to float, the way you do in sleep.",
                           "Float up. Roll over slowly like a log in water. Stay calm.",
                           "Float down, roll back, and settle where you started.",
                           "Count from eleven to twenty into normal, natural sleep. Do it again in your sleep."],
                   signals: ["sleep"], minutes: 30, holds: 3, level: 20),
        GateLesson(id: "1.6", title: "Free Flow 10",
                   why: "Your own purpose in ten. Write it in one plain line before you start.",
                   steps: ["Go to ten on your own. Count one to ten, let ten become a new one, and count to ten again, and again.",
                           "Carry out your purpose with what you have: the box, the balloon, a question.",
                           "To ask: put the question at your centre, push it out in all directions, let it go. Thanks seals it. The answer comes in its own way and time.",
                           "If nothing is clear, ask what the most important thing is to know right now. Puns and the obvious count.",
                           "Try one: stand under a waterfall, then in sunlight, and feel the difference. Or sit inside a pyramid you build around you.",
                           "Come back by thinking one."],
                   signals: ["ask"], tool: .questions, holds: 3)]

    static let threshold: [GateLesson] = [
        GateLesson(id: "2.1", title: "Introduction to Focus 12",
                   why: "Wider awareness. If twelve will not come, go back and work ten: ten is the key.",
                   steps: ["From a deep, steady ten, wait for the mind to wake in a different way.",
                           "When it starts, say eleven. As it grows, twelve. Let it carry you; effort gets in the way.",
                           "Do not study it now. Study it afterwards.",
                           "Sometimes an unpleasant side of you surfaces here. It is part of the work: ground yourself, and stop if it is too much.",
                           "Come back from twelve to ten, then ten to one."],
                   signals: ["twelve"], holds: 5, level: 12),
        GateLesson(id: "2.2", title: "Problem Solving",
                   why: "Take one specific problem into twelve and let it go. Write it as your plan first.",
                   steps: ["In twelve, hold the problem at your centre: heart, belly or head, wherever it lives.",
                           "Push it out through all of your awareness, then let it go.",
                           "Notice images, words, sensations, a sudden knowing. Simple answers count; so do jokes.",
                           "If you are not sure what to ask, ask what you most need to know right now. Thanks seals it."],
                   signals: ["ask", "clear"], tool: .questions, holds: 3, level: 12),
        GateLesson(id: "2.3", title: "One-Month Patterning",
                   why: "What you think in a deep state takes shape around you. Write the pattern before you start; the patterning card checks it.",
                   steps: ["In twelve, build what you want in detail: you in it, now, with feeling.",
                           "Present tense. Say I. For you only. Clear about what you really want. Start small enough to believe.",
                           "Do not say how it comes. Ask that it work for the good of your whole self.",
                           "Push it out in all directions and let it go. Ease means it is released. Do not dig the seed up to check it."],
                   signals: ["pattern"], tool: .pattern, holds: 3, level: 12),
        GateLesson(id: "2.4", title: "Color Breathing",
                   why: "Colours as tools for the body: green calms, red charges, white feeds, purple balances.",
                   steps: ["In ten, breathe in bright energy, hold green, and breathe it down through your body and out your feet. The charge goes with it.",
                           "Red for an act of strength or speed: breathe it in, picture the act, open your eyes and do it.",
                           "White from above into your open palms, spreading through all of you.",
                           "Purple to a place that needs it: say heal, balance. Feed the health, never the problem, and finish by seeing yourself whole.",
                           "You can offer energy to someone else; it is theirs to use or not. End in twelve and renew your patterns."],
                   signals: ["green", "red", "white", "purple"], tool: .breath, holds: 3),
        GateLesson(id: "2.5", title: "Energy Bar Tool",
                   why: "A bar of light to gather and point energy. Yours: a wand, a tube, your own hands.",
                   steps: ["In ten, take a dot of light and stretch it into a bar.",
                           "Say on: it lights and thickens. Say off: it dims and thins. Slowly, once a second or two.",
                           "Speed it up. Let go of the words and of your breathing; keep the on and off going.",
                           "Faster, like a strobe, until it seems always on and there is a warm pulse in your solar plexus.",
                           "Any excess heat, hum it out. Put the bar back in its place so it waits for you."],
                   signals: ["memory", "ten"], holds: 3),
        GateLesson(id: "2.6", title: "Living Body Map",
                   why: "Your body as a map of light: find what is dim and charge it. Then the finer map of your feelings behind it.",
                   steps: ["In ten, charge the bar. Make an outline of your body in white light, like a paper cut-out, a screen, or a glass statue.",
                           "Turn it red for the blood, blue for the nerves, yellow for the organs, orange for muscle and bone, white for everything.",
                           "At each colour, find any dim or flickering place. Green from the bar to balance it, then purple to charge it.",
                           "Wash the whole map in purple from top to bottom.",
                           "Behind it is a finer map of your feelings. Calm what is flickering or too bright until it is even, strong and calm."],
                   signals: ["relax", "pain"], tool: .body, holds: 3),
        GateLesson(id: "2.7", title: "One Breath",
                   why: "Every tool so far, in waking life, on one breath, without anyone noticing. Use it through the shift; it counts as a session.",
                   steps: ["Breathe in bright energy and think ten; breathe out into ten.",
                           "On one breath: pop the balloon, ask a question, or set a pattern.",
                           "At the first sign of a charge, send green through you. Tired: red, or white into your palms."],
                   tool: .breath, minutes: 5, holds: 5)]

    static let freedom: [GateLesson] = [
        GateLesson(id: "3.1", title: "Liftoff",
                   why: "Calm and at home from a point of view that is not your body. You can always come straight back.",
                   steps: ["Build the balloon well in ten.",
                           "Let it carry you a little way up, with you inside it. Like an elevator: you rise by settling.",
                           "Stop and notice what is around you. Float back down to where you began.",
                           "Do it five times, a little higher each time.",
                           "Coming back is always one thought away: think of your right hand's fingers and move them."],
                   holds: 5),
        GateLesson(id: "3.2", title: "Remote Viewing",
                   why: "Reach out to something far away and describe it. The manual's version uses a friend and a white paper bag; the Gate has a fair version from your own pieces.",
                   steps: ["Set it up first: a friend somewhere else puts a small object in a clean white paper bag at a set time. Or seal a target in the viewing game.",
                           "In ten, charge the bar. Keep one end at your centre and stretch the other to the target.",
                           "Let what is there flow back along the bar. Shapes, colours, textures, feelings.",
                           "Describe; do not name. A wet concrete rectangle is not always a pool.",
                           "Write it down before you look. Then check, and log the hits and misses both."],
                   signals: ["memory"], tool: .viewing, holds: 3),
        GateLesson(id: "3.3", title: "Vectors",
                   why: "A clock around you, so you can go out in a direction and find your way back.",
                   steps: ["Twelve is above your head, six below your feet, three at your left hip, nine at your right.",
                           "Send your awareness around: twelve, three, six, nine, and home. Notice what each direction feels like.",
                           "Turn the clock: three in front of you, nine behind. Go twelve, three, nine, and back to twelve.",
                           "Remember the direction that felt easy or brought something. Write it down."],
                   holds: 3, level: 12),
        GateLesson(id: "3.4", title: "Five Questions",
                   why: "Who am I. Where and who was I before this. What is my purpose here. What can I do now to serve it. What is the most important message for me now.",
                   steps: ["In twelve, ask the first question and wait.",
                           "Answers come as pictures, feeling or knowing more often than words. Let them come.",
                           "Ask the next, through all five.",
                           "Translate afterwards, not during. Repeat until each answer is clear. GlyphBot keeps them word for word."],
                   tool: .five, holds: 2, level: 12),
        GateLesson(id: "3.5", title: "Energy Food",
                   why: "Restore your energy without food: palms up, white light in.",
                   steps: ["In ten, hold your hands out, palms up.",
                           "Breathe in and hold. White energy comes down from above into your palms, up your arms and through you.",
                           "Breathe out. Feel how full you are.",
                           "Test it awake straight after: do you feel more energy? Once it works, the session is no longer needed."],
                   signals: ["white"], tool: .breath, holds: 3),
        GateLesson(id: "3.6", title: "First-Stage Separation",
                   why: "Five ways to tell your energy apart from your body. Pick the one that feels right and practise it.",
                   steps: ["Roll: turn the energy inside you like a log in water until it turns freely, then ease the pressure and peel out.",
                           "Rise like a stiff pole: head first, pivoting at the feet, until you stand.",
                           "Back away: slowly, down through whatever you are lying on.",
                           "Out of the top of your head like mist, re-forming outside.",
                           "Float up like a cloud, on the pleasure of floating.",
                           "Try less. In the Army's 1982 report, effort blocked it and the tired, loose sessions went furthest.",
                           "Excitement pulls you back in, so stay patient. To return, think of a hand and move it; walking or cold water finishes it."],
                   holds: 3)]

    static let adventure: [GateLesson] = [
        GateLesson(id: "4.1", title: "One-Year Patterning",
                   why: "Who and where you are a year from now. Plan it carefully first, with the same rules as the month.",
                   steps: ["In twelve, build the year in detail, now, with you in it and feeling it.",
                           "Same rules: present tense, I, for you, specific, for the good of your whole self, no saying how.",
                           "Push it out in all directions and let it go."],
                   signals: ["pattern"], tool: .pattern, holds: 2, level: 12),
        GateLesson(id: "4.2", title: "Five Messages",
                   why: "Five messages in order of importance, the fifth first.",
                   steps: ["In twelve, ask for the fifth most important message for you now.",
                           "Then the fourth, the third, the second, and the most important last.",
                           "Do not work them out as they come; read them afterwards."],
                   tool: .five, holds: 2, level: 12),
        GateLesson(id: "4.3", title: "Free Flow 12",
                   why: "Your own exploration in twelve. Decide the purpose first, or you drift into sleep.",
                   steps: ["Preparation, ten, then twelve.",
                           "The steady tone is your guidepost: it reminds you where and who you are, so you can roam far.",
                           "Carry out your purpose. Come back when you are done."],
                   holds: 3, level: 12),
        GateLesson(id: "4.4", title: "Non-Verbal Communication",
                   why: "Meaning that arrives whole, all at once, without words. You have met it in vibration, light and feeling already.",
                   steps: ["In twelve, stay open to a whole meaning arriving at once.",
                           "It may come as vibration, light, motion or feeling.",
                           "Afterwards, translate it into words, knowing some of it will not fit.",
                           "Give familiar sensations new meanings. That becomes your vocabulary."],
                   signals: ["speak"], holds: 3, level: 12),
        GateLesson(id: "4.5", title: "Non-Verbal Communication II",
                   why: "More practice translating whole impressions into words and pictures.",
                   steps: ["In twelve, receive a whole impression.",
                           "Unfold it slowly: what is in it, what it means, what it asks.",
                           "Write the translation as soon as you are back."],
                   holds: 3, level: 12),
        GateLesson(id: "4.6", title: "Compoint",
                   why: "A communication point: a state you set once and can return to, to gather, meet, or watch.",
                   steps: ["In twelve, set your point: a place you will know again.",
                           "Gather what is there, meet what comes, or simply observe.",
                           "It can be a meeting place agreed with a friend. Return to it on purpose."],
                   holds: 3, level: 12)]

    static let exploring: [GateLesson] = [
        GateLesson(id: "5.1", title: "Mission 10",
                   why: "No spoken steps from here on: the tone carries you and the direction is yours. Purpose firm before you begin.",
                   steps: ["Preparation, then ten on your own.", "Carry out your purpose with the tools you have.", "Come back your own way when the tone ends."],
                   quiet: true),
        GateLesson(id: "5.2", title: "Mission 12",
                   why: "The same in twelve: a pattern, a problem, a question, a new idea or place.",
                   steps: ["Preparation, ten, then twelve.", "Carry out your purpose.", "Come back when it is time."],
                   level: 12, quiet: true),
        GateLesson(id: "5.3", title: "Mission Day",
                   why: "Fifteen minutes when you wake, before the day starts: see the day's goal done.",
                   steps: ["Preparation, then ten or twelve, whichever suits you.", "See and feel today's goal already done: moving pictures and feeling, not words.", "Come back and go."],
                   tool: .mission, minutes: 15, quiet: true),
        GateLesson(id: "5.4", title: "Mission Night",
                   why: "As you go to sleep: set what the night is for, then sleep.",
                   steps: ["Preparation, then ten or twelve.", "Set the night: a dream, a problem solved, a message, or remembering your dreams.", "Let it carry you into sleep."],
                   tool: .mission, level: 20, quiet: true),
        GateLesson(id: "5.5", title: "Horizons",
                   why: "No purpose needed. Memories, feelings and events come up to be seen in a new way.",
                   steps: ["Preparation, then the level that suits you.", "Relax and let it happen.", "Write it down after. Over time, look for the threads."],
                   quiet: true),
        GateLesson(id: "5.6", title: "Pathways",
                   why: "Follow the sound down new paths, or old ones you forgot. Walks to try: a flower, a cloud, the surf, a tree, a breeze, the earth's core.",
                   steps: ["Preparation, then let the sound lead.", "Move between ten and twelve whenever you like. What changes?", "Come back your own way."],
                   quiet: true),
        GateLesson(id: "5.7", title: "Calm Meets Worry",
                   why: "From the 1970s Monroe paper: the deep calm of ten, paired a little at a time with something that makes you uneasy, until it loses its charge. Small things only. One too-much rests it for a week.",
                   steps: ["Before you start, pick one small unease: a message to send, a price to say out loud, a call to make. Never an old wound or a big fear.",
                           "Go to ten and let the body settle fully.",
                           "Bring the small thing in for a breath or two, at a distance, like a picture across the room. Stay loose.",
                           "If the body tightens, let the picture go and settle back into ten. That is the work, not a failure.",
                           "Next time, bring it a little closer or hold it a little longer, only once the last step felt easy.",
                           "End with green through you. Count back to one."],
                   signals: ["green"], holds: 3)]

    static let prospecting: [GateLesson] = [
        GateLesson(id: "6.1", title: "Metamorphosite",
                   why: "Change at the level of the mind. Set the changes you want before you begin.",
                   steps: ["Preparation, then ten or twelve.", "Pattern the changes you set.", "The tone brings you back."],
                   tool: .pattern, quiet: true),
        GateLesson(id: "6.2", title: "Bio-Body",
                   why: "A thorough walk through your body and its rhythms, with the body map and the bar.",
                   steps: ["Preparation, then your level.", "Go through the body, system by system, with the map and the bar.", "Come back."],
                   tool: .body, quiet: true),
        GateLesson(id: "6.3", title: "Null Point",
                   why: "Past twelve to a still, neutral point. From there, choose exactly what to explore.",
                   steps: ["Preparation, ten, twelve, and on past twelve.", "At the still point, choose your direction.", "The tone brings you back."],
                   level: 12, quiet: true),
        GateLesson(id: "6.4", title: "Plus Polarity",
                   why: "Through the still point to the other side of it. Notice what is subtly different.",
                   steps: ["Preparation, ten, twelve, through the still point.", "Pay attention to small changes in your awareness.", "The tone brings you back."],
                   level: 12, quiet: true),
        GateLesson(id: "6.5", title: "Near Reaches",
                   why: "Through the still point into time and space, the physical universe.",
                   steps: ["Preparation, then twelve and through the still point.", "Explore.", "Come back."],
                   level: 12, quiet: true),
        GateLesson(id: "6.6", title: "Far Reaches",
                   why: "Beyond time and space. Everything before this was the preparation.",
                   steps: ["Preparation, ten, twelve, through the still point.", "Dig deep. Go high.", "Come back."],
                   level: 12, quiet: true)]

    static let signals: [GateSignal] = [
        GateSignal(key: "awake", title: "Wide awake", how: "Fingers of your right hand to the back of your neck. Think one."),
        GateSignal(key: "memory", title: "Remember", how: "Close your eyes. Fingers of your right hand softly to the middle of your forehead."),
        GateSignal(key: "ten", title: "Focus 10", how: "Breathe in bright energy, think ten, breathe out."),
        GateSignal(key: "balloon", title: "Balloon", how: "Breathe in, see a moving ring with ten inside it, let it fall around you as you breathe out."),
        GateSignal(key: "back", title: "Come back", how: "Think one and move the fingers of your right hand."),
        GateSignal(key: "sleep", title: "Sleep", how: "Lie down, five deep breaths, count one to twenty."),
        GateSignal(key: "ask", title: "Ask", how: "Breathe into your head, think twelve, ask, and let it go on the out-breath."),
        GateSignal(key: "twelve", title: "Focus 12", how: "From ten, count eleven, twelve."),
        GateSignal(key: "pattern", title: "Pattern", how: "In twelve, build it carefully, push it out everywhere, let it go."),
        GateSignal(key: "green", title: "Calm the charge", how: "Breathe in, hold, think green; breathe it down and out through your feet."),
        GateSignal(key: "red", title: "Strength", how: "Breathe in, hold, think of the act and red; breathe out, open your eyes, do it."),
        GateSignal(key: "white", title: "Fresh energy", how: "Palms up. Breathe in white from above into your hands and through you."),
        GateSignal(key: "purple", title: "Balance a place", how: "Breathe in, hold, think purple, send it to the place: heal, balance."),
        GateSignal(key: "relax", title: "Relax", how: "Think ten. Breathe out as if blowing out a candle."),
        GateSignal(key: "letgo", title: "Let a feeling go", how: "Breathe in, name the feeling, and let it float off on the out-breath like a bubble."),
        GateSignal(key: "lift", title: "Lift when low", how: "Breathe in bright energy through the top of your head; on the out-breath let it fill your chest."),
        GateSignal(key: "clear", title: "Think clearly", how: "Think twelve, hold the question, breathe out, and take the first plain answer."),
        GateSignal(key: "speak", title: "Speak smoothly", how: "Think ten, drop the shoulders, and let the first sentence come slower than feels natural."),
        GateSignal(key: "pain", title: "Turn pain down", how: "The workbook's: look at the place with your eyes closed and repeat 55515 in your mind.")]

    static let before = [
        "An hour after eating. No alcohol, no drugs, not too much caffeine.",
        "Bathroom first. Loosen your clothes; shoes and glasses off. A blanket close: the body can go cold, then warm.",
        "Somewhere dark and quiet, phone on Do Not Disturb. A noise you cannot stop takes you deeper: let it.",
        "Headphones on, volume just loud enough to hear.",
        "Dim the room and give it five quiet minutes before Begin, with no clock in view.",
        "Old or unpleasant feelings can surface, mostly in twelve and beyond. Ground, and stop if it is too much; it passes.",
        "Never while driving, on the floor at work or around machines. Epilepsy or seizures: ask a doctor first."]

    static let grounding = [
        "Count yourself slowly back to one.", "Drink cool water.", "Cold water on your face, neck and wrists.",
        "Barefoot outside, breathing deep, letting the extra go into the ground.", "Your back against a tree."]

    /// The session as timed lines: the preparation the manual teaches (slower in Orientation), the lesson's own steps, the way back.
    static func script(_ l: GateLesson, plan: String, affirmation: String, minutes: Int) -> [(String, Double)] {
        if l.minutes <= 5 { return l.steps.map { ($0, Double(minutes * 60) / Double(l.steps.count)) } }   // one breath needs no preparation
        if l.id == "nap" { return [(l.steps[0], 40), (l.steps[1], 60), (l.steps[2], max(Double(minutes * 60) - 190, 60)), (l.steps[3], 90)] }
        let index = all.firstIndex(of: l) ?? 0
        var s: [(String, Double)] = [("Lie back, or sit with your head held. Put every worry in your box and close the lid.", 40)]
        if index > 0 {
            let fills = ["your head, and swirl it there", "your chest and arms", "your belly", "your hips", "your thighs and knees", "your lower legs and feet"]
            s += fills.map { f -> (String, Double) in ("Breathe in and fill \(f). Breathe out slow through the lips, as at a candle, out through your soles.", 15) }
            s.append(("Keep that breath and hum out loud on each out-breath: aah, ooh, mm. Eyes open in, closed out.", 60))
            if index >= 2 { s.append(("Pop your balloon: a bright moving ring with ten inside it, falling around you.", 25)) }
            s.append((affirmation.isEmpty ? "Say why you are here, and that only what is equal to you or above comes in." : affirmation, 30))
            s.append(("One, two, three.", 20))
            if index >= 2 { s.append(("Down to ten: let each part of the body go at each number. Body asleep, mind awake.", 60)) }
            if l.level == 12 { s.append(("Eleven. Twelve. Wider, more awake.", 30)) }
        }
        let back: (String, Double) = l.level == 20 ? ("Eleven, twelve, on to twenty. Normal, natural sleep.", 90)
            : (l.level == 12 ? "Twelve to ten, then ten down to one. Move the fingers of your right hand. Open your eyes."
                             : "Ten down to one. Move the fingers of your right hand. Open your eyes.", 30)
        let core = l.quiet ? [plan.isEmpty ? "Your purpose." : plan] : l.steps
        let left = max(Double(minutes * 60) - s.map(\.1).reduce(0, +) - back.1, Double(core.count) * 30)
        return s + core.map { ($0, left / Double(core.count)) } + [back]
    }
}

// MARK: - progress, in the Gate's one protected file

struct GateSitting: Codable, Identifiable {
    var id = UUID()
    let lesson: String
    let at: Date
    let plan: String, position: String, warmth: String, energy: String
    let mealHours: Int
    let before: Band
    var after: Band
    var happened = ""
    var held = false
    var tooMuch = false
    var seconds = 0
    var clickedOut: Bool? = nil   // fell asleep partway: common, never counted against the lesson
}

struct GateCourseLog: Codable {
    var affirmation = ""
    var held: [String: Int] = [:]
    var comfortable: [String] = []
    var sittings: [GateSitting] = []
}

extension GateStore {
    var course: GateCourseLog { saved.course ?? GateCourseLog() }
    func held(_ id: String) -> Int { course.held[id] ?? 0 }
    func comfortable(_ id: String) -> Bool { course.comfortable.contains(id) }
    func isOpen(_ l: GateLesson) -> Bool {
        if let after = GateCourse.extraOpensAfter[l.id] { return comfortable(after) }
        guard let i = GateCourse.all.firstIndex(of: l) else { return false }
        if resting(l) { return false }
        return i == 0 || comfortable(GateCourse.all[i - 1].id)
    }
    /// Calm Meets Worry rests a week after a too-much (his pick: mild only, with a stop rule).
    func resting(_ l: GateLesson) -> Bool {
        l.id == "5.7" && course.sittings.contains { $0.lesson == l.id && $0.tooMuch && $0.at > Date.now.addingTimeInterval(-7 * 86400) }
    }
    var currentLesson: GateLesson { GateCourse.all.first { !comfortable($0.id) } ?? GateCourse.all[GateCourse.all.count - 1] }
    var carried: [GateSignal] {
        let keys = Set(GateCourse.all.filter { held($0.id) > 0 || comfortable($0.id) }.flatMap(\.signals))
        return GateCourse.signals.filter { keys.contains($0.key) }
    }
    func editCourse(_ edit: (inout GateCourseLog) -> Void) { change { s in var c = s.course ?? GateCourseLog(); edit(&c); s.course = c } }

    /// The Lab's old Wave I tally (it lived there before the course) carries over once, as held sessions.
    func seed(fromLab tapes: [Int]?) {
        guard readable, saved.course == nil, let t = tapes, t.contains(where: { $0 > 0 }) else { return }
        editCourse { c in for (i, n) in t.prefix(GateCourse.discovery.count).enumerated() where n > 0 { c.held[GateCourse.discovery[i].id] = n } }
    }
}

// MARK: - the screens

struct GateCourseCard: View {
    let store: GateStore
    let openAll: () -> Void
    @State private var sitting: GateLesson?

    var body: some View {
        let l = store.currentLesson
        let done = GateCourse.all.filter { store.comfortable($0.id) }.count
        return PCard(title: "The course", hint: "The manual's six Waves in its order. Each lesson opens when the one before is comfortable.") {
            Text(GateCourse.wave(of: l)).candleHint()
            Text(l.title).candleH2()
            Text(l.why).candleHint()
            Text("Held \(store.held(l.id)) of \(l.holds) · \(done) of \(GateCourse.all.count) lessons comfortable").candleHint()
            if store.course.sittings.count >= 10 {
                Label("\(store.course.sittings.count) sittings. The early reports say the change tends to settle in after the tenth.", systemImage: "seal").candleHint()
            }
            Button("Start this session") { sitting = l }.buttonStyle(CandleButton()).disabled(!store.readable)
            Button("All lessons") { openAll() }.buttonStyle(CandleGhost())
        }
        .fullScreenCover(item: $sitting) { GateSittingView(store: store, lesson: $0) }
    }
}

struct GateCourseSheet: View {
    let store: GateStore
    let go: (GateTool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var affirmation = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("In your own words", text: $affirmation, axis: .vertical)
                    Button("Keep it") { store.editCourse { $0.affirmation = affirmation.trimmingCharacters(in: .whitespacesAndNewlines) } }
                        .disabled(affirmation == store.course.affirmation)
                } header: { Text("Your affirmation") } footer: { Text("Said at the start of every session. Why you are here, and what you allow in.") }
                ForEach(GateCourse.waves.indices, id: \.self) { w in
                    Section(GateCourse.waves[w].name) {
                        ForEach(GateCourse.waves[w].lessons) { l in
                            NavigationLink { GateLessonView(store: store, lesson: l, go: { go($0); dismiss() }) } label: { row(l) }
                        }
                    }
                }
                Section {
                    ForEach(GateCourse.extras) { l in
                        NavigationLink { GateLessonView(store: store, lesson: l, go: { go($0); dismiss() }) } label: { row(l) }
                    }
                } header: { Text("Any time") }
                Section {
                    if store.carried.isEmpty { Text("Each lesson adds a signal you can use awake, on one breath.").foregroundStyle(.secondary) }
                    ForEach(store.carried, id: \.key) { s in
                        VStack(alignment: .leading, spacing: 2) { Text(s.title); Text(s.how).font(.footnote).foregroundStyle(.secondary) }
                    }
                } header: { Text("What you carry") }
                Section("If you come back foggy") { ForEach(GateCourse.grounding, id: \.self) { Text($0) } }
            }
            .scrollContentBackground(.hidden)
            .background { CandleGround() }
            .preferredColorScheme(.dark)
            .navigationTitle("The course").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .onAppear { affirmation = store.course.affirmation }
    }

    private func row(_ l: GateLesson) -> some View {
        let open = store.isOpen(l)
        return HStack(spacing: 12) {
            Image(systemName: GateCourse.extraOpensAfter[l.id] != nil ? (open ? "clock" : "lock") : store.comfortable(l.id) ? "checkmark.seal.fill" : open ? "circle" : "lock")
                .foregroundStyle(Candle.gold).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(l.id) · \(l.title)").foregroundStyle(open ? Candle.ink : Candle.ink.opacity(0.5))
                Text(GateCourse.extraOpensAfter[l.id] != nil ? (open ? "\(l.minutes) min" : "Locked")
                     : store.comfortable(l.id) ? "Comfortable" : open ? "Held \(store.held(l.id)) of \(l.holds)" : store.resting(l) ? "Resting this week" : "Locked")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 44)
    }
}

private struct GateLessonView: View {
    let store: GateStore
    let lesson: GateLesson
    let go: (GateTool) -> Void
    @State private var sitting = false

    var body: some View {
        let open = store.isOpen(lesson)
        let mine = store.course.sittings.filter { $0.lesson == lesson.id }.suffix(10).reversed()
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(GateCourse.wave(of: lesson)).candleHint()
                Text(lesson.why).font(Font.pl(size: 16)).foregroundStyle(Candle.ink)
                Text(lesson.quiet ? "No spoken steps. The tone carries you; your purpose is on the screen." : "\(lesson.minutes) minutes, then the way back.").candleHint()
                ForEach(lesson.steps.indices, id: \.self) { i in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(i + 1)").font(Font.pl(size: 14, weight: .semibold)).foregroundStyle(Candle.gold).frame(width: 18)
                        Text(lesson.steps[i]).font(Font.pl(size: 15)).foregroundStyle(Candle.ink).fixedSize(horizontal: false, vertical: true)
                    }
                }
                let signals = GateCourse.signals.filter { lesson.signals.contains($0.key) }
                if !signals.isEmpty {
                    Text("Signals this lesson gives you").candleH2()
                    ForEach(signals, id: \.key) { s in Text("\(s.title): \(s.how)").candleHint() }
                }
                if let tool = lesson.tool {
                    Button("Open \(tool.title)") { go(tool) }.buttonStyle(CandleGhost())
                }
                if store.resting(lesson) {
                    Text("Resting for a week after a too-much. Go back to ten on its own meanwhile.").candleHint()
                } else if !open, let after = GateCourse.extraOpensAfter[lesson.id], let a = GateCourse.all.first(where: { $0.id == after }) {
                    Text("Opens when \(a.title) is comfortable. You can read it now.").candleHint()
                } else if !open, let i = GateCourse.all.firstIndex(of: lesson), i > 0 {
                    Text("Opens when \(GateCourse.all[i - 1].title) is comfortable. You can read it now.").candleHint()
                }
                Button("Start a session") { sitting = true }.buttonStyle(CandleButton()).disabled(!open || !store.readable)
                if GateCourse.extraOpensAfter[lesson.id] == nil { comfortable }
                if !mine.isEmpty {
                    Text("Your record").candleH2()
                    ForEach(Array(mine)) { s in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(s.at.formatted(date: .abbreviated, time: .shortened)) · \(s.before.title) to \(s.after.title)\(s.held ? " · held" : s.tooMuch ? " · too much" : "")\(s.clickedOut == true ? " · clicked out" : "")").candleHint()
                            if !s.happened.isEmpty { Text(s.happened).font(Font.pl(size: 14)).foregroundStyle(Candle.ink) }
                        }
                    }
                }
            }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }
        .background { CandleGround() }
        .navigationTitle(lesson.title).navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $sitting) { GateSittingView(store: store, lesson: lesson) }
    }

    @ViewBuilder private var comfortable: some View {
        if store.comfortable(lesson.id) {
            Label("Comfortable. Come back to it any time; repetition is the advance.", systemImage: "checkmark.seal.fill").candleHint()
        } else if store.held(lesson.id) >= lesson.holds {
            Text("Held \(store.held(lesson.id)) times. When it feels familiar and easy, open the next.").candleHint()
            Button("Comfortable: open the next") { store.editCourse { $0.comfortable.append(lesson.id) } }.buttonStyle(CandleButton())
        } else {
            Text("Held \(store.held(lesson.id)) of \(lesson.holds). Repeat until it is easy.").candleHint()
        }
    }
}

/// One session: the workbook's record sheet before, the timed lines with the tone, the record after.
struct GateSittingView: View {
    let store: GateStore
    let lesson: GateLesson
    @Environment(\.dismiss) private var dismiss
    private enum Stage { case setup, live, after, done }
    @State private var stage = Stage.setup
    @State private var plan = ""
    @State private var position = "On my back"
    @State private var warmth = "Warm"
    @State private var energy = "Middle"
    @State private var mealHours = 2
    @State private var before = Band.steady
    @State private var after = Band.steady
    @State private var minutes = 30
    @State private var tone = true
    @State private var happened = ""
    @State private var held = false
    @State private var tooMuch = false
    @State private var clickedOut = false
    @State private var sensed = ""
    @State private var felt = ""
    @State private var symbol = ""
    @State private var made = ""
    @State private var fading: AVAudioPlayer?
    @State private var line = ""
    @State private var started = Date()
    @State private var seconds = 0
    @State private var player: AVAudioPlayer?
    @State private var problem: String?
    @State private var cardPack: PackKey?   // a saved sitting earns a card pack, once per lesson (his ask 11-27)

    private var beat: Double { lesson.level == 20 ? 2 : 4 }   // 4 Hz: the beat the 1982 Army trip report gives for the Gateway week

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch stage {
                    case .setup: setup
                    case .live: live
                    case .after: afterward
                    case .done: done
                    }
                }
                .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            }
            .candleScreen()
            .navigationTitle(lesson.title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { stop(); dismiss() } } }
        }
        .task(id: stage == .live) { if stage == .live { await run() } }
        .onAppear { minutes = lesson.minutes }
        .onDisappear { stop() }
        .earnsPack($cardPack)
    }

    @ViewBuilder private var setup: some View {
        DisclosureGroup("Before you start") {
            VStack(alignment: .leading, spacing: 8) { ForEach(GateCourse.before, id: \.self) { Text($0).candleHint().frame(maxWidth: .infinity, alignment: .leading) } }
                .padding(.top, 6)
        }
        .tint(Candle.gold)
        TextField(lesson.quiet ? "Your purpose (it stays on the screen)" : "Your plan for this session", text: $plan, axis: .vertical).textFieldStyle(.roundedBorder)
        choice("Position", $position, ["On my back", "On my side", "Face down", "Sitting"])
        choice("Body", $warmth, ["Cold", "Warm", "Hot"])
        choice("Energy", $energy, ["Low", "Middle", "High"])
        band("Mood now", $before)
        Stepper("Last ate \(mealHours) hour\(mealHours == 1 ? "" : "s") ago", value: $mealHours, in: 0...12).frame(minHeight: 44)
        Picker("Length", selection: $minutes) { ForEach(Array(Set(lesson.id == "nap" ? [30, 90] : [lesson.minutes, 10, 20, 30, 45])).sorted(), id: \.self) { Text("\($0) min").tag($0) } }
            .pickerStyle(.segmented)
        Toggle("Tone in the headphones (\(Int(beat)) Hz between the ears)", isOn: $tone).tint(Candle.gold).frame(minHeight: 44)
        if let problem { Text(problem).candleHint() }
        if store.course.sittings.filter({ $0.at > Date.now.addingTimeInterval(-7 * 86400) }).count >= 20 {
            Text("Twenty sittings this week. The Army's trainers stopped at twenty; rest is part of it.").candleHint()
        }
        Button("Begin") { begin() }.buttonStyle(CandleButton()).disabled(lesson.quiet && plan.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    @ViewBuilder private var live: some View {
        Text(line).font(Font.pl(size: 22, weight: .medium)).foregroundStyle(Candle.goldHi).frame(maxWidth: .infinity, minHeight: 260)
            .multilineTextAlignment(.center)
        Text("Move the fingers of your right hand to come straight back.").candleHint()
        Button("Stop here") { finish() }.buttonStyle(CandleGhost())
    }

    @ViewBuilder private var afterward: some View {
        Text("Write it down now, before it fades.").candleH2()
        Text("If you can, make one thing first: a ten-minute sketch or one line, while the state is still on you.").candleHint()
        TextField("What I made", text: $made, axis: .vertical).textFieldStyle(.roundedBorder)
        TextField("What you sensed", text: $sensed, axis: .vertical).textFieldStyle(.roundedBorder)
        TextField("What the body felt", text: $felt, axis: .vertical).textFieldStyle(.roundedBorder)
        TextField("Any symbol or picture", text: $symbol, axis: .vertical).textFieldStyle(.roundedBorder)
        TextField("Anything else", text: $happened, axis: .vertical).textFieldStyle(.roundedBorder)
        band("Mood now", $after)
        Toggle("It held", isOn: Binding(get: { held }, set: { held = $0; if $0 { tooMuch = false } })).tint(Candle.gold).frame(minHeight: 44)
        Toggle("It was too much", isOn: Binding(get: { tooMuch }, set: { tooMuch = $0; if $0 { held = false } })).tint(Candle.gold).frame(minHeight: 44)
        Toggle("I clicked out (fell asleep partway)", isOn: $clickedOut).tint(Candle.gold).frame(minHeight: 44)
        if clickedOut { Text("Common in the early weeks, and it never counts against the lesson. Try it sitting up, or earlier in your day.").candleHint() }
        if tooMuch { Text("This lesson's count starts again. Go back to the one before until it is easy; nothing is lost.").candleHint() }
        Button("Save") { save() }.buttonStyle(CandleButton())
    }

    @ViewBuilder private var done: some View {
        Text("Held \(store.held(lesson.id)) of \(lesson.holds).").candleH2()
        Text("It ran \(seconds / 60) minutes. \(before.title) to \(after.title).").candleHint()
        if tooMuch { ForEach(GateCourse.grounding, id: \.self) { Text($0).candleHint() } }
        if clickedOut, lesson.level == 12 { Text("Clicking out in twelve usually means ten needs more time. A few sittings of Advanced Focus 10 first.").candleHint() }
        Button("Done") { dismiss() }.buttonStyle(CandleButton())
    }

    private func choice(_ title: String, _ value: Binding<String>, _ options: [String]) -> some View {
        Picker(title, selection: value) { ForEach(options, id: \.self) { Text($0).tag($0) } }.pickerStyle(.segmented)
    }

    private func band(_ title: String, _ value: Binding<Band>) -> some View {
        HStack {
            Text(title).candleHint()
            Spacer()
            Picker(title, selection: value) { ForEach(Band.allCases.reversed(), id: \.self) { Text($0.title).tag($0) } }.labelsHidden().pickerStyle(.menu)
        }
        .frame(minHeight: 44)
    }

    private func begin() {
        problem = nil
        if tone {
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback)   // plays with the silent switch on
                try AVAudioSession.sharedInstance().setActive(true)
                let p = try AVAudioPlayer(data: FrequencyTone.wav(beat: beat))
                p.numberOfLoops = -1
                p.volume = 0
                p.play()
                p.setVolume(1, fadeDuration: 4)
                player = p
            } catch {
                problem = "The tone did not start: \(error.localizedDescription)"
                return
            }
        }
        UIApplication.shared.isIdleTimerDisabled = true   // a locked screen would end the sound
        started = .now
        after = before
        stage = .live
    }

    private func run() async {
        let lines = GateCourse.script(lesson, plan: plan, affirmation: store.course.affirmation, minutes: minutes)
        for (i, item) in lines.enumerated() {
            let (text, secs) = item
            if lesson.id == "nap", i == lines.count - 1, tone { rise() }
            line = text
            do { try await Task.sleep(for: .seconds(secs)) } catch { return }
        }
        finish()
    }

    private func finish() {
        guard stage == .live else { return }
        seconds = Int(Date.now.timeIntervalSince(started))
        stop()
        stage = .after
    }

    /// The gentle wake: the slow sleep beat gives way to a brighter one over ten seconds.
    private func rise() {
        guard let p = try? AVAudioPlayer(data: FrequencyTone.wav(beat: 14)) else { return }
        player?.setVolume(0, fadeDuration: 10)
        p.numberOfLoops = -1
        p.volume = 0
        p.play()
        p.setVolume(1, fadeDuration: 10)
        fading = player   // held until stop(), so its fade is not cut short
        player = p
    }

    private func stop() {
        fading?.stop()
        fading = nil
        player?.stop()
        player = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    /// The talk-through, kept as one text so old records read the same.
    private var debrief: String {
        [("Made", made), ("Sensed", sensed), ("Body", felt), ("Symbol", symbol), ("", happened)]
            .map { ($0.0, $0.1.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.1.isEmpty }
            .map { $0.0.isEmpty ? $0.1 : "\($0.0): \($0.1)" }
            .joined(separator: "\n")
    }

    private func save() {
        let s = GateSitting(lesson: lesson.id, at: started, plan: plan, position: position, warmth: warmth, energy: energy, mealHours: mealHours,
                            before: before, after: after, happened: debrief, held: held, tooMuch: tooMuch, seconds: seconds, clickedOut: clickedOut ? true : nil)
        store.editCourse { c in
            c.sittings.append(s)
            if held, GateCourse.extraOpensAfter[lesson.id] == nil { c.held[lesson.id, default: 0] += 1 }
            if tooMuch { c.held[lesson.id] = 0 }
        }
        stage = .done
        cardPack = PackEarn.fresh("gate-\(lesson.id.lowercased())")
    }
}
