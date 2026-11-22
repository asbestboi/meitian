import SwiftUI

/// Question + four options, for quick-fire rounds (Swear Sprint).
struct QuizPanel: View {
    let question: QuizQuestion
    var picked: Word?
    var locked: Bool
    /// Show which option was right (after the round).
    var reveal: Bool
    var compact = false
    var onPick: (Word) -> Void

    @AppStorage(PinyinPrefs.show) private var showPinyin = true

    var body: some View {
        VStack(spacing: compact ? 10 : 16) {
            Group {
                if question.kind == .listenToHanzi {
                    VStack(spacing: 6) {
                        SpeakButton(text: question.word.hanzi, size: compact ? 64 : 84, tint: Theme.jade)
                        Text("listen and tap it").font(.rounded(.caption, weight: .bold)).foregroundStyle(.secondary)
                    }
                    .onAppear { Speaker.shared.say(question.word.hanzi) }
                } else if question.kind == .hanziToMeaning {
                    RubyText(hanzi: question.word.hanzi, pinyin: question.word.pinyin,
                             size: compact ? 42 : (question.word.hanzi.count > 3 ? 48 : 60),
                             weight: .semibold, alignment: .center)
                } else {
                    Text("“\(question.word.shortMeaning)”")
                        .font(.rounded(compact ? .title2 : .title, weight: .bold))
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.5)
                }
            }
            .frame(maxWidth: .infinity, minHeight: compact ? 70 : 110)
            .padding(.vertical, compact ? 8 : 14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .id(question.id)
            .transition(.scale(scale: 0.9).combined(with: .opacity))

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(question.options) { option in optionButton(option) }
            }
        }
        .animation(Theme.bouncy, value: question.id)
    }

    private func optionButton(_ option: Word) -> some View {
        let isAnswer = option.id == question.word.id
        let isPicked = picked?.id == option.id
        let isHanzi = question.kind != .hanziToMeaning
        let bg: Color = reveal && isAnswer ? Theme.jade.opacity(0.22)
            : isPicked && !isAnswer ? Theme.red.opacity(0.2)
            : isPicked ? Theme.jade.opacity(0.22) : Theme.card
        let border: Color = reveal && isAnswer ? Theme.jade : isPicked ? (isAnswer ? Theme.jade : Theme.red) : .primary.opacity(0.08)
        return Button { onPick(option) } label: {
            VStack(spacing: 1) {
                Text(isHanzi ? option.hanzi : option.shortMeaning)
                    .font(isHanzi ? .hanzi(compact ? 24 : 28, weight: .medium) : .rounded(compact ? .subheadline : .headline, weight: .semibold))
                    .minimumScaleFactor(0.6)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                if isHanzi && showPinyin {
                    PinyinText(pinyin: option.pinyin, font: .rounded(.caption2, weight: .semibold)).lineLimit(1)
                }
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: compact ? 54 : 68)
            .padding(.horizontal, 6)
            .background(bg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(border, lineWidth: 2.5))
            .opacity(locked && !isPicked && !(reveal && isAnswer) ? 0.45 : 1)
        }
        .buttonStyle(PressableStyle())
        .disabled(locked || picked != nil)
    }
}
