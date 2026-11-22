//! WeChat's built-in emoji. In WeChat they are typed and stored as codes in brackets ("哈哈[捂脸]"), and
//! that's how the chat stories write them too. The apps show WeChat's own pictures (© Tencent, from
//! emojiall.com/en/platform-wechat) and leave them out when reading a message aloud.

/// (code, emoji): the closest Unicode emoji, for places that can't draw a picture and for codes without artwork.
const WECHAT: &[(&str, &str)] = &[
    ("微笑", "🙂"), ("撇嘴", "😕"), ("色", "😍"), ("发呆", "😳"), ("得意", "😎"), ("流泪", "😢"),
    ("害羞", "☺️"), ("闭嘴", "🤐"), ("睡", "😴"), ("大哭", "😭"), ("尴尬", "😅"), ("发怒", "😡"),
    ("调皮", "😜"), ("呲牙", "😁"), ("惊讶", "😮"), ("难过", "🙁"), ("囧", "😖"), ("抓狂", "😫"),
    ("吐", "🤮"), ("偷笑", "🤭"), ("愉快", "😊"), ("白眼", "🙄"), ("傲慢", "😤"), ("困", "😪"),
    ("惊恐", "😱"), ("憨笑", "😄"), ("悠闲", "😌"), ("咒骂", "🤬"), ("疑问", "🤔"), ("嘘", "🤫"),
    ("晕", "😵"), ("衰", "😩"), ("骷髅", "💀"), ("敲打", "🔨"), ("再见", "👋"), ("擦汗", "😓"),
    ("抠鼻", "😑"), ("鼓掌", "👏"), ("坏笑", "😏"), ("鄙视", "😒"), ("委屈", "🥺"), ("快哭了", "🥹"),
    ("亲亲", "😘"), ("可怜", "🥺"), ("笑脸", "😀"), ("生病", "😷"), ("脸红", "😊"), ("破涕为笑", "😂"),
    ("恐惧", "😨"), ("失望", "😞"), ("无语", "😑"), ("嘿哈", "🤗"), ("捂脸", "🤦"), ("奸笑", "😏"),
    ("机智", "🤓"), ("皱眉", "😣"), ("耶", "✌️"), ("吃瓜", "🍉"), ("加油", "💪"), ("汗", "😓"),
    ("天啊", "😱"), ("Emm", "🤔"), ("社会社会", "🤙"), ("旺柴", "🐶"), ("好的", "👌"), ("打脸", "🤕"),
    ("哇", "🤩"), ("翻白眼", "🙄"), ("666", "🤘"), ("让我看看", "👀"), ("叹气", "😮‍💨"), ("苦涩", "🥲"),
    ("裂开", "💔"), ("嘴唇", "💋"), ("爱心", "❤️"), ("心碎", "💔"), ("拥抱", "🤗"), ("强", "👍"),
    ("弱", "👎"), ("握手", "🤝"), ("胜利", "✌️"), ("抱拳", "🙏"), ("拳头", "👊"), ("OK", "👌"),
    ("合十", "🙏"), ("啤酒", "🍺"), ("咖啡", "☕"), ("蛋糕", "🎂"), ("玫瑰", "🌹"), ("凋谢", "🥀"),
    ("菜刀", "🔪"), ("炸弹", "💣"), ("便便", "💩"), ("月亮", "🌙"), ("太阳", "☀️"), ("庆祝", "🎉"),
    ("礼物", "🎁"), ("红包", "🧧"), ("發", "🀄"), ("福", "🧧"), ("烟花", "🎆"), ("爆竹", "🧨"),
    ("猪头", "🐷"), ("跳跳", "💃"), ("发抖", "🥶"), ("转圈", "🌀"),
    ("酷", "😎"), ("奋斗", "💪"), ("勾引", "👈"), ("差劲", "👎"), ("NO", "🙅"), ("激动", "🤩"),
    ("回头", "🔙"), ("左太极", "☯️"), ("右太极", "☯️"), ("加油加油", "💪"), ("可爱", "😊"), ("饥饿", "😋"),
    ("流汗", "😓"), ("折磨", "😣"), ("糗大了", "😅"), ("左哼哼", "😤"), ("右哼哼", "😤"), ("哈欠", "🥱"),
    ("阴险", "😏"), ("吓", "😱"), ("西瓜", "🍉"), ("篮球", "🏀"), ("乒乓", "🏓"), ("饭", "🍚"),
    ("示爱", "💋"), ("闪电", "⚡"), ("刀", "🔪"), ("足球", "⚽"), ("赞", "👍"), ("踩", "👎"),
    ("爱你", "🤟"), ("爱情", "💑"), ("飞吻", "😘"), ("怄火", "😠"), ("磕头", "🙇"), ("挥手", "👋"),
    ("街舞", "💃"), ("献吻", "😗"), ("发", "🀄"), ("emm", "😑"), ("强壮", "💪"), ("鬼魂", "👻"),
    ("吐舌", "😝"), ("瓢虫", "🐞"), ("冷汗", "😰"),
];

/// (code, 64 × 64 PNG).
const ART: &[(&str, &[u8])] = &[
    ("微笑", include_bytes!("../data/wechat/1f642.png")),
    ("撇嘴", include_bytes!("../data/wechat/1f61f.png")),
    ("色", include_bytes!("../data/wechat/1f60d.png")),
    ("发呆", include_bytes!("../data/wechat/1f626.png")),
    ("得意", include_bytes!("../data/wechat/1f60e.png")),
    ("流泪", include_bytes!("../data/wechat/1f62d.png")),
    ("害羞", include_bytes!("../data/wechat/1f60a.png")),
    ("闭嘴", include_bytes!("../data/wechat/1f910.png")),
    ("睡", include_bytes!("../data/wechat/1f62a.png")),
    ("大哭", include_bytes!("../data/wechat/1f622.png")),
    ("尴尬", include_bytes!("../data/wechat/wx046.png")),
    ("发怒", include_bytes!("../data/wechat/1f621.png")),
    ("调皮", include_bytes!("../data/wechat/1f61b.png")),
    ("呲牙", include_bytes!("../data/wechat/1f601.png")),
    ("惊讶", include_bytes!("../data/wechat/1f632.png")),
    ("难过", include_bytes!("../data/wechat/1f641.png")),
    ("囧", include_bytes!("../data/wechat/1f630.png")),
    ("抓狂", include_bytes!("../data/wechat/1f62b.png")),
    ("吐", include_bytes!("../data/wechat/1f92e.png")),
    ("偷笑", include_bytes!("../data/wechat/1f92d.png")),
    ("愉快", include_bytes!("../data/wechat/1f60a-new.png")),
    ("白眼", include_bytes!("../data/wechat/1f644-new.png")),
    ("傲慢", include_bytes!("../data/wechat/1f615.png")),
    ("困", include_bytes!("../data/wechat/1f62a-new.png")),
    ("惊恐", include_bytes!("../data/wechat/1f628.png")),
    ("憨笑", include_bytes!("../data/wechat/1f600.png")),
    ("悠闲", include_bytes!("../data/wechat/1f6ac.png")),
    ("咒骂", include_bytes!("../data/wechat/1f92c.png")),
    ("疑问", include_bytes!("../data/wechat/wx068.png")),
    ("嘘", include_bytes!("../data/wechat/1f92b.png")),
    ("晕", include_bytes!("../data/wechat/1f635.png")),
    ("衰", include_bytes!("../data/wechat/1f622-new.png")),
    ("骷髅", include_bytes!("../data/wechat/1f480.png")),
    ("敲打", include_bytes!("../data/wechat/1f915.png")),
    ("再见", include_bytes!("../data/wechat/1f44b.png")),
    ("擦汗", include_bytes!("../data/wechat/wx076.png")),
    ("抠鼻", include_bytes!("../data/wechat/wx077.png")),
    ("鼓掌", include_bytes!("../data/wechat/1f44f.png")),
    ("坏笑", include_bytes!("../data/wechat/1f62c.png")),
    ("鄙视", include_bytes!("../data/wechat/wx084.png")),
    ("委屈", include_bytes!("../data/wechat/1f641-new.png")),
    ("快哭了", include_bytes!("../data/wechat/1f625.png")),
    ("亲亲", include_bytes!("../data/wechat/1f61a.png")),
    ("可怜", include_bytes!("../data/wechat/1f97a.png")),
    ("笑脸", include_bytes!("../data/wechat/1f604.png")),
    ("生病", include_bytes!("../data/wechat/1f637.png")),
    ("脸红", include_bytes!("../data/wechat/1f633.png")),
    ("破涕为笑", include_bytes!("../data/wechat/1f602.png")),
    ("恐惧", include_bytes!("../data/wechat/1f631-new.png")),
    ("失望", include_bytes!("../data/wechat/1f614.png")),
    ("无语", include_bytes!("../data/wechat/1f612.png")),
    ("嘿哈", include_bytes!("../data/wechat/wx004.png")),
    ("捂脸", include_bytes!("../data/wechat/wx005.png")),
    ("奸笑", include_bytes!("../data/wechat/wx003.png")),
    ("机智", include_bytes!("../data/wechat/wx006.png")),
    ("皱眉", include_bytes!("../data/wechat/1f97a-new.png")),
    ("耶", include_bytes!("../data/wechat/270c-new.png")),
    ("吃瓜", include_bytes!("../data/wechat/wx033.png")),
    ("加油", include_bytes!("../data/wechat/wx011.png")),
    ("汗", include_bytes!("../data/wechat/1f613-new.png")),
    ("天啊", include_bytes!("../data/wechat/1f632-new.png")),
    ("Emm", include_bytes!("../data/wechat/1f611-new.png")),
    ("社会社会", include_bytes!("../data/wechat/wx018.png")),
    ("旺柴", include_bytes!("../data/wechat/1f436.png")),
    ("好的", include_bytes!("../data/wechat/1f44c-new.png")),
    ("打脸", include_bytes!("../data/wechat/1f915-new.png")),
    ("哇", include_bytes!("../data/wechat/1f929.png")),
    ("翻白眼", include_bytes!("../data/wechat/1f644.png")),
    ("666", include_bytes!("../data/wechat/wx145.png")),
    ("让我看看", include_bytes!("../data/wechat/wx144.png")),
    ("叹气", include_bytes!("../data/wechat/wx143.png")),
    ("苦涩", include_bytes!("../data/wechat/wx142.png")),
    ("裂开", include_bytes!("../data/wechat/wx141.png")),
    ("嘴唇", include_bytes!("../data/wechat/1f444.png")),
    ("爱心", include_bytes!("../data/wechat/2764.png")),
    ("心碎", include_bytes!("../data/wechat/1f494.png")),
    ("拥抱", include_bytes!("../data/wechat/1f917.png")),
    ("强", include_bytes!("../data/wechat/1f44d.png")),
    ("弱", include_bytes!("../data/wechat/1f44e.png")),
    ("握手", include_bytes!("../data/wechat/1f91d.png")),
    ("胜利", include_bytes!("../data/wechat/270c.png")),
    ("抱拳", include_bytes!("../data/wechat/1f64f.png")),
    ("拳头", include_bytes!("../data/wechat/270a.png")),
    ("OK", include_bytes!("../data/wechat/1f44c.png")),
    ("合十", include_bytes!("../data/wechat/1f64f-new.png")),
    ("啤酒", include_bytes!("../data/wechat/1f37a.png")),
    ("咖啡", include_bytes!("../data/wechat/2615.png")),
    ("玫瑰", include_bytes!("../data/wechat/1f339.png")),
    ("凋谢", include_bytes!("../data/wechat/1f940.png")),
    ("菜刀", include_bytes!("../data/wechat/1f52a.png")),
    ("炸弹", include_bytes!("../data/wechat/1f4a3.png")),
    ("便便", include_bytes!("../data/wechat/1f4a9.png")),
    ("月亮", include_bytes!("../data/wechat/1f319.png")),
    ("太阳", include_bytes!("../data/wechat/1f31e.png")),
    ("庆祝", include_bytes!("../data/wechat/1f389.png")),
    ("礼物", include_bytes!("../data/wechat/1f381-new.png")),
    ("蛋糕", include_bytes!("../data/wechat/1f381.png")),
    ("红包", include_bytes!("../data/wechat/1f9e7.png")),
    ("發", include_bytes!("../data/wechat/1f005.png")),
    ("福", include_bytes!("../data/wechat/wx001.png")),
    ("猪头", include_bytes!("../data/wechat/1f437.png")),
    ("跳跳", include_bytes!("../data/wechat/wx128.png")),
    ("发抖", include_bytes!("../data/wechat/1f976.png")),
    ("转圈", include_bytes!("../data/wechat/wx131.png")),
    ("酷", include_bytes!("../data/wechat/wx052.png")),
    ("奋斗", include_bytes!("../data/wechat/wx066.png")),
    ("勾引", include_bytes!("../data/wechat/wx120.png")),
    ("差劲", include_bytes!("../data/wechat/wx122.png")),
    ("NO", include_bytes!("../data/wechat/wx124.png")),
    ("激动", include_bytes!("../data/wechat/wx136.png")),
    ("回头", include_bytes!("../data/wechat/wx133.png")),
    ("左太极", include_bytes!("../data/wechat/wx139.png")),
    ("右太极", include_bytes!("../data/wechat/wx140.png")),
    ("加油加油", include_bytes!("../data/wechat/wx014.png")),
    ("可爱", include_bytes!("../data/wechat/1f60a-new.png")),
    ("饥饿", include_bytes!("../data/wechat/1f60b.png")),
    ("流汗", include_bytes!("../data/wechat/1f613.png")),
    ("折磨", include_bytes!("../data/wechat/1f623.png")),
    ("糗大了", include_bytes!("../data/wechat/1f611.png")),
    ("左哼哼", include_bytes!("../data/wechat/1f624.png")),
    ("右哼哼", include_bytes!("../data/wechat/1f624-new.png")),
    ("哈欠", include_bytes!("../data/wechat/1f971.png")),
    ("阴险", include_bytes!("../data/wechat/1f60f.png")),
    ("吓", include_bytes!("../data/wechat/1f631.png")),
    ("西瓜", include_bytes!("../data/wechat/1f349.png")),
    ("篮球", include_bytes!("../data/wechat/1f3c0.png")),
    ("乒乓", include_bytes!("../data/wechat/1f3d3.png")),
    ("饭", include_bytes!("../data/wechat/1f35a.png")),
    ("示爱", include_bytes!("../data/wechat/1f444.png")),
    ("闪电", include_bytes!("../data/wechat/26a1.png")),
    ("刀", include_bytes!("../data/wechat/2694.png")),
    ("足球", include_bytes!("../data/wechat/26bd.png")),
    ("赞", include_bytes!("../data/wechat/1f44d.png")),
    ("踩", include_bytes!("../data/wechat/1f44e.png")),
    ("爱你", include_bytes!("../data/wechat/1f91f.png")),
    ("爱情", include_bytes!("../data/wechat/1f491.png")),
    ("飞吻", include_bytes!("../data/wechat/1f618.png")),
    ("怄火", include_bytes!("../data/wechat/1f620.png")),
    ("磕头", include_bytes!("../data/wechat/1f647.png")),
    ("挥手", include_bytes!("../data/wechat/1f44b-new.png")),
    ("街舞", include_bytes!("../data/wechat/1f483.png")),
    ("献吻", include_bytes!("../data/wechat/1f617.png")),
    ("发", include_bytes!("../data/wechat/1f005.png")),
    ("emm", include_bytes!("../data/wechat/1f611-new.png")),
    ("强壮", include_bytes!("../data/wechat/1f4aa.png")),
    ("鬼魂", include_bytes!("../data/wechat/1f47b.png")),
    ("吐舌", include_bytes!("../data/wechat/1f61d.png")),
    ("瓢虫", include_bytes!("../data/wechat/1f41e.png")),
    ("冷汗", include_bytes!("../data/wechat/1f630.png")),
];

fn bare(code: &str) -> &str {
    let c = code.trim();
    c.strip_prefix('[').and_then(|c| c.strip_suffix(']')).unwrap_or(c)
}

fn art(code: &str) -> Option<&'static [u8]> {
    let c = bare(code);
    ART.iter().find(|(k, _)| *k == c).map(|(_, b)| *b)
}

/// WeChat's own picture (PNG) for a code, with or without its brackets.
#[uniffi::export]
pub fn wechat_image(code: String) -> Option<Vec<u8>> {
    art(&code).map(<[u8]>::to_vec)
}

/// A piece of a chat message: plain text, or the code of a WeChat emoji that has a picture.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct TextPart {
    pub text: String,
    /// `text` is a code ("[捂脸]") to draw with `wechat_image`.
    pub emoji: bool,
}

/// Splits a message into text and WeChat pictures. Codes without a picture become the closest Unicode emoji.
#[uniffi::export]
pub fn text_parts(text: String) -> Vec<TextPart> {
    let mut out: Vec<TextPart> = vec![];
    let mut push = |text: &str, emoji: bool| match out.last_mut() {
        _ if text.is_empty() => {}
        Some(last) if !emoji && !last.emoji => last.text.push_str(text),
        _ => out.push(TextPart { text: text.into(), emoji }),
    };
    let mut rest = text.as_str();
    while let Some(open) = rest.find('[') {
        push(&rest[..open], false);
        let after = &rest[open..];
        let Some(close) = after.find(']') else {
            rest = after;
            break;
        };
        let code = &after[..=close];
        if art(code).is_some() {
            push(code, true);
        } else {
            push(&wechat_emoji(code.to_string()).unwrap_or_else(|| code.to_string()), false);
        }
        rest = &after[close + 1..];
    }
    push(rest, false);
    out
}

/// Keeps the codes that have a picture and turns the others into emoji.
pub(crate) fn keep_wechat(text: &str) -> String {
    if !text.contains('[') {
        return text.to_string();
    }
    text_parts(text.to_string()).into_iter().map(|p| p.text).collect()
}

/// The emoji for a WeChat code, with or without its brackets ("[捂脸]" or "捂脸").
#[uniffi::export]
pub fn wechat_emoji(code: String) -> Option<String> {
    let c = bare(&code);
    WECHAT.iter().find(|(k, _)| *k == c).map(|(_, e)| e.to_string())
}

/// Replaces every known "[code]" with its emoji; unknown brackets stay as they are.
pub fn render_wechat(text: &str) -> String {
    if !text.contains('[') {
        return text.to_string();
    }
    let mut out = String::with_capacity(text.len());
    let mut rest = text;
    while let Some(open) = rest.find('[') {
        out.push_str(&rest[..open]);
        let after = &rest[open..];
        match after.find(']') {
            Some(close) => {
                let code = &after[..=close];
                match wechat_emoji(code.to_string()) {
                    Some(e) => out.push_str(&e),
                    None => out.push_str(code),
                }
                rest = &after[close + 1..];
            }
            None => {
                out.push_str(after);
                rest = "";
            }
        }
    }
    out.push_str(rest);
    out
}

/// `render_wechat` for the apps: what screen readers say.
#[uniffi::export]
pub fn render_wechat_text(text: String) -> String {
    render_wechat(&text)
}

fn is_emoji(c: char) -> bool {
    let u = c as u32;
    (0x1F000..=0x1FAFF).contains(&u)
        || (0x2600..=0x27BF).contains(&u)
        || u == 0x200D
        || u == 0xFE0F
        || (0x2190..=0x21FF).contains(&u)
        || (0x2B00..=0x2BFF).contains(&u)
}

/// Text to read aloud: WeChat codes and emoji removed.
#[uniffi::export]
pub fn speakable(text: String) -> String {
    let rendered = render_wechat(&text);
    let s: String = rendered.chars().filter(|c| !is_emoji(*c)).collect();
    s.trim().to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn codes() {
        assert_eq!(render_wechat("哈哈哈[捂脸]"), "哈哈哈🤦");
        assert_eq!(render_wechat("[旺柴][旺柴]好的"), "🐶🐶好的");
        assert_eq!(render_wechat("[不存在]你好"), "[不存在]你好");
        assert_eq!(render_wechat("a[b"), "a[b");
        assert_eq!(wechat_emoji("[吃瓜]".into()).as_deref(), Some("🍉"));
        assert_eq!(speakable("太好了[庆祝]🎉！".into()), "太好了！");
        assert_eq!(speakable("[捂脸]".into()), "");
    }

    #[test]
    fn real_pictures() {
        for (code, png) in ART {
            assert_eq!(&png[1..4], b"PNG", "{code}");
            assert!(WECHAT.iter().any(|(k, _)| k == code), "{code} needs a text stand-in");
        }
        assert!(wechat_image("[捂脸]".into()).is_some() && wechat_image("旺柴".into()).is_some());
        assert!(wechat_image("[不存在]".into()).is_none() && wechat_image("捂脸]".into()).is_none());
        let part = |text: &str, emoji| TextPart { text: text.into(), emoji };
        assert_eq!(text_parts("哈哈[捂脸][旺柴]好".into()), vec![part("哈哈", false), part("[捂脸]", true), part("[旺柴]", true), part("好", false)]);
        // no picture for fireworks: the emoji joins the text around it
        assert_eq!(text_parts("看[烟花]！[不存在] a[b".into()), vec![part("看🎆！[不存在] a[b", false)]);
        assert!(text_parts(String::new()).is_empty());
        assert_eq!(keep_wechat("好[捂脸][烟花]"), "好[捂脸]🎆");
        let missing: Vec<&str> = WECHAT.iter().map(|(k, _)| *k).filter(|k| art(k).is_none()).collect();
        assert!(missing.len() <= 4, "{missing:?}");
    }
}
