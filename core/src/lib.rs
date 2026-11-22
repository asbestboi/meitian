//! Měitiān core: the logic shared by the iOS (Swift) and Android (Kotlin) apps.
//! Exposed to both through UniFFI; the UIs stay native.

uniffi::setup_scaffolding!();

pub mod challenge;
pub mod content;
pub mod effects;
pub mod exercises;
pub mod game;
pub mod hearts;
pub mod lan;
pub mod milestones;
pub mod online;
pub mod path;
pub mod pinyin;
pub mod progress;
pub mod quests;
pub mod stories;
pub mod vocab;
pub mod wechat;
pub mod words;

pub use challenge::*;
pub use content::*;
pub use effects::*;
pub use exercises::*;
pub use game::*;
pub use hearts::*;
pub use lan::*;
pub use milestones::*;
pub use online::*;
pub use path::*;
pub use pinyin::*;
pub use progress::*;
pub use quests::*;
pub use stories::*;
pub use vocab::*;
pub use wechat::*;
pub use words::*;
