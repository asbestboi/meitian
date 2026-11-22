//! Měitiān core: the logic shared by the iOS (Swift) and Android (Kotlin) apps.
//! Exposed to both through UniFFI; the UIs stay native.

uniffi::setup_scaffolding!();

pub mod arenas;
pub mod battle;
pub mod content;
mod draw;
pub mod effects;
pub mod exercises;
pub mod game;
pub mod hearts;
pub mod milestones;
pub mod online;
pub mod path;
pub mod pictures;
pub mod pinyin;
pub mod plan;
pub mod progress;
pub mod quests;
pub mod slots;
pub mod sounds;
pub mod stories;
pub mod vocab;
pub mod wechat;
pub mod words;

pub use arenas::*;
pub use battle::*;
pub use content::*;
pub use effects::*;
pub use exercises::*;
pub use game::*;
pub use hearts::*;
pub use milestones::*;
pub use online::*;
pub use path::*;
pub use pictures::*;
pub use pinyin::*;
pub use plan::*;
pub use progress::*;
pub use quests::*;
pub use slots::*;
pub use sounds::*;
pub use stories::*;
pub use vocab::*;
pub use wechat::*;
pub use words::*;

#[cfg(test)]
mod preview_tests;
