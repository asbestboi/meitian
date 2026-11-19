//! WeChat's built-in emoji. In WeChat they are typed and stored as codes in brackets ("哈哈[捂脸]"), and
//! that's how the chat stories write them too. The apps show them as the closest Unicode emoji and leave
//! them out when reading a message aloud.

/// (code, emoji). WeChat's own artwork belongs to Tencent, so these are look-alikes.
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
];

/// The emoji for a WeChat code, with or without its brackets ("[捂脸]" or "捂脸").
#[uniffi::export]
pub fn wechat_emoji(code: String) -> Option<String> {
    let c = code.trim().trim_start_matches('[').trim_end_matches(']');
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
}
