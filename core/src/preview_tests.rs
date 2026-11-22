#[test]
#[ignore]
fn dump() {
    let d = std::env::var("PREVIEW_DIR").unwrap();
    for l in 1..=6u8 { for dark in [false, true] {
        let a = crate::arenas::arena_for(l, 6);
        let mut v: Vec<u8> = crate::arenas::arena_scene(a.clone(), 390.0, 844.0, dark).into_iter().flat_map(|x| x.ops).collect();
        v.extend(crate::arenas::arena_frame(a, 7300, 390.0, 844.0, dark));
        std::fs::write(format!("{d}/arena{l}{}.bin", if dark {"d"} else {"l"}), v).unwrap();
    }}
    for id in crate::effects::HIT_EFFECTS { for t in [230u32, 430, 620, 900] {
        std::fs::write(format!("{d}/{}-{t}.bin", &id[3..]), crate::effects::hit_frame(id.into(), t, 390.0, 500.0, 195.0, 430.0, 195.0, 170.0)).unwrap();
    }}
    for id in crate::effects::AURAS {
        std::fs::write(format!("{d}/au-{}.bin", &id[3..]), crate::effects::aura_frame(id.into(), 5210, 110.0, 110.0, 34.0)).unwrap();
    }
}

/// For every level and daily goal: which units end with a story that just became readable.
#[test]
#[ignore]
fn coverage() {
    let d = std::env::var("MEITIAN_CONTENT_DIST").unwrap();
    let read = |n: String| std::fs::read_to_string(format!("{d}/{n}")).unwrap();
    for n in 1..=6 {
        crate::content::content_load("words".into(), read(format!("words-{n}.json"))).unwrap();
    }
    crate::content::content_load("stories".into(), read("stories.json".into())).unwrap();
    for level in 1..=6u8 {
        for goal in [3u32, 5, 8] {
            let order = crate::plan::path_words(level, goal, vec![]);
            let unit = (goal * 5) as usize;
            let below = crate::vocab::known_word_ids(vec![], level - 1);
            let open = |n: usize| {
                let mut k = below.clone();
                k.extend(order[..n.min(order.len())].iter().cloned());
                crate::stories::shelf_stories("2026-01-01".into(), k).into_iter().filter(|s| s.unlocked && s.story.date.is_empty()).map(|s| s.story.id).collect::<std::collections::HashSet<_>>()
            };
            let units = order.len().div_ceil(unit);
            let start = open(0).len();
            let (mut last, mut row, mut empty) = (open(0), String::new(), 0);
            for u in 1..=units {
                let now = open(u * unit);
                let new = now.difference(&last).count();
                row += &format!("{}", if new > 9 { "+".into() } else { new.to_string() });
                if new == 0 && u < units { empty += 1 }
                last = now;
            }
            println!("HSK {level} goal {goal}: {units} units, {empty} without a new story; readable at the start {start}, at the end {}  {row}", last.len());
        }
    }
}
