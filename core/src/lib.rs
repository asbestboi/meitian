//! Měitiān core: the logic shared by the iOS (Swift) and Android (Kotlin) apps.
//! Exposed to both through UniFFI; the UIs stay native.

uniffi::setup_scaffolding!();

pub mod challenge;
pub mod game;
pub mod pinyin;
pub mod progress;
pub mod words;

pub use challenge::*;
pub use game::*;
pub use pinyin::*;
pub use progress::*;
pub use words::*;
