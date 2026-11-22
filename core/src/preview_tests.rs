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
